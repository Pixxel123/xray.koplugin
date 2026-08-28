-- xray_presencemap_spec.lua
require("spec.spec_helper")
local presence = require("xray_presencemap")

describe("xray_presencemap", function()

    describe("buildPresenceMatrix", function()

        it("marks a character present in a chapter that names them", function()
            local timeline = {
                { chapter = "Chapter 1", event = "Victor recounts his childhood." },
            }
            local characters = {
                { name = "Victor Frankenstein", aliases = { "Victor" } },
            }
            local matrix = presence.buildPresenceMatrix(timeline, characters)
            assert.is_true(matrix[1]["Victor Frankenstein"])
        end)

        it("does not match a name that is only a substring of another word", function()
            local timeline = {
                { chapter = "Chapter 7", event = "William is dead." },
            }
            local characters = { { name = "Will", aliases = {} } }
            local matrix = presence.buildPresenceMatrix(timeline, characters)
            assert.is_nil(matrix[1]["Will"])
        end)

        it("counts a character named in the chapter title but not the event text", function()
            local timeline = {
                { chapter = "Walton's Letter", event = "The voyage north begins." },
            }
            local characters = { { name = "Walton", aliases = {} } }
            local matrix = presence.buildPresenceMatrix(timeline, characters)
            assert.is_true(matrix[1]["Walton"])
        end)

        it("builds one row per event it is given, in order", function()
            -- Filtering out prior-book events is the caller's job, so the row
            -- index always lines up with the caller's own event list.
            local timeline = {
                { chapter = "Chapter 1", event = "Victor begins." },
                { chapter = "Chapter 2", event = "Nobody in particular." },
                { chapter = "Chapter 3", event = "Victor returns." },
            }
            local characters = { { name = "Victor", aliases = {} } }
            local matrix = presence.buildPresenceMatrix(timeline, characters)
            assert.equals(3, #matrix)
            assert.is_true(matrix[1]["Victor"])
            assert.is_nil(matrix[2]["Victor"])
            assert.is_true(matrix[3]["Victor"])
        end)

        it("skips a character with no name rather than crashing", function()
            -- The AI can return an entry with aliases and no name; deduplication
            -- keeps it. Indexing the result table by a nil name would error.
            local timeline = { { chapter = "Chapter 1", event = "Victor walks." } }
            local characters = { { aliases = { "Victor" } }, { name = "Victor" } }
            local matrix = presence.buildPresenceMatrix(timeline, characters)
            assert.is_true(matrix[1]["Victor"])
        end)

        it("still matches when an alias repeats the name", function()
            -- The AI often lists the canonical name among the aliases. The
            -- duplicate needle is dropped, so the match must come from the one
            -- that is kept.
            local timeline = { { chapter = "Chapter 1", event = "Victor walks." } }
            local characters = { { name = "Victor", aliases = { "Victor", "victor" } } }
            local matrix = presence.buildPresenceMatrix(timeline, characters)
            assert.is_true(matrix[1]["Victor"])
        end)

        it("matches regardless of letter case", function()
            -- The plugin's other matchers are case-insensitive; a presence map
            -- that disagreed with Mentions about the same chapter would be worse
            -- than one that is slightly generous.
            local timeline = { { chapter = "Chapter 1", event = "the creature stirs." } }
            local characters = { { name = "The Creature", aliases = {} } }
            local matrix = presence.buildPresenceMatrix(timeline, characters)
            assert.is_true(matrix[1]["The Creature"])
        end)

        it("matches a character by surname when the text omits the first name", function()
            -- Prose says "Holden's crew", never "James Holden", and the AI's
            -- alias list does not always include the surname.
            local timeline = { { chapter = "Chapter 1", event = "Holden and the crew agree." } }
            local characters = { { name = "James Holden", aliases = { "Jim" } } }
            local matrix = presence.buildPresenceMatrix(timeline, characters)
            assert.is_true(matrix[1]["James Holden"])
        end)

        it("does not use a surname two characters share", function()
            -- A surname both siblings answer to identifies neither. Guessing
            -- would put one in every chapter that names the other.
            local timeline = { { chapter = "Chapter 1", event = "Holden waited." } }
            local characters = {
                { name = "James Holden", aliases = {} },
                { name = "Elise Holden", aliases = {} },
            }
            local matrix = presence.buildPresenceMatrix(timeline, characters)
            assert.is_nil(matrix[1]["James Holden"])
            assert.is_nil(matrix[1]["Elise Holden"])
        end)

        it("does not treat a short surname as a needle", function()
            -- "Poe" would fire on "poem"; the boundary check saves that one, but
            -- short surnames collide too readily to be worth guessing.
            local timeline = { { chapter = "Chapter 1", event = "Roe waited." } }
            local characters = { { name = "Alan Roe", aliases = {} } }
            local matrix = presence.buildPresenceMatrix(timeline, characters)
            assert.is_nil(matrix[1]["Alan Roe"])
        end)

    end)

    describe("coverageOrder", function()

        -- Victor in 3 chapters, Creature in 2, Walton in 1.
        local function sampleMatrix()
            return {
                [1] = { Victor = true },
                [2] = { Victor = true, Creature = true },
                [3] = { Victor = true, Creature = true, Walton = true },
            }
        end
        local sampleChars = {
            { name = "Walton" }, { name = "Creature" }, { name = "Victor" },
        }

        it("orders characters by how many chapters name each of them", function()
            assert.same({ "Victor", "Creature", "Walton" },
                        presence.coverageOrder(sampleMatrix(), sampleChars))
        end)

        it("drops characters who appear in no chapter", function()
            local chars = { { name = "Victor" }, { name = "Ghost" } }
            assert.same({ "Victor" },
                        presence.coverageOrder({ [1] = { Victor = true } }, chars))
        end)

        it("breaks equal coverage by earliest appearance, then by name", function()
            -- Ernest and Justine both have coverage 1; Justine appears first.
            local matrix = { [1] = { Justine = true }, [2] = { Ernest = true } }
            local chars = { { name = "Ernest" }, { name = "Justine" } }
            assert.same({ "Justine", "Ernest" }, presence.coverageOrder(matrix, chars))
        end)

        it("keeps everyone with any coverage when no minimum is given", function()
            -- Walton appears once and must survive the default call.
            assert.same({ "Victor", "Creature", "Walton" },
                        presence.coverageOrder(sampleMatrix(), sampleChars))
        end)

        it("drops characters below the minimum coverage", function()
            -- Four characters, three of them in two or more chapters.
            local matrix = {
                [1] = { Ann = true, Bob = true, Cal = true },
                [2] = { Ann = true, Bob = true, Cal = true },
                [3] = { Ann = true, Dot = true },
            }
            local chars = { { name = "Ann" }, { name = "Bob" }, { name = "Cal" }, { name = "Dot" } }
            assert.same({ "Ann", "Bob", "Cal" }, presence.coverageOrder(matrix, chars, 2))
        end)

        it("ignores the minimum when too few characters would survive it", function()
            -- Only Ann clears a minimum of 2. Filtering to one row would leave a
            -- book early in its reading with an almost empty map, so the whole
            -- order is kept instead.
            local matrix = {
                [1] = { Ann = true },
                [2] = { Ann = true, Bob = true },
                [3] = { Cal = true },
            }
            local chars = { { name = "Ann" }, { name = "Bob" }, { name = "Cal" } }
            assert.same({ "Ann", "Bob", "Cal" }, presence.coverageOrder(matrix, chars, 2))
        end)

        it("skips a nameless character rather than ranking them", function()
            -- buildPresenceMatrix tolerates a nameless AI entry, so this must
            -- too. Such an entry has no matrix key and so no coverage; it must
            -- not reach the sort, where it would be compared by name.
            local matrix = { [1] = { Victor = true } }
            local chars = { { aliases = { "Victor" } }, { name = "Victor" } }
            assert.same({ "Victor" }, presence.coverageOrder(matrix, chars))
        end)

        it("keeps a lead when only the second entry for that name carries the role", function()
            -- Two entries can share a name, and the role sits on whichever one
            -- the AI wrote it on. Reading only the first would drop a
            -- protagonist the minimum-coverage rule is meant to keep.
            local matrix = {
                [1] = { Lead = true, Ann = true, Bob = true, Cal = true },
                [2] = { Ann = true, Bob = true, Cal = true },
                [3] = { Ann = true, Bob = true, Cal = true },
            }
            local chars = {
                { name = "Lead" }, { name = "Lead", role = "Protagonist" },
                { name = "Ann" }, { name = "Bob" }, { name = "Cal" },
            }
            assert.same({ "Ann", "Bob", "Cal", "Lead" },
                        presence.coverageOrder(matrix, chars, 2))
        end)

        it("gives one row to a name held by two character entries", function()
            -- The matrix is keyed by name, so duplicates share a single key.
            -- Listing the name twice would draw two identical rows against one
            -- set of markers.
            local matrix = { [1] = { Victor = true } }
            local chars = { { name = "Victor" }, { name = "Victor" } }
            assert.same({ "Victor" }, presence.coverageOrder(matrix, chars))
        end)

        it("ignores a matrix key with no character behind it", function()
            -- Only the characters handed in get a row, so a stale key cannot
            -- add one the name gutter would not draw.
            local matrix = { [1] = { Victor = true, Stranger = true } }
            assert.same({ "Victor" }, presence.coverageOrder(matrix, { { name = "Victor" } }))
        end)

        it("keeps a protagonist below the minimum coverage", function()
            -- A lead who happens to appear in one chapter of what has been
            -- fetched so far is not a walk-on.
            -- Three others clear the minimum, so the MIN_FILTERED_ROWS floor
            -- does not fire and the lead is kept by the role rule alone.
            local matrix = {
                [1] = { Lead = true, Ann = true, Bob = true, Cal = true },
                [2] = { Ann = true, Bob = true, Cal = true },
                [3] = { Ann = true, Bob = true, Cal = true },
            }
            local chars = {
                { name = "Lead", role = "Protagonist" },
                { name = "Ann" }, { name = "Bob" }, { name = "Cal" },
            }
            assert.same({ "Ann", "Bob", "Cal", "Lead" },
                        presence.coverageOrder(matrix, chars, 2))
        end)

    end)

    describe("matchingChapters", function()

        -- Victor 1-3, Creature 2-3, Walton 3 only.
        local matrix = {
            [1] = { Victor = true },
            [2] = { Victor = true, Creature = true },
            [3] = { Victor = true, Creature = true, Walton = true },
        }

        it("returns every chapter when nothing is selected", function()
            assert.same({ 1, 2, 3 }, presence.matchingChapters(matrix, {}))
        end)

        it("returns the chapters holding a single selected character", function()
            assert.same({ 2, 3 }, presence.matchingChapters(matrix, { "Creature" }))
        end)

        it("returns only chapters holding every selected character", function()
            assert.same({ 3 }, presence.matchingChapters(matrix, { "Creature", "Walton" }))
        end)

        it("returns nothing when the selected characters never share a chapter", function()
            local apart = { [1] = { Ann = true }, [2] = { Bob = true } }
            assert.same({}, presence.matchingChapters(apart, { "Ann", "Bob" }))
        end)

    end)


    describe("split strip (frozen names, scrollable grid)", function()

        local GEOM = {
            name_width = 78, col_width = 26, row_height = 19,
            top_padding = 6, marker = 9, label_size = 8,
        }
        local matrix = {
            [1] = { Victor = true },
            [2] = { Victor = true, Creature = true },
            [3] = { Victor = true, Creature = true, Walton = true },
        }
        local chapters = { "Letter 1", "Chapter 1", "Chapter 2" }
        local order = { "Victor", "Creature", "Walton" }

        local function count(svg, class)
            local n = 0
            for _ in svg:gmatch('class="' .. class .. '"') do n = n + 1 end
            return n
        end

        describe("buildStripNamesSVG", function()

            it("is exactly the name gutter wide", function()
                local _, w = presence.buildStripNamesSVG(order, {}, GEOM)
                assert.equals(GEOM.name_width, w)
            end)

            it("writes every name when nothing is selected", function()
                local svg = presence.buildStripNamesSVG(order, {}, GEOM)
                for _, n in ipairs(order) do
                    assert.is_not_nil(svg:find(">" .. n .. "<", 1, true))
                end
            end)

            it("writes only the selected names when filtering", function()
                local svg = presence.buildStripNamesSVG(order, { "Victor" }, GEOM)
                assert.is_not_nil(svg:find(">Victor<", 1, true))
                assert.is_nil(svg:find(">Walton<", 1, true))
            end)

        end)

        describe("buildStripGridSVG", function()

            it("is exactly the columns wide, with no name gutter", function()
                local _, w = presence.buildStripGridSVG(matrix, order, chapters, {}, GEOM,
                    presence.matchingChapters(matrix, {}))
                assert.equals(#chapters * GEOM.col_width, w)
            end)

            it("keeps its own height in step with the names", function()
                local _, _, gh = presence.buildStripGridSVG(matrix, order, chapters, {}, GEOM,
                    presence.matchingChapters(matrix, {}))
                local _, _, nh = presence.buildStripNamesSVG(order, {}, GEOM)
                assert.equals(nh, gh)
            end)

            it("draws a marker for every appearance", function()
                local svg = presence.buildStripGridSVG(matrix, order, chapters, {}, GEOM,
                    presence.matchingChapters(matrix, {}))
                assert.equals(6, count(svg, "pip"))
            end)

            it("shades and joins the columns holding all selected characters", function()
                local svg = presence.buildStripGridSVG(matrix, order, chapters, { "Creature", "Walton" }, GEOM,
                    presence.matchingChapters(matrix, { "Creature", "Walton" }))
                assert.equals(1, count(svg, "shade"))
                assert.equals(1, count(svg, "join"))
            end)

            it("uses caller-supplied matches when given", function()
                -- Bucketed crossings are worked out per chapter, so the renderer
                -- must be told which columns matched rather than deriving them.
                local svg = presence.buildStripGridSVG(matrix, order, chapters,
                    { "Victor", "Creature" }, GEOM, { 1 })
                assert.equals(1, count(svg, "shade"))
                -- column 1 is the shaded one, not column 3 as derivation would give
                local x = tonumber(svg:match('class="shade" x="([%-%d%.]+)"'))
                assert.is_true(x < GEOM.col_width)
            end)

            it("draws no join for a single selected character", function()
                local svg = presence.buildStripGridSVG(matrix, order, chapters, { "Victor" }, GEOM,
                    presence.matchingChapters(matrix, { "Victor" }))
                assert.equals(0, count(svg, "join"))
            end)

            it("places the first column at the very left edge", function()
                -- No name gutter, so the grid can be scrolled independently.
                local svg = presence.buildStripGridSVG(matrix, order, chapters, {}, GEOM,
                    presence.matchingChapters(matrix, {}))
                local first_x = tonumber(svg:match('class="pip" x="([%d%.]+)"'))
                assert.is_true(first_x < GEOM.col_width)
            end)

        end)
    end)

    describe("bucketMatrix", function()

        -- 9 chapters. Ann is in 1 and 5; Bob is in 3 and 5. They share only 5.
        local matrix = {}
        for i = 1, 9 do matrix[i] = {} end
        matrix[1].Ann = true
        matrix[3].Bob = true
        matrix[5].Ann = true
        matrix[5].Bob = true

        it("collapses chapters into the requested number of columns", function()
            local buckets = presence.bucketMatrix(matrix, {}, 3)
            assert.equals(3, #buckets)
        end)

        it("covers every chapter across the ranges, with no gap or overlap", function()
            local _, _, ranges = presence.bucketMatrix(matrix, {}, 3)
            assert.equals(1, ranges[1].first)
            assert.equals(9, ranges[#ranges].last)
            for i = 2, #ranges do
                assert.equals(ranges[i - 1].last + 1, ranges[i].first)
            end
        end)

        it("marks a character present if they appear anywhere in the span", function()
            -- span 1 covers chapters 1-3, and Ann is in chapter 1
            local buckets = presence.bucketMatrix(matrix, {}, 3)
            assert.is_true(buckets[1].Ann)
        end)

        it("leaves a span empty for a character who never appears in it", function()
            -- span 3 covers chapters 7-9, where nobody appears
            local buckets = presence.bucketMatrix(matrix, {}, 3)
            assert.is_nil(buckets[3].Ann)
        end)

        it("reports a crossing only where the characters share one chapter", function()
            -- span 2 covers 4-6 and both are in chapter 5
            local _, matches = presence.bucketMatrix(matrix, presence.matchingChapters(matrix, { "Ann", "Bob" }), 3)
            assert.same({ 2 }, matches)
        end)

        it("does not report a crossing when they merely fall in the same span", function()
            -- Chapters 1-3 hold Ann (1) and Bob (3): both present in span 1, but
            -- never in the same chapter. Bucketing presence first would say they met.
            local apart = {}
            for i = 1, 9 do apart[i] = {} end
            apart[1].Ann = true
            apart[3].Bob = true
            local buckets, matches = presence.bucketMatrix(apart, presence.matchingChapters(apart, { "Ann", "Bob" }), 3)
            assert.is_true(buckets[1].Ann)
            assert.is_true(buckets[1].Bob)
            assert.same({}, matches)
        end)

        it("returns no columns at all for a book with no chapters", function()
            -- A timeline holding only prior-book events leaves an empty matrix.
            -- The column count is floored at one, which would otherwise hand
            -- back a bucket spanning a chapter that does not exist.
            local buckets, matches, ranges = presence.bucketMatrix({}, {}, 5)
            assert.same({}, buckets)
            assert.same({}, matches)
            assert.same({}, ranges)
        end)

        it("passes a short book through one chapter per column", function()
            local buckets, _, ranges = presence.bucketMatrix(matrix, {}, 20)
            assert.equals(9, #buckets)
            assert.equals(1, ranges[1].first)
            assert.equals(1, ranges[1].last)
        end)

    end)
end)
