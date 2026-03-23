--!strict
--[[
	Class: EmberPointController
	Description: Client-side controller for placing and interacting with Ember Points.
	Handles input 'K' to place an Ember Point and listens for the DeployResult.
	Dependencies: NetworkController
	
	Usage:
		local EmberPointController = require(path.to.EmberPointController)
		EmberPointController:Init(dependencies)
		EmberPointController:Start()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NetworkTypes = require(Shared.types.NetworkTypes)

local EmberPointController = {}
EmberPointController._initialized = false

local NetworkController = nil
local PlayerHUDController = nil

local DBNC_TIME = 1.0
local lastDeployTime = 0

function EmberPointController:Init(dependencies: any)
	NetworkController = dependencies.NetworkController
	PlayerHUDController = dependencies.PlayerHUDController
	self._initialized = true
end

function EmberPointController:Start()
	assert(self._initialized, "Must call Init() before Start()")
	
	-- Input for placing Ember Point
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		
		-- Use 'K' for Kindle / place Ember Point
		if input.KeyCode == Enum.KeyCode.K then
			local now = os.clock()
			if now - lastDeployTime < DBNC_TIME then return end
			lastDeployTime = now
			
			local position = Players.LocalPlayer.Character and Players.LocalPlayer.Character.PrimaryPart and Players.LocalPlayer.Character.PrimaryPart.Position
			if position then
				-- Send request to server
				NetworkController:Send("EmberPointPlaceRequest", {
					Position = position
				})
			end
		end
	end)
	
	-- Listen for deploy result
	NetworkController:RegisterHandler("EmberPointDeployResult", function(packet: NetworkTypes.EmberPointDeployResultPacket)
		local color = packet.Success and Color3.fromRGB(255, 150, 50) or Color3.fromRGB(200, 50, 50)
		if PlayerHUDController then
			PlayerHUDController:ShowToast(
				packet.Success and "Ember Point" or "Failed",
				packet.Message,
				color,
				4.0
			)
		end
		
		if packet.Success and packet.PointId then
			-- Optional: Play a sound or show short VFX here
		end
	end)
end

return EmberPointController
