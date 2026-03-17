--!strict
--[[
	DevWorldBootstrap.server.lua

	Issue #107 & #178: All Rings (1-4) Zone & Enemy Spawning

	Studio-only server script that procedurally creates world content for all
	rings to allow end-to-end gameplay testing:

	Ring 1 — Verdant Shelf:
		• 3 zones: Canopy Road, Drowned Meadow, Ashward Fringe
		• 3 enemy types per zone (Hollowed Drifter, Hollowed Sentinel, Greyback, etc.)
		• Enemies tagged for HollowedService, CreatureService, etc.

	Ring 2 — Ashfeld:
		• 3 zones with Choir and environmental enemies
		• Enemies: Choir Initiate, Choir Penitent, Ash Hound, etc.

	Ring 3 — Vael Depths:
		• 3 zones with Preserved and Threadweaver enemies
		• Vertical architecture hints for Ring 3

	Ring 4 — Gloam:
		• 3 zones with Vaelborn and elite enemies
		• Luminance drain implications visible

	This script is NEVER active in published servers — guarded by RunService:IsStudio().
	When Studio team builds real geometry, this script can be deleted and parts replaced.

	See docs/Game Plan/World_Design.md for complete zone and enemy specifications.
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
-- Each ring radiates outward. Zones are positioned progressively further.

local RINGS = {
	-- Ring 1 — Verdant Shelf (forest, 200-350 studs from origin)
	Ring1 = {
		Center = Vector3.new(0, 1, 275),
		RadiusInner = 200,
		RadiusOuter = 350,
		Zones = {
			CanopyRoad = {
				Position = Vector3.new(-100, 1, 250),
				Size = Vector3.new(150, 10, 200),
				Enemies = {
					{ Type = "HollowedDrifter", Pos = Vector3.new(-120, 1, 240) },
					{ Type = "HollowedSentinel", Pos = Vector3.new(-80, 1, 260) },
					{ Type = "Greyback", Pos = Vector3.new(-100, 1, 225) },
				},
			},
			DrownedMeadow = {
				Position = Vector3.new(0, 1, 300),
				Size = Vector3.new(150, 10, 200),
				Enemies = {
					{ Type = "HollowedFisher", Pos = Vector3.new(-30, 1, 290) },
					{ Type = "MurkLurker", Pos = Vector3.new(30, 1, 310) },
					{ Type = "SaturatedHollowed", Pos = Vector3.new(0, 1, 330) },
				},
			},
			AshwardFringe = {
				Position = Vector3.new(120, 1, 280),
				Size = Vector3.new(150, 10, 200),
				Enemies = {
					{ Type = "HollowedScout", Pos = Vector3.new(90, 1, 265) },
					{ Type = "FringeCreeper", Pos = Vector3.new(140, 1, 285) },
					{ Type = "Dimling", Pos = Vector3.new(120, 1, 305) },
				},
			},
		},
	},
	-- Ring 2 — Ashfeld (dead civilization, 350-550 studs)
	Ring2 = {
		Center = Vector3.new(0, 1, 450),
		RadiusInner = 350,
		RadiusOuter = 550,
		Zones = {
			Ashroads = {
				Position = Vector3.new(-150, 1, 420),
				Size = Vector3.new(150, 10, 200),
				Enemies = {
					{ Type = "ChoirInitiate", Pos = Vector3.new(-180, 1, 410) },
					{ Type = "ChoirPenitent", Pos = Vector3.new(-120, 1, 430) },
					{ Type = "AshHound", Pos = Vector3.new(-150, 1, 390) },
				},
			},
			DriedBasin = {
				Position = Vector3.new(0, 1, 480),
				Size = Vector3.new(150, 10, 200),
				Enemies = {
					{ Type = "HollowedChanneler", Pos = Vector3.new(-30, 1, 470) },
					{ Type = "BasinStalker", Pos = Vector3.new(30, 1, 500) },
					{ Type = "PetrifiedHollowed", Pos = Vector3.new(0, 1, 520) },
				},
			},
			ChoirOutpost = {
				Position = Vector3.new(150, 1, 450),
				Size = Vector3.new(150, 10, 200),
				Enemies = {
					{ Type = "ChoirVanguard", Pos = Vector3.new(120, 1, 435) },
					{ Type = "ChoirArchivist", Pos = Vector3.new(180, 1, 455) },
					{ Type = "AshenFamiliar", Pos = Vector3.new(150, 1, 475) },
				},
			},
		},
	},
	-- Ring 3 — Vael Depths (underground ruins, 550-750 studs)
	Ring3 = {
		Center = Vector3.new(0, 1, 650),
		RadiusInner = 550,
		RadiusOuter = 750,
		Zones = {
			HallOfAccord = {
				Position = Vector3.new(-150, 1, 620),
				Size = Vector3.new(150, 10, 200),
				Enemies = {
					{ Type = "PreservedSeated", Pos = Vector3.new(-180, 1, 610) },
					{ Type = "PreservedStanding", Pos = Vector3.new(-120, 1, 630) },
					{ Type = "MemoryShade", Pos = Vector3.new(-150, 1, 590) },
				},
			},
			CollapsedArchive = {
				Position = Vector3.new(0, 1, 680),
				Size = Vector3.new(150, 10, 200),
				Enemies = {
					{ Type = "ThreadweaverLurker", Pos = Vector3.new(-30, 1, 670) },
					{ Type = "ThreadweaverHunter", Pos = Vector3.new(30, 1, 700) },
					{ Type = "ArchiveCrawler", Pos = Vector3.new(0, 1, 720) },
				},
			},
			MemorialQuarter = {
				Position = Vector3.new(150, 1, 650),
				Size = Vector3.new(150, 10, 200),
				Enemies = {
					{ Type = "HollowRevenant", Pos = Vector3.new(120, 1, 635) },
					{ Type = "GriefTouched", Pos = Vector3.new(180, 1, 655) },
					{ Type = "WardenGhost", Pos = Vector3.new(150, 1, 675) },
				},
			},
		},
	},
	-- Ring 4 — Gloam (luminance drain, 750-950 studs)
	Ring4 = {
		Center = Vector3.new(0, 1, 850),
		RadiusInner = 750,
		RadiusOuter = 950,
		Zones = {
			Windfield = {
				Position = Vector3.new(-150, 1, 820),
				Size = Vector3.new(150, 10, 200),
				Enemies = {
					{ Type = "VaelbornDrifter", Pos = Vector3.new(-180, 1, 810) },
					{ Type = "VaelbornPack", Pos = Vector3.new(-120, 1, 830) },
					{ Type = "GloamShade", Pos = Vector3.new(-150, 1, 790) },
				},
			},
			SunkenChroirShrine = {
				Position = Vector3.new(0, 1, 880),
				Size = Vector3.new(150, 10, 200),
				Enemies = {
					{ Type = "ChoirAscendant", Pos = Vector3.new(-30, 1, 870) },
					{ Type = "ShrineWarden", Pos = Vector3.new(30, 1, 900) },
					{ Type = "HollowedPilgrim", Pos = Vector3.new(0, 1, 920) },
				},
			},
			NullApproach = {
				Position = Vector3.new(150, 1, 850),
				Size = Vector3.new(150, 10, 200),
				Enemies = {
					{ Type = "NullTouchedHollowed", Pos = Vector3.new(120, 1, 835) },
					{ Type = "WanderingPreserved", Pos = Vector3.new(180, 1, 855) },
					{ Type = "ConvergenceHerald", Pos = Vector3.new(150, 1, 875) },
				},
			},
		},
	},
}

-- Enemy type to CollectionService tag mapping
local ENEMY_TYPE_TAGS = {
	-- Ring 1
	HollowedDrifter = "HollowedSpawn",
	HollowedSentinel = "HollowedSpawn",
	Greyback = "CreatureSpawn",
	HollowedFisher = "HollowedSpawn",
	MurkLurker = "CreatureSpawn",
	SaturatedHollowed = "HollowedSpawn",
	HollowedScout = "HollowedSpawn",
	FringeCreeper = "CreatureSpawn",
	Dimling = "CreatureSpawn",
	-- Ring 2
	ChoirInitiate = "ChoirSpawn",
	ChoirPenitent = "ChoirSpawn",
	AshHound = "CreatureSpawn",
	HollowedChanneler = "HollowedSpawn",
	BasinStalker = "CreatureSpawn",
	PetrifiedHollowed = "HollowedSpawn",
	ChoirVanguard = "ChoirSpawn",
	ChoirArchivist = "ChoirSpawn",
	AshenFamiliar = "CreatureSpawn",
	-- Ring 3
	PreservedSeated = "PreservedSpawn",
	PreservedStanding = "PreservedSpawn",
	MemoryShade = "EnvironmentalSpawn",
	ThreadweaverLurker = "ThreadweaverSpawn",
	ThreadweaverHunter = "ThreadweaverSpawn",
	ArchiveCrawler = "CreatureSpawn",
	HollowRevenant = "HollowedSpawn",
	GriefTouched = "HollowedSpawn",
	WardenGhost = "PreservedSpawn",
	-- Ring 4
	VaelbornDrifter = "VaelbornSpawn",
	VaelbornPack = "VaelbornSpawn",
	GloamShade = "EnvironmentalSpawn",
	ChoirAscendant = "ChoirSpawn",
	ShrineWarden = "ChoirSpawn",
	HollowedPilgrim = "HollowedSpawn",
	NullTouchedHollowed = "HollowedSpawn",
	WanderingPreserved = "PreservedSpawn",
	ConvergenceHerald = "EnvironmentalSpawn",
}

-- Ground colors per ring (for visual distinction)
local RING_COLORS = {
	Ring1 = BrickColor.new("Medium green"),
	Ring2 = BrickColor.new("Dark stone grey"),
	Ring3 = BrickColor.new("Slate blue"),
	Ring4 = BrickColor.new("Dark slate blue"),
}

local RING_TRIGGER_COLORS = {
	Ring1 = BrickColor.new("Forest green"),
	Ring2 = BrickColor.new("Dark red"),
	Ring3 = BrickColor.new("Slate blue"),
	Ring4 = BrickColor.new("Midnight blue"),
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

-- ─── Create All Zones & Enemies ──────────────────────────────────────────────

print("\n[DevWorldBootstrap] Creating all ring zones and enemy spawns...")

for ringName, ringData in RINGS do
	print(`\n[DevWorldBootstrap] Setting up {ringName}...`)
	
	-- Create ground for this ring
	local groundName = ringName .. "Ground"
	if not Workspace:FindFirstChild(groundName) then
		makePart(
			groundName,
			Vector3.new(700, 1, 700),
			CFrame.new(ringData.Center.X, 0, ringData.Center.Z),
			RING_COLORS[ringName],
			true,
			true,
			0,
			Workspace
		)
		print(`  ✓ Created {groundName}`)
	end
	
	-- Create zone triggers
	local triggerSize = Vector3.new(
		(ringData.RadiusOuter - ringData.RadiusInner) * 2,
		10,
		(ringData.RadiusOuter - ringData.RadiusInner) * 2
	)
	local triggerName = ringName .. "Trigger"
	if not Workspace:FindFirstChild(triggerName) then
		local trigger = makePart(
			triggerName,
			triggerSize,
			CFrame.new(ringData.Center),
			RING_TRIGGER_COLORS[ringName],
			true,
			false,
			0.85,
			Workspace
		)
		trigger.Material = Enum.Material.Neon
		CollectionService:AddTag(trigger, ringName .. "Zone")
		print(`  ✓ Created {triggerName}`)
	end
	
	-- Create zones and enemy spawns
	for zoneName, zoneData in ringData.Zones do
		local zoneTriggerName = ringName .. "_" .. zoneName .. "_Trigger"
		if not Workspace:FindFirstChild(zoneTriggerName) then
			local zoneTrigger = makePart(
				zoneTriggerName,
				zoneData.Size,
				CFrame.new(zoneData.Position),
				RING_TRIGGER_COLORS[ringName],
				true,
				false,
				0.9,
				Workspace
			)
			print(`  ✓ Created zone trigger: {zoneName}`)
		end
		
		-- Create enemy spawns
		for _, enemyData in zoneData.Enemies do
			local enemyTag = ENEMY_TYPE_TAGS[enemyData.Type]
			if enemyTag then
				local spawnName = ringName .. "_" .. zoneName .. "_" .. enemyData.Type
				if not Workspace:FindFirstChild(spawnName) then
					local spawnPart = makePart(
						spawnName,
						Vector3.new(2, 0.2, 2),
						CFrame.new(enemyData.Pos),
						BrickColor.new("Dark red"),
						true,
						false,
						0.9,
						Workspace
					)
					CollectionService:AddTag(spawnPart, enemyTag)
					-- Add custom attributes for services to use
					spawnPart:SetAttribute("EnemyType", enemyData.Type)
					spawnPart:SetAttribute("Ring", ringName)
					spawnPart:SetAttribute("Zone", zoneName)
				end
			end
		end
		print(`  ✓ Created {#zoneData.Enemies} enemy spawns in {zoneName}`)
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
	print("\n[DevWorldBootstrap] Created Ring1Entrance pad at (0, 1, 180)")
end

print("\n[DevWorldBootstrap] ✅ All zones and enemy spawns created!")
print("[DevWorldBootstrap] Ring 1: 3 zones × 3 enemies = 9 spawn points")
print("[DevWorldBootstrap] Ring 2: 3 zones × 3 enemies = 9 spawn points")
print("[DevWorldBootstrap] Ring 3: 3 zones × 3 enemies = 9 spawn points")
print("[DevWorldBootstrap] Ring 4: 3 zones × 3 enemies = 9 spawn points")
print("[DevWorldBootstrap] Total: 36 enemy spawn points + 12 zone triggers")
print("[DevWorldBootstrap] See docs/Game Plan/World_Design.md for complete specifications")
