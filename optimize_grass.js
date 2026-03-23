const fs = require('fs');

// Update HeavenEnvironmentController config
let heavenCode = fs.readFileSync('src/client/controllers/HeavenEnvironmentController.lua', 'utf8');

// Decrease density slightly but increase size to compensate, extend draw distance to fix cutoff
heavenCode = heavenCode.replace('BladeHeight = 1.2,', 'BladeHeight = 1.6,');
heavenCode = heavenCode.replace('BladeWidth = 0.15,', 'BladeWidth = 0.35,');
heavenCode = heavenCode.replace('BladeDepth = 0.10,', 'BladeDepth = 0.20,');

heavenCode = heavenCode.replace('CellSize = 12.0,', 'CellSize = 16.0,');
heavenCode = heavenCode.replace('DrawDistance = 160,', 'DrawDistance = 220,');
heavenCode = heavenCode.replace('AnimationDist = 80,', 'AnimationDist = 100,');
heavenCode = heavenCode.replace('FadeStart = 120,', 'FadeStart = 160,');
heavenCode = heavenCode.replace('BladesPerCell = 200,', 'BladesPerCell = 80,'); // Was ~1.38/sq stud. Now is ~0.3/sq stud with wider blades. Less lag.

fs.writeFileSync('src/client/controllers/HeavenEnvironmentController.lua', heavenCode);

// Update GrassGrid loop
let gridCode = fs.readFileSync('src/client/modules/environment/GrassGrid.lua', 'utf8');

// 1. Update Grid range with buffer to prevent pop-in/pop-out
gridCode = gridCode.replace(
    'local range = math.ceil(config.DrawDistance / config.CellSize)',
    'local range = math.ceil(config.DrawDistance / config.CellSize) + 1\n\tlocal bufferDistSq = (config.DrawDistance + config.CellSize) ^ 2'
);
gridCode = gridCode.replace(
    'if (dx*dx + dz*dz) * (config.CellSize*config.CellSize) <= config.DrawDistance*config.DrawDistance then',
    'if (dx*dx + dz*dz) * (config.CellSize*config.CellSize) <= bufferDistSq then'
);

// 2. Frustum Culling and Math Optimization in _updateBlades
const updateBladesRegex = /function GrassGrid:_updateBlades\(dt: number, playerPos: Vector3\)([\s\S]*?)Workspace:BulkMoveTo/g;
let match = updateBladesRegex.exec(gridCode);

let newUpdateBlades = `function GrassGrid:_updateBlades(dt: number, playerPos: Vector3)
	local config = self.Config
	local t = self._clock

	local windDir = Vector3.new(math.cos(self._windAngle), 0, math.sin(self._windAngle))
	local windAxis = Vector3.new(-windDir.Z, 0, windDir.X)

	local interactRadiusSq = config.InteractionRadius * config.InteractionRadius
	local animDistSq = config.AnimationDist * config.AnimationDist
	local fadeRange = math.max(0.1, config.DrawDistance - config.FadeStart)

	local bulkParts = {}
	local bulkCFrames = {}
	local count = 0
	
	local cam = Workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or playerPos
	local camLook = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)

	for _, cell in pairs(self._activeCells) do
		local cellX = cell.X * config.CellSize
		local cellZ = cell.Z * config.CellSize
		
		local cellDx = cellX - playerPos.X
		local cellDz = cellZ - playerPos.Z
		
		-- Cull cells way beyond draw distance (buffer included)
		if (cellDx*cellDx + cellDz*cellDz) > (config.DrawDistance + config.CellSize)^2 + 400 then
			continue
		end
		
		-- Frustum Culling: Skip cells behind the camera to drastically reduce math overhead
		local toCamX = cellX - camPos.X
		local toCamZ = cellZ - camPos.Z
		local distToCamSq = toCamX*toCamX + toCamZ*toCamZ
		
		if distToCamSq > (config.CellSize * config.CellSize * 2) then
			local distToCam = math.sqrt(distToCamSq)
			local dirX = toCamX / distToCam
			local dirZ = toCamZ / distToCam
			local dot = camLook.X * dirX + camLook.Z * dirZ
			if dot < -0.25 then -- ~105 degree threshold, wide enough to hide edges
				continue
			end
		end

		for _, blade in ipairs(cell.Blades) do
			local baseCF = blade.BaseCFrame
			local pos = baseCF.Position

			local dx = pos.X - playerPos.X
			local dz = pos.Z - playerPos.Z
			local distSq = dx*dx + dz*dz

			local fade = 0
			local dist = 0
			
			-- Out of animation range: only sink, no wind or interaction
			if distSq > animDistSq then
				dist = math.sqrt(distSq)
				if dist > config.FadeStart then
					fade = clamp((dist - config.FadeStart) / fadeRange, 0, 1)
				end
			
				local halfHeight = (config.BladeHeight * blade.HeightScale * 0.5)
				local sinkOffset = fade * (config.BladeHeight * blade.HeightScale)
				local finalCF = baseCF * CFrame.new(0, halfHeight - sinkOffset, 0)

				count = count + 1
				bulkParts[count] = blade.Part
				bulkCFrames[count] = finalCF
				continue
			end

			dist = math.sqrt(distSq)
			if dist > config.FadeStart then
				fade = clamp((dist - config.FadeStart) / fadeRange, 0, 1)
			end

			local swayX = pos.X + blade.Phase
			local swayZ = pos.Z + blade.Phase

			-- Optimized wind math using Trig instead of math.noise
			local n = math.sin(swayX * config.WindNoiseScale + t * config.WindNoiseTime) * 
			          math.cos(swayZ * config.WindNoiseScale + t * config.WindNoiseTime * 0.8)
			local gust = math.sin(swayX * 0.02 + t * config.WindGustFreq)
			
			local totalWind = (n * 0.8 + gust * 0.4) * self._windStrength
			local windTilt = math.rad(totalWind)

			local interactRot = CFrame.new()

			if distSq < interactRadiusSq then
				local safeDist = dist
				if safeDist < 0.1 then safeDist = 0.1 end

				local pushFactor = (1 - (safeDist / config.InteractionRadius)) * config.InteractionStrength
				pushFactor = math.pow(pushFactor, 2.0)

				local dirX = dx / safeDist
				local dirZ = dz / safeDist

				local pushAxis = Vector3.new(-dirZ, 0, dirX)
				if pushAxis.Magnitude > 0.001 then
					interactRot = CFrame.fromAxisAngle(pushAxis.Unit, -pushFactor)
				end
			end

			local halfHeight = (config.BladeHeight * blade.HeightScale * 0.5)
			local sinkOffset = fade * (config.BladeHeight * blade.HeightScale)

			local combinedRot = interactRot * CFrame.fromAxisAngle(windAxis, windTilt)
			local finalCF = baseCF * combinedRot * CFrame.new(0, halfHeight - sinkOffset, 0)

			count = count + 1
			bulkParts[count] = blade.Part
			bulkCFrames[count] = finalCF
		end
	end

	if count > 0 then
		Workspace:BulkMoveTo`;

gridCode = gridCode.replace(match[0], newUpdateBlades);
fs.writeFileSync('src/client/modules/environment/GrassGrid.lua', gridCode);
