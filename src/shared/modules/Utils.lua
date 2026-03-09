--!strict
--[[
	Utils.lua
	
	Shared utility module for common operations across combat, hitbox, and action systems.
	Consolidates DRY logic to prevent duplication across services.
	
	Dependencies: None (leaf module)
	
	Public API:
	- Geometry calculations (magnitude, distance, box/sphere checks)
	- Table operations (safe removal, finding by property)
	- Validation helpers (nil checks, type guards)
	- Timing utilities (frame-based calculations)
	- ID generation (GenerateId)
]]

local HttpService = game:GetService("HttpService")

local Utils = {}

--[[
	===== ID GENERATION =====
]]

--[[
	Generate a unique ID string using a GUID
	@return Unique ID string
]]
function Utils.GenerateId(): string
	return HttpService:GenerateGUID(false)
end

--[[
	===== GEOMETRY & SPATIAL CALCULATIONS =====
]]

--[[
	Calculate distance between two points
	@param posA First position
	@param posB Second position
	@return Distance in studs
]]
function Utils.Distance(posA: Vector3, posB: Vector3): number
	return (posA - posB).Magnitude
end

--[[
	Check if a point is inside a box
	@param point The point to check
	@param boxCenter Center of the box
	@param boxSize Size of the box (width, height, depth)
	@return True if point is inside
]]
function Utils.PointInBox(point: Vector3, boxCenter: Vector3, boxSize: Vector3): boolean
	local halfSize = boxSize / 2
	local offset = (point - boxCenter).Abs()
	return offset.X <= halfSize.X and offset.Y <= halfSize.Y and offset.Z <= halfSize.Z
end

--[[
	Check if a point is inside a sphere
	@param point The point to check
	@param sphereCenter Center of the sphere
	@param radius Sphere radius
	@return True if point is inside
]]
function Utils.PointInSphere(point: Vector3, sphereCenter: Vector3, radius: number): boolean
	return Utils.Distance(point, sphereCenter) <= radius
end

--[[
	Get closest point on a ray segment to a target point
	@param rayOrigin Start of ray
	@param rayDirection Ray direction (should be normalized)
	@param rayLength Ray length
	@param point Target point
	@return Closest point on ray, distance to ray
]]
function Utils.ClosestPointOnRay(rayOrigin: Vector3, rayDirection: Vector3, rayLength: number, point: Vector3): (Vector3, number)
	local toPoint = point - rayOrigin
	local normalizedDir = rayDirection.Unit
	
	-- Project point onto ray
	local projLength = math.max(0, math.min(rayLength, toPoint:Dot(normalizedDir)))
	local closest = rayOrigin + (normalizedDir * projLength)
	local distance = Utils.Distance(point, closest)
	
	return closest, distance
end

--[[
	===== TABLE OPERATIONS =====
]]

--[[
	Safely find and remove item from table
	@param tbl The table
	@param item The item to remove
	@return True if item was found and removed
]]
function Utils.RemoveFromTable(tbl: {any}, item: any): boolean
	local index = table.find(tbl, item)
	if index then
		table.remove(tbl, index)
		return true
	end
	return false
end

--[[
	Find item in table by property
	@param tbl The table to search
	@param property The property name
	@param value The value to match
	@return The matching item or nil
]]
function Utils.FindByProperty(tbl: {any}, property: string, value: any): any?
	for _, item in tbl do
		if type(item) == "table" and item[property] == value then
			return item
		end
	end
	return nil
end

--[[
	Remove all instances of a value from table
	@param tbl The table
	@param item The item to remove
	@return Number of items removed
]]
function Utils.RemoveAll(tbl: {any}, item: any): number
	local count = 0
	while table.find(tbl, item) do
		table.remove(tbl, table.find(tbl, item) :: number)
		count += 1
	end
	return count
end

--[[
	===== VALIDATION HELPERS =====
]]

--[[
	Check if player is valid (exists, has character, has humanoid)
	@param player The player to check
	@return True if player is valid
]]
function Utils.IsValidPlayer(player: Player?): boolean
	if not player or not player.Parent then
		return false
	end
	
	local character = player.Character
	if not character then
		return false
	end
	
	local humanoid = character:FindFirstChild("Humanoid")
	return humanoid ~= nil
end

--[[
	Check if character part exists and is valid
	@param character The character to check
	@param partName The part name to check
	@return True if part exists
]]
function Utils.HasPart(character: Model?, partName: string): boolean
	if not character then
		return false
	end
	
	local part = character:FindFirstChild(partName)
	return part ~= nil
end

--[[
	Get character or nil safely
	@param player The player
	@return Character or nil
]]
function Utils.GetCharacter(player: Player?): Model?
	if not player then
		return nil
	end
	return player.Character
end

--[[
	Get humanoid root part safely
	@param player The player
	@return HumanoidRootPart or nil
]]
function Utils.GetRootPart(player: Player?): BasePart?
	local character = Utils.GetCharacter(player)
	if not character then
		return nil
	end
	
	return character:FindFirstChild("HumanoidRootPart")
end

--[[
    Get all BaseParts that serve as zone triggers.  These are identified by
    the folder/part name prefix "ZoneTrigger".  Movement modules should ignore
    them when raycasting for walls/ledges so the transparent trigger volumes
    don't register as climbable surfaces.
]]
function Utils.GetZoneTriggerParts(): {BasePart}
    -- prefer tagged parts if CollectionService is available (ZoneService adds tags)
    local CollectionService = game:GetService("CollectionService")
    if CollectionService then
        local tagged = CollectionService:GetTagged("ZoneTrigger")
        local parts: {BasePart} = {}
        for _, obj in ipairs(tagged) do
            if obj:IsA("BasePart") then
                table.insert(parts, obj)
            end
        end
        if #parts > 0 then
            return parts
        end
        -- fall through to full scan if no tagged results (legacy)
    end

    local parts: {BasePart} = {}
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name:match("^ZoneTrigger") then
            table.insert(parts, obj)
        end
    end
    return parts
end
-- ===== TIMING UTILITIES =====

--[[ NOTE: previous stray comment closer removed; timing utilities section begins below. ]]

--[[
	Check if a cooldown has expired
	@param lastTime The time of last action
	@param cooldown Cooldown duration in seconds
	@return True if cooldown has expired
]]
function Utils.IsCooldownExpired(lastTime: number?, cooldown: number): boolean
	if not lastTime then
		return true
	end
	
	return tick() - lastTime >= cooldown
end

--[[
	Clamp a frame time between bounds
	@param frame Current frame (0-1)
	@param min Minimum frame
	@param max Maximum frame
	@return True if frame is within bounds
]]
function Utils.IsFrameInRange(frame: number, min: number, max: number): boolean
	return frame >= min and frame <= max
end

--[[
	===== STRING & FORMATTING =====
]]

--[[
	Format a number with commas
	@param num The number to format
	@return Formatted string
]]
function Utils.FormatNumber(num: number): string
	local str = tostring(math.floor(num))
	return str:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

--[[
	Create a debug tag for logging
	@param serviceName Name of the service
	@return Formatted tag like "[ServiceName]"
]]
function Utils.MakeTag(serviceName: string): string
	return `[{serviceName}]`
end

--[[
	===== MATH UTILITIES =====
]]

--[[
	Clamp a value between min and max
	@param value The value to clamp
	@param min Minimum value
	@param max Maximum value
	@return Clamped value
]]
function Utils.Clamp(value: number, min: number, max: number): number
	return math.max(min, math.min(max, value))
end

--[[
	Linear interpolation
	@param a Start value
	@param b End value
	@param t Time (0-1)
	@return Interpolated value
]]
function Utils.Lerp(a: number, b: number, t: number): number
	return a + (b - a) * Utils.Clamp(t, 0, 1)
end

--[[
	Ease in-out quad
	@param t Time (0-1)
	@return Eased value
]]
function Utils.EaseInOutQuad(t: number): number
	t = Utils.Clamp(t, 0, 1)
	if t < 0.5 then
		return 2 * t * t
	end
	return 1 - (-2 * t + 2) ^ 2 / 2
end

--[[
	Spring damper for smooth, physics-based interpolation
	Implements a semi-implicit Euler integrator for stable spring motion
	
	@param current Current position (number or Vector3)
	@param target Target position (number or Vector3)
	@param velocity Current velocity (number or Vector3)
	@param frequency Natural frequency (Hz) - higher = stiffer spring
	@param dampingRatio Damping ratio (0-1+) - 1 = critically damped, <1 = underdamped (bouncy), >1 = overdamped (slow)
	@param dt Delta time (seconds)
	@return newPosition, newVelocity
]]
function Utils.SpringDamper(current: any, target: any, velocity: any, frequency: number, dampingRatio: number, dt: number): (any, any)
	-- Spring constants derived from frequency and damping ratio
	local angularFrequency = 2 * math.pi * frequency
	local springConstant = angularFrequency * angularFrequency
	local dampingCoefficient = 2 * dampingRatio * angularFrequency
	
	-- Semi-implicit Euler integration for stability
	local displacement = current - target
	local springForce = -springConstant * displacement
	local dampingForce = -dampingCoefficient * velocity
	local acceleration = springForce + dampingForce
	
	local newVelocity = velocity + acceleration * dt
	local newPosition = current + newVelocity * dt
	
	return newPosition, newVelocity
end

--[[
	Spring damper specifically for Vector3 with per-axis application
	More efficient for 3D motion than calling SpringDamper on each component
	
	@param current Current Vector3 position
	@param target Target Vector3 position
	@param velocity Current Vector3 velocity
	@param frequency Natural frequency (Hz)
	@param dampingRatio Damping ratio (0-1+)
	@param dt Delta time (seconds)
	@return newPosition Vector3, newVelocity Vector3
]]
function Utils.SpringDamperVector3(current: Vector3, target: Vector3, velocity: Vector3, frequency: number, dampingRatio: number, dt: number): (Vector3, Vector3)
	local angularFrequency = 2 * math.pi * frequency
	local springConstant = angularFrequency * angularFrequency
	local dampingCoefficient = 2 * dampingRatio * angularFrequency
	
	local displacement = current - target
	local springForce = -springConstant * displacement
	local dampingForce = -dampingCoefficient * velocity
	local acceleration = springForce + dampingForce
	
	local newVelocity = velocity + acceleration * dt
	local newPosition = current + newVelocity * dt
	
	return newPosition, newVelocity
end

return Utils
