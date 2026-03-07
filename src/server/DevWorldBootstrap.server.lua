--!strict
--[[
	DevWorldBootstrap.server.lua

	Issue #107: Playable Ring-1 zone (Verdant Shelf prototype)

	Studio-only server script that procedurally creates the minimum world
	content required to make Ring 1 playable end-to-end:

		• ZoneTrigger_Ring1  — zone volume BasePart (ZoneService detects this)
		• HollowedSpawn (×3) — tagged Parts at preset Ring-1 positions
		  (HollowedService.Start() reads CollectionService tag "HollowedSpawn")

	This script is NEVER active in published servers — it is guarded by
	RunService:IsStudio().  When the Studio team builds real Ring-1 geometry
	these workspace objects can be replaced with authored parts; this script
	can then be deleted.

	What "playable end-to-end" means for Ring-1 MVP:
		1. Player can walk to Ring 1 area and ZoneService reports Ring = 1
		2. Three Hollowed NPCs patrol, aggro, and attack players
		3. Killing an NPC grants 25 Resonance via ProgressionService
		4. Player returns to Ring 0 and ZoneService reports Ring = 0

	No Luminance drain in Ring 1 (drain begins in Ring 2, per spec).
	No PvP flags in Ring 1 (player-opt-in system, deferred to Phase 4 content).
]]

local RunService        = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace         = game:GetService("Workspace")

-- Studio guard — this code never runs on published servers
if not RunService:IsStudio() then
	return
end

print("[DevWorldBootstrap] Studio mode detected — seeding Ring-1 prototype world content")

-- ─── Config ──────────────────────────────────────────────────────────────────

-- Centre of Ring-0 (Hearthspire) is world origin (0, 0, 0).
-- Ring-1 starts roughly 200 studs out from origin.
-- The trigger volume is a large flat slab placed at Y=1 so it overlaps players.

local RING1_CENTER       = Vector3.new(0, 1, 250)   -- offset forward from origin
local RING1_RADIUS_INNER = 150                       -- inner boundary (Ring-0 edge)
local RING1_RADIUS_OUTER = 350                       -- outer boundary

-- Ring-0 trigger (safe zone — implicit, no part required; ZoneService defaults to 0)
-- Ring-1 volume: an annular region.  We approximate it with a large rectangular slab.
local RING1_TRIGGER_SIZE = Vector3.new(
	(RING1_RADIUS_OUTER - RING1_RADIUS_INNER) * 2,
	10,
	(RING1_RADIUS_OUTER - RING1_RADIUS_INNER) * 2
)

-- Hollowed spawn positions (within Ring-1 bounds)
local HOLLOWED_SPAWN_POSITIONS: {Vector3} = {
	Vector3.new(-80, 1, 220),
	Vector3.new(  0, 1, 270),
	Vector3.new( 90, 1, 240),
}

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function makePart(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: BrickColor,
	anchored: boolean,
	canCollide: boolean,
	transparency: number,
	parent: Instance
): BasePart
	local p = Instance.new("Part")
	p.Name         = name
	p.Size         = size
	p.CFrame       = cframe
	p.BrickColor   = color
	p.Anchored     = anchored
	p.CanCollide   = canCollide
	p.Transparency = transparency
	p.Locked       = true   -- prevent accidental selection
	p.Material     = Enum.Material.Grass
	p.Parent       = parent
	return p
end

-- ─── Zone Trigger ─────────────────────────────────────────────────────────────

-- Only create if not already authored by Studio team
if not Workspace:FindFirstChild("ZoneTrigger_Ring1") then
	local triggerCenter = CFrame.new(RING1_CENTER)
	local trigger = makePart(
		"ZoneTrigger_Ring1",
		RING1_TRIGGER_SIZE,
		triggerCenter,
		BrickColor.new("Forest green"),
		true,    -- anchored
		false,   -- not solid (players walk through)
		0.85,    -- nearly invisible in production; visible in Studio for debugging
		Workspace
	)
	trigger.Material = Enum.Material.Neon

	-- Tag for any future systems that may need it
	CollectionService:AddTag(trigger, "Ring1Zone")

	print(("[DevWorldBootstrap] Created ZoneTrigger_Ring1 at %s size %s"):format(
		tostring(RING1_CENTER), tostring(RING1_TRIGGER_SIZE)
	))
else
	print("[DevWorldBootstrap] ZoneTrigger_Ring1 already exists — skipping placement")
end

-- ─── Ground Plane — Ring 1 ───────────────────────────────────────────────────

-- Create a simple flat ground slab so players have somewhere to stand
if not Workspace:FindFirstChild("Ring1Ground") then
	makePart(
		"Ring1Ground",
		Vector3.new(700, 1, 700),
		CFrame.new(RING1_CENTER.X, 0, RING1_CENTER.Z),
		BrickColor.new("Medium green"),
		true,
		true,
		0,
		Workspace
	)
	print("[DevWorldBootstrap] Created Ring1Ground slab")
end

-- ─── Hollowed Spawn Points ────────────────────────────────────────────────────

-- Create a small invisible platform at each spawn point and tag it "HollowedSpawn"
for i, pos in HOLLOWED_SPAWN_POSITIONS do
	local spawnName = ("HollowedSpawn_Ring1_%d"):format(i)
	if not Workspace:FindFirstChild(spawnName) then
		local part = makePart(
			spawnName,
			Vector3.new(2, 0.2, 2),
			CFrame.new(pos),
			BrickColor.new("Dark red"),
			true,
			false,
			0.9,  -- almost invisible
			Workspace
		)
		CollectionService:AddTag(part, "HollowedSpawn")
		print(("[DevWorldBootstrap] Tagged HollowedSpawn at %s"):format(tostring(pos)))
	else
		print(("[DevWorldBootstrap] %s already exists — skipping"):format(spawnName))
	end
end

-- ─── Spawn Platform — Ring 0 entry ───────────────────────────────────────────

-- A slightly elevated spawn pad so players can easily enter Ring 1 in Studio
if not Workspace:FindFirstChild("Ring1Entrance") then
	makePart(
		"Ring1Entrance",
		Vector3.new(30, 1, 30),
		CFrame.new(0, 1, 180),  -- edge of Ring-0, facing into Ring-1
		BrickColor.new("Bright yellow"),
		true,
		true,
		0,
		Workspace
	)
	print("[DevWorldBootstrap] Created Ring1Entrance pad at (0, 1, 180)")
end

print("[DevWorldBootstrap] Ring-1 prototype world seeding complete")
print("[DevWorldBootstrap] Zone detection: walk past Z=180 → ZoneService should report Ring 1")
print("[DevWorldBootstrap] Hollowed NPCs: 3 spawned via HollowedService on server Start()")
