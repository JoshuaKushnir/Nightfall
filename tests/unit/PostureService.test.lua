--!strict
-- PostureService unit tests (discipline integration)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PostureService = require(ReplicatedStorage.Server.services.PostureService)
local DisciplineConfig = require(ReplicatedStorage.Shared.modules.DisciplineConfig)
local StateService = require(ReplicatedStorage.Shared.modules.StateService)

return {
	name = "PostureService Unit Tests",
	tests = {
		{
			name = "ResetPosture uses discipline pool",
			fn = function()
				-- fake player
				local p = {UserId = 123, Name = "Test"}
				-- patch StateService to return discipline data
				local orig = StateService.GetPlayerData
				StateService.GetPlayerData = function(_)
					return {DisciplineId = "Ironclad"}
				end

				PostureService.ResetPosture(p)
				local curr, max = PostureService.GetPosture(p)
				assert(max == DisciplineConfig.Get("Ironclad").postureMax)
				assert(curr == max)

				-- restore original
				StateService.GetPlayerData = orig
			end,
		},
		{
			name = "TriggerStagger respects discipline duration",
			fn = function()
				local p = {UserId = 456, Name = "StunTest"}
				local orig = StateService.GetPlayerData
				StateService.GetPlayerData = function(_)
					return {DisciplineId = "Silhouette"}
				end

				PostureService.ResetPosture(p)
				PostureService.TriggerStagger(p)
				-- immediately check that the stored end time matches config
				local _, state = PostureService.GetPosture(p)
				-- can't access end, so rely on printed output? instead inspect private table by hack
				-- we will access internal _postures via debug.getupvalue since it's local
				local info = debug.getupvalue(PostureService.TriggerStagger, 1)
				-- skip complex introspection; instead call IsStaggered and wait
				assert(PostureService.IsStaggered(p))
				-- wait for duration and ensure it clears
				task.wait(DisciplineConfig.Get("Silhouette").staggerDuration + 0.1)
				assert(not PostureService.IsStaggered(p))

				StateService.GetPlayerData = orig
			end,
		},
		{
			name = "DrainPosture returns overflow amount",
			fn = function()
				local p = {UserId = 789, Name = "OverflowTest"}
				-- set a small posture pool so overflow is easy to trigger
				local orig = StateService.GetPlayerData
				StateService.GetPlayerData = function(_)
					return {DisciplineId = "Wayward"}
				end

				PostureService.ResetPosture(p)
				-- manually reduce posture to a low value via two drains
				local broke, overflow = PostureService.DrainPosture(p, 95, "Unguarded")
				-- initial drain should not break (pool 100)
				assert(not broke and overflow == 0)
				-- second drain should overflow by 90 (95-10 remaining)
				local broke2, overflow2 = PostureService.DrainPosture(p, 95, "Unguarded")
				assert(broke2 and overflow2 > 0, "overflow not reported")
				
				StateService.GetPlayerData = orig
			end,
		},
	},
}

