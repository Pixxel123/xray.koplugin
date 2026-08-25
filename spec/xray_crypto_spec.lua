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

    it("decrypts valid AES-256-GCM payloads with valid secret", function()
        local hex_secret = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        local ciphertext_b64 = "GBEztvpiw5zbGEOh0A1WpzrpE/0ZQbt+Qk6JJBgpIl15g1UDSAwtclUd+qWiwX7M3fddrHfiOsgnT3MeMZNomBwfABdY8Hdrvxqfe6ej/HR6tnM="

        local plaintext, err = Crypto:decryptPayload(ciphertext_b64, hex_secret)
        assert.is_nil(err)
        assert.is_string(plaintext)
        assert.is_true(plaintext:find("AQ.Ab8RN6J4TestKey123") ~= nil)
    end)

    it("fails decryption with wrong secret when no session_id", function()
        local wrong_secret = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
        local ciphertext_b64 = "GBEztvpiw5zbGEOh0A1WpzrpE/0ZQbt+Qk6JJBgpIl15g1UDSAwtclUd+qWiwX7M3fddrHfiOsgnT3MeMZNomBwfABdY8Hdrvxqfe6ej/HR6tnM="

        local plaintext, err = Crypto:decryptPayload(ciphertext_b64, wrong_secret)
        assert.is_nil(plaintext)
        assert.is_string(err)
    end)

    it("decrypts payload encrypted with session_id even when random hex_secret is passed", function()
        local session_id = "K9X2B4"
        local random_hex_secret = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        
        -- Generate ciphertext using SHA256(session_id)
        local key_bytes = Crypto:sha256(session_id)
        local iv = "123456789012"
        local plaintext = '{"provider":"gemini","api_key":"AQ.TestManualCode123"}'
        
        local ffi = require("ffi")
        local lib = ffi.load("/usr/lib/koreader/libs/libcrypto.so.57")
        local ctx = lib.EVP_CIPHER_CTX_new()
        lib.EVP_EncryptInit_ex(ctx, lib.EVP_aes_256_gcm(), nil, key_bytes, iv)
        local out_buf = ffi.new("unsigned char[128]")
        local outl = ffi.new("int[1]")
        local finall = ffi.new("int[1]")
        lib.EVP_EncryptUpdate(ctx, out_buf, outl, plaintext, #plaintext)
        lib.EVP_EncryptFinal_ex(ctx, out_buf + outl[0], finall)
        local tag = ffi.new("unsigned char[16]")
        lib.EVP_CIPHER_CTX_ctrl(ctx, 0x10, 16, tag)
        lib.EVP_CIPHER_CTX_free(ctx)
        
        local raw = iv .. ffi.string(out_buf, outl[0] + finall[0]) .. ffi.string(tag, 16)
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

        local decrypted, err = Crypto:decryptPayload(b64, random_hex_secret, session_id)
        assert.is_nil(err)
        assert.is_string(decrypted)
        assert.is_true(decrypted:find("AQ.TestManualCode123") ~= nil)
    end)
end)
