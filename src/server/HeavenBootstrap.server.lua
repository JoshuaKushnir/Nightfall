--!strict
-- Class: HeavenBootstrap
-- Description: Server-side bootstrap for Heaven environment setup. Initializes the ethereal plane
--              with terrain, glass monoliths, sky effects, and spawn location (Studio only).
-- Dependencies: RunService, Lighting, Workspace

local RunService = game:GetService("RunService")
local Lighting   = game:GetService("Lighting")
local Workspace  = game:GetService("Workspace")

if not RunService:IsStudio() then return end

local HEAVEN_Y      = 10000
local MEADOW_RADIUS = 2500
local GLASS_COLOR   = Color3.fromRGB(210, 235, 255)

local function setupEnvironment()
    Lighting.ClockTime            = 13.5
    Lighting.GeographicLatitude   = 15
    Lighting.Brightness           = 3.8
    Lighting.OutdoorAmbient       = Color3.fromRGB(170, 195, 255)
    Lighting.ShadowSoftness       = 0.35
    Lighting.ExposureCompensation = 0.55

    local atm                     = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere", Lighting)
    atm.Density                   = 0.32
    atm.Offset                    = 0.55
    atm.Color                     = Color3.fromRGB(185, 215, 255)
    atm.Decay                     = Color3.fromRGB(235, 248, 255)
    atm.Glare                     = 0.95
    atm.Haze                      = 3.0

    local clouds                  = Workspace.Terrain:FindFirstChildOfClass("Clouds") or
        Instance.new("Clouds", Workspace.Terrain)
    clouds.Cover                  = 0.65
    clouds.Density                = 0.72
    clouds.Color                  = Color3.fromRGB(255, 255, 255)

    local sr                      = Lighting:FindFirstChildOfClass("SunRaysEffect") or
        Instance.new("SunRaysEffect", Lighting)
    sr.Intensity                  = 0.45
    sr.Spread                     = 0.6

    local bloom                   = Lighting:FindFirstChildOfClass("BloomEffect") or
        Instance.new("BloomEffect", Lighting)
    bloom.Intensity               = 0.55
    bloom.Size                    = 32
    bloom.Threshold               = 1.4

    local cc                      = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or
        Instance.new("ColorCorrectionEffect", Lighting)
    cc.Brightness                 = 0.04
    cc.Contrast                   = 0.06
    cc.Saturation                 = 0.14
    cc.TintColor                  = Color3.fromRGB(255, 248, 230)

    print("[HeavenBootstrap] Environment configured")
end

local function createGlassL(name, position, rotation, scale)
    local model = Instance.new("Model")
    model.Name  = name
    local function makePart(size, offset)
        local p        = Instance.new("Part")
        p.Material     = Enum.Material.Glass
        p.Transparency = 0.38
        p.Reflectance  = 0.72
        p.Color        = GLASS_COLOR
        p.Size         = size * scale
        p.Anchored     = true
        p.CastShadow   = true
        p.CFrame       = CFrame.new(position)
            * CFrame.Angles(0, math.rad(rotation), 0)
            * CFrame.new(offset * scale)
        p.Parent       = model
    end
    local vertSz  = Vector3.new(200, 1200, 200)
    local horizSz = Vector3.new(1000, 200, 200)
    makePart(vertSz, Vector3.new(0, vertSz.Y / 2, 0))
    makePart(horizSz, Vector3.new(horizSz.X / 2 - vertSz.X / 2, vertSz.Y - 100, 0))
    model.Parent = Workspace
    return model
end

local function createFloor()
    local old = Workspace:FindFirstChild("HeavenlyFloor")
    if old then old:Destroy() end
    local floor      = Instance.new("Part")
    floor.Name       = "HeavenlyFloor"
    floor.Size       = Vector3.new(MEADOW_RADIUS * 2, 1, MEADOW_RADIUS * 2)
    floor.Position   = Vector3.new(0, HEAVEN_Y - 0.5, 0)
    floor.BrickColor = BrickColor.new("Bright green")
    floor.Material   = Enum.Material.Grass
    floor.Anchored   = true
    floor.Locked     = true
    floor.CastShadow = false
    floor.Parent     = Workspace
end

print("[HeavenBootstrap] Initializing Ethereal Infrastructure...")
setupEnvironment()
createFloor()
createGlassL("Monolith_Main", Vector3.new(-600, HEAVEN_Y, -800), 45, 1.0)
createGlassL("Monolith_FarRight", Vector3.new(1200, HEAVEN_Y, 400), -30, 1.4)
createGlassL("Monolith_Distance", Vector3.new(-2000, HEAVEN_Y, 1500), 120, 0.8)
createGlassL("Monolith_Near", Vector3.new(400, HEAVEN_Y, -200), 15, 0.65)

local spawn        = Instance.new("SpawnLocation")
spawn.Position     = Vector3.new(0, HEAVEN_Y + 5, 0)
spawn.Size         = Vector3.new(10, 1, 10)
spawn.Transparency = 1
spawn.CanCollide   = false
spawn.Anchored     = true
spawn.Parent       = Workspace

print("[HeavenBootstrap] Ethereal Plane constructed at Y=" .. HEAVEN_Y)
