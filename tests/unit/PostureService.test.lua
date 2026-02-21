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
				assert(max == DisciplineConfig.Get("Ironclad").PosturePool)
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
				task.wait(DisciplineConfig.Get("Silhouette").StaggerDuration + 0.1)
				assert(not PostureService.IsStaggered(p))

				StateService.GetPlayerData = orig
			end,
		},
	},
}
