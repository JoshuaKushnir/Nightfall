--!strict
-- Simple unit test ensuring NetworkProvider creates expected RemoteEvents
-- Uses the real module because it has no external dependencies.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)
local NetworkTypes = require(ReplicatedStorage.Shared.types.NetworkTypes)

describe("NetworkProvider", function()
    beforeEach(function()
        -- reset folder if exists
        local folder = ReplicatedStorage:FindFirstChild("NetworkEvents")
        if folder then folder:Destroy() end
        NetworkProvider._initialized = false
        NetworkProvider._remoteEvents = {}
        NetworkProvider._remoteFunctions = {}
        NetworkProvider._networkFolder = nil
    end)

    it("creates all events from NetworkTypes", function()
        NetworkProvider:Init()
        local all = NetworkTypes.GetAllEvents()
        for _, name in ipairs(all) do
            local evt = NetworkProvider:GetRemoteEvent(name)
            assert(evt and evt:IsA("RemoteEvent"), "Expected event " .. name)
        end
    end)

    it("includes AbilityCastRequest and AbilityCastResult", function()
        NetworkProvider:Init()
        assert(NetworkProvider:GetRemoteEvent("AbilityCastRequest"))
        assert(NetworkProvider:GetRemoteEvent("AbilityCastResult"))
    end)
end)
