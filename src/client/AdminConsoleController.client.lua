-- AdminConsoleController.client.lua
-- Teleport shortcut for dev: Press P to go to Heaven zone
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local Players           = game:GetService("Players")

-- Wait for LocalPlayer to be initialized
while not Players.LocalPlayer do
    Players.PlayerAdded:Wait()
end
local player        = Players.LocalPlayer
local IS_DEV        = (player.Name == "oofer_ytb" or player.UserId == game.CreatorId)

-- Wait for the server to create RemoteEvents before trying to use them
local networkFolder = ReplicatedStorage:WaitForChild("NetworkEvents", 15)
if not networkFolder then
    warn("[AdminConsoleController] NetworkEvents folder not found — admin shortcuts disabled")
    return
end

local adminRemote = networkFolder:WaitForChild("AdminCommand", 10)
if not adminRemote then
    warn("[AdminConsoleController] AdminCommand RemoteEvent not found — admin shortcuts disabled")
    return
end

UserInputService.InputBegan:Connect(function(input, processed)
    if processed or not IS_DEV then return end
    if input.KeyCode == Enum.KeyCode.P then
        adminRemote:FireServer({ Command = "tp_dev", Args = { "heaven" } })
    end
end)
