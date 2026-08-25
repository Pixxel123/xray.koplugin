package.path = "xray.koplugin/?.lua;spec/?.lua;" .. package.path
require("spec.spec_helper")

local Crypto = require("xray_crypto")

describe("xray_crypto", function()
    it("generates a 64-character hex secret", function()
        local secret = Crypto:generateSecretHex()
        assert.is_string(secret)
        assert.are.equal(64, #secret)
        assert.is_true(secret:match("^[0-9a-f]+$") ~= nil)
    end)

    it("converts hex to bytes and back", function()
        local hex = "0123456789abcdef"
        local bytes = Crypto:hexToBytes(hex)
        local recovered = Crypto:bytesToHex(bytes)
        assert.are.equal(hex, recovered)
    end)

    it("decodes base64 strings accurately", function()
        local encoded = "SGVsbG8gV29ybGQ="
        local decoded = Crypto:base64_decode(encoded)
        assert.are.equal("Hello World", decoded)
    end)

    it("computes pure Lua SHA-256 and HMAC-SHA256 hashes accurately", function()
        local hash = Crypto:sha256("test")
        assert.is_string(hash)
        assert.are.equal(32, #hash)
        assert.are.equal("9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08", Crypto:bytesToHex(hash))

        local hmac = Crypto:hmac_sha256("key", "The quick brown fox jumps over the lazy dog")
        assert.is_string(hmac)
        assert.are.equal(32, #hmac)
        assert.are.equal("f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8", Crypto:bytesToHex(hmac))
    end)

    it("encrypts and decrypts pure Lua HMAC stream payloads", function()
        local hex_secret = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        local key_bytes = Crypto:hexToBytes(hex_secret)
        local iv = "1234567890123456"
        local plaintext = '{"provider":"gemini","api_key":"AQ.TestKey123"}'
        
        -- Build keystream
        local keystream = ""
        local counter = 0
        while #keystream < #plaintext do
            local c_bytes = string.char(
                math.floor(counter / 16777216) % 256,
                math.floor(counter / 65536) % 256,
                math.floor(counter / 256) % 256,
                counter % 256
            )
            local block = Crypto:hmac_sha256(key_bytes, iv .. c_bytes)
            keystream = keystream .. block
            counter = counter + 1
        end

        local ciphertext = ""
        for i = 1, #plaintext do
            local b1 = plaintext:byte(i)
            local b2 = keystream:byte(i)
            local res = 0
            local p = 1
            for bit = 0, 7 do
                local bit1 = b1 % 2
                local bit2 = b2 % 2
                if bit1 ~= bit2 then res = res + p end
                b1 = math.floor(b1 / 2)
                b2 = math.floor(b2 / 2)
                p = p * 2
            end
            ciphertext = ciphertext .. string.char(res)
        end

        local tag = Crypto:hmac_sha256(key_bytes, "AUTH" .. iv .. ciphertext):sub(1, 16)
        local raw = iv .. tag .. ciphertext

        -- Manual base64 encode
        local b64_chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
        local b64 = ""
        for i = 1, #raw, 3 do
            local b1, b2, b3 = raw:byte(i, i+2)
            local n = (b1 * 65536) + ((b2 or 0) * 256) + (b3 or 0)
            local c1 = math.floor(n / 262144) % 64 + 1
            local c2 = math.floor(n / 4096) % 64 + 1
            local c3 = math.floor(n / 64) % 64 + 1
            local c4 = n % 64 + 1
            b64 = b64 .. b64_chars:sub(c1, c1) .. b64_chars:sub(c2, c2) .. (b2 and b64_chars:sub(c3, c3) or '=') .. (b3 and b64_chars:sub(c4, c4) or '=')
        end

        local decrypted, err = Crypto:decryptPayload("HMAC:" .. b64, hex_secret)
        assert.is_nil(err)
        assert.are.equal(plaintext, decrypted)
    end)

    it("fails decryption with wrong secret when no session_id", function()
        local wrong_secret = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
        local ciphertext_b64 = "HMAC:GBEztvpiw5zbGEOh0A1WpzrpE/0ZQbt+Qk6JJBgpIl15g1UDSAwtclUd+qWiwX7M3fddrHfiOsgnT3MeMZNomBwfABdY8Hdrvxqfe6ej/HR6tnM="

        local plaintext, err = Crypto:decryptPayload(ciphertext_b64, wrong_secret)
        assert.is_nil(plaintext)
        assert.is_string(err)
    end)
end)
