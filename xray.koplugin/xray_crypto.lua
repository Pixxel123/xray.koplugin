-- xray_crypto.lua
-- Cryptographic helper module for KOReader X-Ray Plugin (AES-256-GCM / SHA-256)
local ffi = require("ffi")

ffi.cdef[[
typedef struct evp_cipher_ctx_st EVP_CIPHER_CTX;
typedef struct evp_cipher_st EVP_CIPHER;

EVP_CIPHER_CTX *EVP_CIPHER_CTX_new(void);
void EVP_CIPHER_CTX_free(EVP_CIPHER_CTX *c);
const EVP_CIPHER *EVP_aes_256_gcm(void);
int EVP_EncryptInit_ex(EVP_CIPHER_CTX *ctx, const EVP_CIPHER *cipher, void *impl, const unsigned char *key, const unsigned char *iv);
int EVP_EncryptUpdate(EVP_CIPHER_CTX *ctx, unsigned char *out, int *outl, const unsigned char *in, int inl);
int EVP_EncryptFinal_ex(EVP_CIPHER_CTX *ctx, unsigned char *out, int *outl);
int EVP_DecryptInit_ex(EVP_CIPHER_CTX *ctx, const EVP_CIPHER *cipher, void *impl, const unsigned char *key, const unsigned char *iv);
int EVP_DecryptUpdate(EVP_CIPHER_CTX *ctx, unsigned char *out, int *outl, const unsigned char *in, int inl);
int EVP_DecryptFinal_ex(EVP_CIPHER_CTX *ctx, unsigned char *out, int *outl);
int EVP_CIPHER_CTX_ctrl(EVP_CIPHER_CTX *ctx, int type, int arg, void *ptr);

unsigned char *SHA256(const unsigned char *d, size_t n, unsigned char *md);
int RAND_bytes(unsigned char *buf, int num);
]]

local M = {}
local libcrypto = nil

local function getLibCrypto()
    if libcrypto then return libcrypto end
    local candidates = {
        "/usr/lib/koreader/libs/libcrypto.so.57",
        "/usr/lib/koreader/libs/libcrypto.so",
        "libcrypto.so.3",
        "libcrypto.so.1.1",
        "libcrypto.so",
        "crypto"
    }
    for _, path in ipairs(candidates) do
        local ok, lib = pcall(ffi.load, path)
        if ok and lib then
            libcrypto = lib
            return libcrypto
        end
    end
    -- Fallback to global C namespace
    pcall(function() libcrypto = ffi.C end)
    return libcrypto
end

-- Base64 Decoding
local b64_chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local b64_lookup = {}
for i = 1, #b64_chars do
    b64_lookup[b64_chars:sub(i, i)] = i - 1
end

function M:base64_decode(data)
    if not data or data == "" then return "" end
    data = data:gsub('[^'..b64_chars..'=]', '')
    return (data:gsub('..?.?.?', function(x)
        if #x == 0 then return '' end
        local c = 0
        for i = 1, 4 do
            local ch = x:sub(i, i)
            local v = b64_lookup[ch] or 0
            c = c * 64 + v
        end
        local pad = 0
        if x:sub(4, 4) == '=' then pad = 1 end
        if x:sub(3, 3) == '=' then pad = 2 end
        
        local b1 = math.floor(c / 65536) % 256
        local b2 = math.floor(c / 256) % 256
        local b3 = c % 256
        if pad == 2 then
            return string.char(b1)
        elseif pad == 1 then
            return string.char(b1, b2)
        else
            return string.char(b1, b2, b3)
        end
    end))
end

-- Hex string to binary bytes
function M:hexToBytes(hex)
    if not hex then return "" end
    hex = hex:gsub("%s+", "")
    return (hex:gsub('..', function(cc)
        return string.char(tonumber(cc, 16) or 0)
    end))
end

-- Binary bytes to Hex string
function M:bytesToHex(bytes)
    if not bytes then return "" end
    return (bytes:gsub('.', function(c)
        return string.format('%02x', string.byte(c))
    end))
end

-- Generate cryptographically random 32-byte (256-bit) Hex Secret
function M:generateSecretHex()
    local lib = getLibCrypto()
    local buf = ffi.new("unsigned char[32]")
    local ok = false
    if lib and lib.RAND_bytes then
        local ret = pcall(function() return lib.RAND_bytes(buf, 32) end)
        if ret then ok = true end
    end
    if not ok then
        -- Fallback pseudo-random generation
        for i = 0, 31 do
            buf[i] = math.random(0, 255)
        end
    end
    local str = ffi.string(buf, 32)
    return self:bytesToHex(str)
end

local bit = bit or bit32 or require("bit")
local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local rshift, lshift = bit.rshift, bit.lshift

local function ror(x, n)
    return bor(rshift(x, n), lshift(x, 32 - n))
end

-- SHA-256 round constants
local K_SHA256 = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
}

local function sha256_pure(msg)
    local H0, H1, H2, H3, H4, H5, H6, H7 =
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19

    local len = #msg
    local bit_len = len * 8
    local pad_len = 64 - ((len + 9) % 64)
    if pad_len == 64 then pad_len = 0 end

    local padded = msg .. "\128" .. string.rep("\0", pad_len)
    local high_len = math.floor(bit_len / 4294967296)
    local low_len = bit_len % 4294967296
    padded = padded .. string.char(
        rshift(high_len, 24), band(rshift(high_len, 16), 0xff), band(rshift(high_len, 8), 0xff), band(high_len, 0xff),
        rshift(low_len, 24), band(rshift(low_len, 16), 0xff), band(rshift(low_len, 8), 0xff), band(low_len, 0xff)
    )

    local W = {}
    for chunk = 1, #padded, 64 do
        for i = 0, 15 do
            local o = chunk + i * 4
            W[i + 1] = bor(
                lshift(padded:byte(o), 24),
                lshift(padded:byte(o + 1), 16),
                lshift(padded:byte(o + 2), 8),
                padded:byte(o + 3)
            )
        end
        for i = 17, 64 do
            local s0 = bxor(ror(W[i - 15], 7), ror(W[i - 15], 18), rshift(W[i - 15], 3))
            local s1 = bxor(ror(W[i - 2], 17), ror(W[i - 2], 19), rshift(W[i - 2], 10))
            W[i] = band(W[i - 16] + s0 + W[i - 7] + s1, 0xffffffff)
        end

        local a, b, c, d, e, f, g, h = H0, H1, H2, H3, H4, H5, H6, H7
        for i = 1, 64 do
            local S1 = bxor(ror(e, 6), ror(e, 11), ror(e, 25))
            local ch = bxor(band(e, f), band(bnot(e), g))
            local temp1 = band(h + S1 + ch + K_SHA256[i] + W[i], 0xffffffff)
            local S0 = bxor(ror(a, 2), ror(a, 13), ror(a, 22))
            local maj = bxor(band(a, b), band(a, c), band(b, c))
            local temp2 = band(S0 + maj, 0xffffffff)

            h = g
            g = f
            f = e
            e = band(d + temp1, 0xffffffff)
            d = c
            c = b
            b = a
            a = band(temp1 + temp2, 0xffffffff)
        end

        H0 = band(H0 + a, 0xffffffff)
        H1 = band(H1 + b, 0xffffffff)
        H2 = band(H2 + c, 0xffffffff)
        H3 = band(H3 + d, 0xffffffff)
        H4 = band(H4 + e, 0xffffffff)
        H5 = band(H5 + f, 0xffffffff)
        H6 = band(H6 + g, 0xffffffff)
        H7 = band(H7 + h, 0xffffffff)
    end

    local function word_to_bytes(w)
        return string.char(band(rshift(w, 24), 0xff), band(rshift(w, 16), 0xff), band(rshift(w, 8), 0xff), band(w, 0xff))
    end

    return word_to_bytes(H0) .. word_to_bytes(H1) .. word_to_bytes(H2) .. word_to_bytes(H3) ..
           word_to_bytes(H4) .. word_to_bytes(H5) .. word_to_bytes(H6) .. word_to_bytes(H7)
end

local function hmac_sha256_pure(key, msg)
    if #key > 64 then key = sha256_pure(key) end
    if #key < 64 then key = key .. string.rep("\0", 64 - #key) end
    local o_key_pad = ""
    local i_key_pad = ""
    for i = 1, 64 do
        local b = key:byte(i)
        o_key_pad = o_key_pad .. string.char(bxor(b, 0x5c))
        i_key_pad = i_key_pad .. string.char(bxor(b, 0x36))
    end
    return sha256_pure(o_key_pad .. sha256_pure(i_key_pad .. msg))
end

-- SHA-256 Hash of string -> 32 binary bytes
function M:sha256(data)
    local lib = getLibCrypto()
    if lib and lib.SHA256 then
        local ok, res = pcall(function()
            local md = ffi.new("unsigned char[32]")
            lib.SHA256(data, #data, md)
            return ffi.string(md, 32)
        end)
        if ok and res then return res end
    end
    return sha256_pure(data)
end

function M:hmac_sha256(key, data)
    return hmac_sha256_pure(key, data)
end

-- Pure Lua HMAC-SHA256 Stream Cipher Decryption
-- Format: [16 bytes IV] + [16 bytes Tag] + [Ciphertext]
function M:decryptHMACStream(raw, key_bytes)
    if not raw or #raw < 33 then return nil, "Invalid HMAC payload length" end
    local iv = raw:sub(1, 16)
    local tag = raw:sub(17, 32)
    local ciphertext = raw:sub(33)

    local expected_tag = hmac_sha256_pure(key_bytes, "AUTH" .. iv .. ciphertext):sub(1, 16)
    if tag ~= expected_tag then
        return nil, "HMAC auth tag verification failed"
    end

    local keystream = ""
    local counter = 0
    while #keystream < #ciphertext do
        local c_bytes = string.char(band(rshift(counter, 24), 0xff), band(rshift(counter, 16), 0xff), band(rshift(counter, 8), 0xff), band(counter, 0xff))
        local block = hmac_sha256_pure(key_bytes, iv .. c_bytes)
        keystream = keystream .. block
        counter = counter + 1
    end

    local plaintext = ""
    for i = 1, #ciphertext do
        plaintext = plaintext .. string.char(bxor(ciphertext:byte(i), keystream:byte(i)))
    end

    return plaintext
end

-- Decrypt Base64 Encrypted Payload (Dual: Pure Lua HMAC Stream + OpenSSL AES-256-GCM)
function M:decryptPayload(b64_payload, hex_secret, session_id)
    if not b64_payload or b64_payload == "" then
        return nil, "Empty payload"
    end

    local is_hmac_stream = b64_payload:match("^HMAC:") ~= nil
    local clean_b64 = b64_payload:gsub("^HMAC:", "")
    local raw = self:base64_decode(clean_b64)
    if not raw or #raw < 20 then
        return nil, "Invalid payload length"
    end

    -- Candidate keys to try:
    -- 1. hex_secret (for QR code scan with #secret)
    -- 2. SHA-256(session_id) (for manual 6-character code entry)
    -- 3. SHA-256("XRAY-DEFAULT") (fallback)
    local candidate_keys = {}
    if hex_secret and #hex_secret >= 32 then
        local padded_hex = hex_secret:sub(1, 64)
        if #padded_hex < 64 then padded_hex = padded_hex .. string.rep("0", 64 - #padded_hex) end
        table.insert(candidate_keys, self:hexToBytes(padded_hex))
    end
    if session_id and #session_id > 0 then
        table.insert(candidate_keys, self:sha256(session_id))
    end
    table.insert(candidate_keys, self:sha256("XRAY-DEFAULT"))

    -- 1. Try HMAC Stream Decryption (zero external dependencies)
    if is_hmac_stream or #raw >= 33 then
        for _, key_bytes in ipairs(candidate_keys) do
            local plain, err = self:decryptHMACStream(raw, key_bytes)
            if plain then
                return plain
            end
        end
    end

    -- 2. Try AES-256-GCM via OpenSSL (12 bytes IV + ciphertext + 16 bytes Tag)
    if #raw >= 29 then
        local iv = raw:sub(1, 12)
        local tag = raw:sub(-16)
        local ciphertext = raw:sub(13, -17)

        local lib = getLibCrypto()
        if lib and lib.EVP_CIPHER_CTX_new and lib.EVP_aes_256_gcm then
            for _, key_bytes in ipairs(candidate_keys) do
                local ctx = lib.EVP_CIPHER_CTX_new()
                if ctx ~= nil then
                    local out_buf = ffi.new("unsigned char[?]", #ciphertext + 32)
                    local outl = ffi.new("int[1]")
                    local final_l = ffi.new("int[1]")
                    local success = false
                    local result_text = nil

                    local ok_run = pcall(function()
                        local cipher = lib.EVP_aes_256_gcm()
                        if lib.EVP_DecryptInit_ex(ctx, cipher, nil, key_bytes, iv) ~= 1 then return end
                        if lib.EVP_DecryptUpdate(ctx, out_buf, outl, ciphertext, #ciphertext) ~= 1 then return end
                        
                        -- Set Expected Auth Tag (0x11 = EVP_CTRL_GCM_SET_TAG, 16 bytes)
                        local tag_buf = ffi.new("unsigned char[16]", tag)
                        if lib.EVP_CIPHER_CTX_ctrl(ctx, 0x11, 16, tag_buf) ~= 1 then return end
                        
                        if lib.EVP_DecryptFinal_ex(ctx, out_buf + outl[0], final_l) == 1 then
                            local total_len = outl[0] + final_l[0]
                            result_text = ffi.string(out_buf, total_len)
                            success = true
                        end
                    end)

                    lib.EVP_CIPHER_CTX_free(ctx)

                    if ok_run and success and result_text then
                        return result_text
                    end
                end
            end
        end
    end

    return nil, "Authentication/decryption failed (tag mismatch or invalid secret)"
end

return M
