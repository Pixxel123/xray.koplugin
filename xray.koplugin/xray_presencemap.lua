-- Timeline presence map: pure layout logic, no UI dependencies.
-- Stateless, so M.name() not M:name(). Required directly, like xray_theme.
-- Name matching duplicates ChapterAnalyzer:findCharactersInText and is
-- case-insensitive to agree with it. No dependencies, so the spec can run
-- outside KOReader.
local M = {}

local BYTE_0, BYTE_9 = string.byte("0"), string.byte("9")
local BYTE_A, BYTE_Z = string.byte("A"), string.byte("Z")
local BYTE_a, BYTE_z = string.byte("a"), string.byte("z")
local BYTE_UNDERSCORE = string.byte("_")

-- ASCII only. CJK bytes are never word characters, so the boundary checks
-- always pass and matching falls back to plain substring search.
local function isWordByte(b)
    return b ~= nil and (
        (b >= BYTE_0 and b <= BYTE_9) or
        (b >= BYTE_A and b <= BYTE_Z) or
        (b >= BYTE_a and b <= BYTE_z) or
        b == BYTE_UNDERSCORE)
end

-- Whether the AI labelled this character a lead. The role field is free text,
-- so this is a hint, never a ranking.
local function isLead(role)
    return type(role) == "string" and role:lower():find("protagonist", 1, true) ~= nil
end

-- The last word of a multi-word name. Prose leans on surnames ("Holden's crew")
-- and the AI's alias list often omits them. Short ones collide too often to
-- guess from, so they are skipped, as in xray_data's frequency scorer.
local function surnameOf(name)
    if type(name) ~= "string" then return nil end
    local last = name:match("(%S+)$")
    if last and #last > 3 and last ~= name then return last end
    return nil
end

-- Lower-cased once per call rather than per chapter. Duplicates are dropped:
-- an alias that repeats the canonical name or the surname would otherwise buy a
-- second scan of every chapter for an answer the first scan already gave.
local function needlesFor(character, own_surname)
    local needles, seen = {}, {}
    local function add(text)
        if type(text) ~= "string" or text == "" then return end
        local lowered = text:lower()
        if seen[lowered] then return end
        seen[lowered] = true
        needles[#needles + 1] = {
            text = lowered,
            starts_word = isWordByte(lowered:byte(1)),
            ends_word = isWordByte(lowered:byte(#lowered)),
        }
    end
    add(character.name)
    for _, alias in ipairs(character.aliases or {}) do add(alias) end
    add(own_surname)
    return needles
end

-- Plain find, not a pattern, so names with metacharacters need no escaping.
-- Only an end that is itself a word character needs a boundary check, so a
-- name ending in ")" still matches.
local function containsNeedle(text, needle)
    local from = 1
    local len = #text
    while true do
        local s, e = text:find(needle.text, from, true)
        if not s then return false end
        local ok_before = not needle.starts_word or not isWordByte(text:byte(s - 1))
        local ok_after = not needle.ends_word or
            (e >= len or not isWordByte(text:byte(e + 1)))
        if ok_before and ok_after then return true end
        from = s + 1
    end
end

-- Which tracked characters are named in each event.
-- Returns matrix[row][character_name] = true.
-- The caller supplies already-filtered events, so row N is its event N.
-- Both the chapter title and the summary are searched.
function M.buildPresenceMatrix(events, characters)
    -- The name is this matrix's key, so a nameless entry is skipped.
    -- A surname shared by two characters identifies neither, so it is only a
    -- needle when one character owns it.
    local surnames, owners = {}, {}
    for i, character in ipairs(characters or {}) do
        local surname = surnameOf(character.name)
        surnames[i] = surname
        if surname then
            local key = surname:lower()
            owners[key] = (owners[key] or 0) + 1
        end
    end

    local needles = {}
    for i, character in ipairs(characters or {}) do
        if type(character.name) == "string" and character.name ~= "" then
            local surname = surnames[i]
            if surname and owners[surname:lower()] ~= 1 then surname = nil end
            needles[#needles + 1] =
                { name = character.name, list = needlesFor(character, surname) }
        end
    end

    local matrix = {}
    for row, entry in ipairs(events or {}) do
        local cell = {}
        local text = ((entry.chapter or "") .. "\n" .. (entry.event or "")):lower()
        for _, character in ipairs(needles) do
            for _, needle in ipairs(character.list) do
                if containsNeedle(text, needle) then
                    cell[character.name] = true
                    break
                end
            end
        end
        matrix[row] = cell
    end
    return matrix
end

-- Below this many characters, min_coverage is ignored. See coverageOrder.
local MIN_FILTERED_ROWS = 3

-- Characters that appear at all, most-present first. Shared by the filter
-- buttons, name gutter and grid rows, so a position always means the same
-- character. Ties break by first appearance then name, so the order does not
-- shuffle between rebuilds.
--
-- min_coverage drops walk-ons named in fewer than that many chapters, and
-- defaults to 1, which keeps everyone. It is ignored when fewer than
-- MIN_FILTERED_ROWS characters would survive: early in a book almost everyone
-- appears once, and an empty map is worse than a crowded one. A lead is kept
-- either way, since appearing in one fetched chapter does not make them minor.
function M.coverageOrder(matrix, characters, min_coverage)
    -- Keyed by name, matching the matrix, so two entries sharing one name draw
    -- one row rather than two identical ones. The same non-empty-string check
    -- as buildPresenceMatrix, so a nameless AI entry is skipped by both.
    -- lead is the union across those entries: the role sits on whichever one
    -- the AI wrote it on, and taking only the first would drop a protagonist
    -- the rule below is meant to keep.
    local by_name, entries = {}, {}
    for _, character in ipairs(characters or {}) do
        local name = character.name
        if type(name) == "string" and name ~= "" then
            local entry = by_name[name]
            if not entry then
                entry = { name = name, coverage = 0, first = nil, lead = false }
                by_name[name] = entry
                entries[#entries + 1] = entry
            end
            if isLead(character.role) then entry.lead = true end
        end
    end

    -- One pass over the matrix rather than a rescan per character. Rows are
    -- visited in order, so the first row to name someone is their first.
    for row = 1, #matrix do
        for name in pairs(matrix[row] or {}) do
            local entry = by_name[name]
            if entry then
                entry.coverage = entry.coverage + 1
                entry.first = entry.first or row
            end
        end
    end

    local stats = {}
    for _, entry in ipairs(entries) do
        if entry.coverage > 0 then stats[#stats + 1] = entry end
    end

    table.sort(stats, function(a, b)
        if a.coverage ~= b.coverage then return a.coverage > b.coverage end
        if a.first ~= b.first then return a.first < b.first end
        return a.name < b.name
    end)

    local order, kept = {}, {}
    for i, entry in ipairs(stats) do
        order[i] = entry.name
        if entry.coverage >= (min_coverage or 1) or entry.lead then
            kept[#kept + 1] = entry.name
        end
    end
    if #kept >= MIN_FILTERED_ROWS then return kept end
    return order
end

-- Ascending row indices where every selected character is present.
-- An empty selection means all rows.
function M.matchingChapters(matrix, selected)
    local out = {}
    for row = 1, #matrix do
        local all_present = true
        for _, name in ipairs(selected or {}) do
            if not (matrix[row] and matrix[row][name]) then
                all_present = false
                break
            end
        end
        if all_present then out[#out + 1] = row end
    end
    return out
end

-- Collapse a chapter-level matrix into at most n_buckets columns, so a long
-- book fits the screen without scrolling sideways.
-- chapter_matches is the row list from matchingChapters.
-- Returns the bucketed matrix, the matching bucket indices, and the ranges.
--
-- Presence can be bucketed, but crossings cannot. That is why this takes an
-- already resolved list of matching chapters rather than a selection.
-- Two characters in different chapters of one span have not met, so working
-- the crossings out from the bucketed matrix would report a meeting that
-- never happened.
function M.bucketMatrix(matrix, chapter_matches, n_buckets)
    local nrows = #matrix
    -- No chapters means no columns. The clamp below floors the count at one,
    -- which would otherwise invent a bucket spanning a chapter that is not there.
    if nrows == 0 then return {}, {}, {} end
    n_buckets = math.max(1, math.min(n_buckets or nrows, nrows))

    local matched_row = {}
    for _, idx in ipairs(chapter_matches or {}) do matched_row[idx] = true end

    local buckets, matches, ranges = {}, {}, {}
    for b = 1, n_buckets do
        -- Spread any remainder evenly rather than piling it into the last span.
        local first = math.floor((b - 1) * nrows / n_buckets) + 1
        local last = math.floor(b * nrows / n_buckets)
        if last < first then last = first end
        ranges[b] = { first = first, last = last }

        local cell, crossed = {}, false
        for row = first, last do
            for name in pairs(matrix[row] or {}) do cell[name] = true end
            if matched_row[row] then crossed = true end
        end
        buckets[b] = cell
        if crossed then matches[#matches + 1] = b end
    end

    return buckets, matches, ranges
end

-- Which characters get a row: the selection, or everyone when unfiltered.
-- Shared with the UI's height calculation so the two cannot disagree.
function M.shownNames(order, selected)
    if not selected or #selected == 0 then return order end
    local is_selected = {}
    for _, name in ipairs(selected) do is_selected[name] = true end
    local rows = {}
    for _, name in ipairs(order) do
        if is_selected[name] then rows[#rows + 1] = name end
    end
    return rows
end

-- Pixel height of a strip with this many character rows. Exported so the UI's
-- scroll cap cannot drift from what the renderers draw.
function M.stripHeight(n_rows, geom)
    return geom.top_padding + n_rows * geom.row_height + 4
end

local XML_ESCAPES = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;" }

local function xmlEscape(text)
    return (tostring(text):gsub('[&<>"]', XML_ESCAPES))
end

local function svgOpen(w, h)
    return {
        string.format(
            '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">',
            w, h, w, h),
        string.format('<rect class="bg" x="0" y="0" width="%d" height="%d" fill="white"/>', w, h),
    }
end

-- The left gutter: one name per row. Split from the grid so it stays put while
-- the grid scrolls. Returns svg, width, height.
function M.buildStripNamesSVG(order, selected, geom)
    local rows = M.shownNames(order, selected)
    local width, height = geom.name_width, M.stripHeight(#rows, geom)
    local out = svgOpen(width, height)
    for r, name in ipairs(rows) do
        local y = geom.top_padding + (r - 1) * geom.row_height + geom.row_height / 2
        out[#out + 1] = string.format(
            '<text class="cname" x="%.1f" y="%.1f" font-size="%d" text-anchor="end" fill="black">%s</text>',
            width - 7, y + 3, geom.label_size + 2, xmlEscape(name))
    end
    out[#out + 1] = "</svg>"
    return table.concat(out, "\n"), width, height
end

-- The grid: columns as chapters (or bucketed spans), one row per shown name.
-- Returns svg, width, height.
--
-- Every column is kept while filtering, to show where in the book the matches
-- fall. Matching columns are shaded. Two or more selections draw a join line,
-- which is safe because only selected characters have rows here.
--
-- match_cols must be passed in. A bucketed matrix has already lost the
-- per-chapter detail, so the crossings cannot be worked out here.
function M.buildStripGridSVG(matrix, order, chapters, selected, geom, match_cols)
    local rows = M.shownNames(order, selected)
    local filtering = selected and #selected > 0

    local matches = {}
    for _, idx in ipairs(match_cols or {}) do matches[idx] = true end

    local ncols = #chapters
    local width, height = ncols * geom.col_width, M.stripHeight(#rows, geom)
    local out = svgOpen(width, height)

    local function colX(i) return (i - 1) * geom.col_width + geom.col_width / 2 end
    local function rowY(r)
        return geom.top_padding + (r - 1) * geom.row_height + geom.row_height / 2
    end

    if filtering then
        local join = #rows >= 2
        for i = 1, ncols do
            if matches[i] then
                out[#out + 1] = string.format(
                    '<rect class="shade" x="%.1f" y="%.1f" width="%d" height="%.1f" fill="#e3e6df"/>',
                    colX(i) - geom.col_width / 2, geom.top_padding - 4,
                    geom.col_width, #rows * geom.row_height + 4)
                if join then
                    out[#out + 1] = string.format(
                        '<line class="join" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="black" stroke-width="2"/>',
                        colX(i), rowY(1), colX(i), rowY(#rows))
                end
            end
        end
    end

    for r, name in ipairs(rows) do
        for i = 1, ncols do
            if matrix[i] and matrix[i][name] then
                out[#out + 1] = string.format(
                    '<rect class="pip" x="%.1f" y="%.1f" width="%d" height="%d" fill="black"/>',
                    colX(i) - geom.marker / 2, rowY(r) - geom.marker / 2,
                    geom.marker, geom.marker)
            end
        end
    end

    out[#out + 1] = "</svg>"
    return table.concat(out, "\n"), width, height
end

return M
