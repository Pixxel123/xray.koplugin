package.path = "xray.koplugin/?.lua;spec/?.lua;" .. package.path
require("spec.spec_helper")

local WebSetup = require("xray_websetup")

describe("xray_websetup", function()
    local mock_ai_helper
    local mock_loc
    local saved_prov, saved_key

    before_each(function()
        saved_prov = nil
        saved_key = nil
        mock_ai_helper = {
            settings = {},
            setAPIKey = function(self, prov, key)
                saved_prov = prov
                saved_key = key
            end,
            setCustomAPIConfig = function(self, prov, key, endpoint, model)
                saved_prov = prov
                saved_key = key
            end,
            updateConfigKey = function(self, k, v) end,
        }
        mock_loc = {
            t = function(self, k, arg) return k .. ":" .. tostring(arg or "") end
        }
    end)

    it("returns formatted provider display names", function()
        assert.are.equal("Google Gemini", WebSetup:getProviderDisplayName("gemini"))
        assert.are.equal("OpenAI ChatGPT", WebSetup:getProviderDisplayName("chatgpt"))
        assert.are.equal("DeepSeek", WebSetup:getProviderDisplayName("deepseek"))
        assert.are.equal("Anthropic Claude", WebSetup:getProviderDisplayName("claude"))
        assert.are.equal("Custom API", WebSetup:getProviderDisplayName("custom1"))
    end)

    it("applies received key to AIHelper", function()
        WebSetup.ai_helper = mock_ai_helper
        WebSetup.loc = mock_loc

        local payload = {
            provider = "gemini",
            api_key = "AQ.TestGeminiKey123"
        }

        local ok, err = WebSetup:applyReceivedKey(payload)
        assert.is_true(ok)
        assert.are.equal("gemini", saved_prov)
        assert.are.equal("AQ.TestGeminiKey123", saved_key)
    end)

    it("handles custom API configuration payloads", function()
        WebSetup.ai_helper = mock_ai_helper
        WebSetup.loc = mock_loc

        local payload = {
            provider = "custom1",
            api_key = "sk-or-testkey",
            endpoint = "https://openrouter.ai/api/v1/chat/completions",
            model = "google/gemini-flash"
        }

        local ok, err = WebSetup:applyReceivedKey(payload)
        assert.is_true(ok)
        assert.are.equal("custom1", saved_prov)
        assert.are.equal("sk-or-testkey", saved_key)
    end)

    it("stops cleanly and clears session state", function()
        WebSetup.is_running = true
        WebSetup.session_id = "ABC123"
        WebSetup.session_secret = "secret"
        WebSetup:stop()

        assert.is_false(WebSetup.is_running)
        assert.is_nil(WebSetup.session_id)
        assert.is_nil(WebSetup.session_secret)
    end)

    it("correctly identifies whether local server is supported by device", function()
        local Device = require("device")
        local orig_isKindle = Device.isKindle

        -- When device is Kindle (firewall blocks inbound connections)
        Device.isKindle = function() return true end
        assert.is_false(WebSetup:isLocalServerSupported())

        -- When device is Android / Kobo / etc.
        Device.isKindle = function() return false end
        assert.is_true(WebSetup:isLocalServerSupported())

        Device.isKindle = orig_isKindle
    end)
end)
