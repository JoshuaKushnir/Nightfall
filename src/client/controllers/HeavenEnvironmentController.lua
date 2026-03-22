--!strict
local RunService                  = game:GetService("RunService")
local Lighting                    = game:GetService("Lighting")
local Workspace                   = game:GetService("Workspace")
local Players                     = game:GetService("Players")
local AssetService                = game:GetService("AssetService")

local HeavenEnvironmentController = {}

-- Constants
local HEAVEN_Y                    = 10000
local BLADE_WIDTH                 = 0.28
local BLADE_HEIGHT                = 5.0
local BLADE_SEGMENTS              = 3
local GRASS_POOL_SIZE             = 800
local DRAW_RADIUS                 = 150
local CELL_SIZE                   = 5.0
local UPDATE_THRESHOLD            = CELL_SIZE
local WIND_CHANGE_INTERVAL        = 5.0
local WIND_STRENGTH_MIN           = 6.0
local WIND_STRENGTH_MAX           = 22.0
local WIND_NOISE_SCALE            = 0.06
local WIND_NOISE_TIME             = 0.35
local WIND_GUST_FREQ              = 0.9
local GRASS_HUE_MIN               = 0.275; local GRASS_HUE_MAX = 0.355
local GRASS_SAT_MIN               = 0.55; local GRASS_SAT_MAX = 0.85
local GRASS_VAL_MIN               = 0.40; local GRASS_VAL_MAX = 0.70
local CLOUD_PULSE_SPEED           = 0.018; local CLOUD_COVER_BASE = 0.65; local CLOUD_COVER_AMP = 0.12
local CLOUD_DENSITY_BASE          = 0.72; local CLOUD_DENSITY_AMP = 0.08
local SUN_GLARE_ANGLE             = 35; local SUN_GLARE_ANGLE2 = 10; local FLARE_MAX_ALPHA = 0.55

-- State
local _initialized                = false
local _connections                = {}
local _clock                      = 0
local _bladeFolder
local _pool                       = {}
local _active                     = {}
local _lastGridX                  = math.huge; local _lastGridZ = math.huge
local _lastWindChange             = 0
local _windAngle                  = 0.0; local _windStrength = 12.0
local _windTargetAngle            = 0.0; local _windTargetStrength = 12.0
local _sunRaysEffect; local _bloomEffect; local _clouds; local _lensFlareGui

-- Seeded RNG
local function seededRand(x, z)
    local seed = math.abs(math.floor(x) * 2654435761 + math.floor(z) * 2246822519) % 2147483647
    return Random.new(seed)
end

-- Build blade EditableMesh -> MeshPart
-- Each blade is a segmented quad (BLADE_SEGMENTS strips) with:
--   • All vertex normals pointing straight up (0,1,0) — vegetation-style lighting
--   • UV V=0 at root, V=1 at tip — pairs with SDF alpha texture
--   • Slight width taper toward tip for a natural blade shape
local function buildBladeMesh()
    local em = AssetService:CreateEditableMesh()
    local nUp = em:AddNormal(Vector3.new(0, 1, 0))
    local vIds = {}; local uvIds = {}
    for row = 0, BLADE_SEGMENTS do
        local v     = row / BLADE_SEGMENTS
        local y     = v * BLADE_HEIGHT
        local halfW = BLADE_WIDTH * (1 - v * 0.6) -- taper toward tip
        local vRow  = {}; local uvRow = {}
        for col = 0, 1 do
            local x    = (col == 0) and -halfW or halfW
            vRow[col]  = em:AddVertex(Vector3.new(x, y, 0))
            uvRow[col] = em:AddUV(Vector2.new(col, v))
        end
        vIds[row] = vRow; uvIds[row] = uvRow
    end
    for row = 0, BLADE_SEGMENTS - 1 do
        local v00 = vIds[row][0]; local v10 = vIds[row][1]
        local v01 = vIds[row + 1][0]; local v11 = vIds[row + 1][1]
        local u00 = uvIds[row][0]; local u10 = uvIds[row][1]
        local u01 = uvIds[row + 1][0]; local u11 = uvIds[row + 1][1]
        local t1 = em:AddTriangle(v00, v10, v11)
        em:SetFaceNormals(t1, { nUp, nUp, nUp }); em:SetFaceUVs(t1, { u00, u10, u11 })
        local t2 = em:AddTriangle(v00, v11, v01)
        em:SetFaceNormals(t2, { nUp, nUp, nUp }); em:SetFaceUVs(t2, { u00, u11, u01 })
    end
    local ok, mp = pcall(function()
        return AssetService:CreateMeshPartAsync(Content.fromObject(em))
    end)
    em:Destroy()
    if not ok then
        warn("[HeavenEnv] Blade build failed: " .. tostring(mp)); return nil
    end
    local part      = mp
    part.Anchored   = true; part.CanCollide = false; part.CastShadow = false
    part.Name       = "GrassBlade"; part.Material = Enum.Material.SmoothPlastic
    -- SurfaceAppearance: SDF-style blade silhouette alpha map
    -- AlphaMode.Overlay clips transparent pixels at the blade edges
    -- ColorMap uses a tapered blade gradient for the silhouette
    local sa        = Instance.new("SurfaceAppearance")
    sa.AlphaMode    = Enum.AlphaMode.Overlay
    -- Wrap ColorMap in pcall since it requires Plugin capability (unavailable in client)
    local ok        = pcall(function()
        sa.ColorMap = "rbxassetid://131805673" -- grass blade silhouette
    end)
    if not ok then
        warn("[HeavenEnv] Warning: Could not set ColorMap (Plugin capability missing in Studio)")
    end
    sa.NormalMap = ""; sa.RoughnessMap = ""; sa.MetalnessMap = ""
    sa.Parent = part
    return part
end

-- Pool init
local function initGrassPool()
    _bladeFolder        = Instance.new("Folder")
    _bladeFolder.Name   = "HeavenGrass"
    _bladeFolder.Parent = Workspace
    local template      = buildBladeMesh()
    if not template then return end
    template.CFrame = CFrame.new(0, -9999, 0)
    template.Parent = _bladeFolder
    table.insert(_pool, template)
    for _ = 1, GRASS_POOL_SIZE - 1 do
        local c = template:Clone()
        c.CFrame = CFrame.new(0, -9999, 0)
        c.Parent = _bladeFolder
        table.insert(_pool, c)
    end
    print("[HeavenEnv] Grass pool ready: " .. #_pool .. " blades")
end

-- Scatter blades in a jittered grid around camera
local function scatterBladesAround(camX, camZ)
    for _, e in _active do
        e.part.CFrame = CFrame.new(0, -9999, 0)
        table.insert(_pool, e.part)
    end
    table.clear(_active)
    local floorY = HEAVEN_Y + 0.5
    local half   = math.ceil(DRAW_RADIUS / CELL_SIZE)
    for gx = -half, half do
        for gz = -half, half do
            if gx * gx + gz * gz > half * half then continue end
            if #_pool == 0 then break end
            local wx0    = camX + gx * CELL_SIZE
            local wz0    = camZ + gz * CELL_SIZE
            local rng    = seededRand(wx0, wz0)
            local wx     = wx0 + rng:NextNumber(-CELL_SIZE * 0.4, CELL_SIZE * 0.4)
            local wz     = wz0 + rng:NextNumber(-CELL_SIZE * 0.4, CELL_SIZE * 0.4)
            local hMul   = rng:NextNumber(0.72, 1.28)
            local rotY   = rng:NextNumber(0, math.pi * 2)
            local ph     = rng:NextNumber(0, math.pi * 2)
            local hue    = rng:NextNumber(GRASS_HUE_MIN, GRASS_HUE_MAX)
            local sat    = rng:NextNumber(GRASS_SAT_MIN, GRASS_SAT_MAX)
            local val    = rng:NextNumber(GRASS_VAL_MIN, GRASS_VAL_MAX)
            local blade  = table.remove(_pool)
            blade.Size   = Vector3.new(BLADE_WIDTH * 2, BLADE_HEIGHT * hMul, BLADE_WIDTH * 0.1)
            blade.Color  = Color3.fromHSV(hue, sat, val)
            blade.CFrame = CFrame.new(wx, floorY, wz) * CFrame.Angles(0, rotY, 0)
            table.insert(_active, { part = blade, worldX = wx, worldZ = wz, phase = ph, rotY = rotY })
        end
        if #_pool == 0 then break end
    end
    _lastGridX = camX; _lastGridZ = camZ
end

-- Wind
local function pickNewWindTarget()
    _windTargetAngle    = math.random() * math.pi * 2
    _windTargetStrength = WIND_STRENGTH_MIN + math.random() * (WIND_STRENGTH_MAX - WIND_STRENGTH_MIN)
end

local function updateWind(dt)
    local k       = 1 - math.exp(-dt * 0.8)
    local da      = (_windTargetAngle - _windAngle + math.pi * 3) % (math.pi * 2) - math.pi
    _windAngle    = _windAngle + da * k
    _windStrength = _windStrength + (_windTargetStrength - _windStrength) * k
end

-- Grass animation: rotate each blade from its root using noise-driven lean
-- tiltAxis is perpendicular to wind direction in XZ so blades lean correctly
local function animateGrass()
    if #_active == 0 then return end
    local floorY = HEAVEN_Y + 0.5
    local t      = _clock
    local wdx    = math.cos(_windAngle)
    local wdz    = math.sin(_windAngle)
    local str    = _windStrength
    for _, e in _active do
        local wx = e.worldX; local wz = e.worldZ; local ph = e.phase
        local n1 = math.noise(wx * WIND_NOISE_SCALE, wz * WIND_NOISE_SCALE, t * WIND_NOISE_TIME)
        local n2 = math.noise(wx * WIND_NOISE_SCALE * 0.4, t * WIND_GUST_FREQ + ph, 0)
        local combined = n1 * 0.65 + n2 * 0.35 + math.sin(t * 1.1 + ph) * 0.12
        local leanRad = math.rad(combined * str)
        local tiltAxis = Vector3.new(-wdz, 0, wdx)
        e.part.CFrame =
            CFrame.new(wx, floorY, wz)
            * CFrame.Angles(0, e.rotY, 0)
            * CFrame.fromAxisAngle(tiltAxis, leanRad)
    end
end

-- Clouds pulse
local function updateClouds(t)
    if not _clouds then return end
    _clouds.Cover   = CLOUD_COVER_BASE + math.sin(t * CLOUD_PULSE_SPEED) * CLOUD_COVER_AMP
    _clouds.Density = CLOUD_DENSITY_BASE + math.cos(t * CLOUD_PULSE_SPEED * 1.3) * CLOUD_DENSITY_AMP
end

-- Sun direction + lens flare
local function getSunDirection()
    local ok, dir = pcall(function() return Lighting:GetSunDirection() end)
    if ok and dir then return -dir end
    local t = (Lighting.ClockTime / 24) * math.pi * 2
    return Vector3.new(math.cos(t), math.sin(t) * 0.8, 0.2).Unit
end

local function buildLensFlareUI()
    local player = Players.LocalPlayer
    if not player then return end
    local gui = Instance.new("ScreenGui")
    gui.Name = "HeavenLensFlare"; gui.IgnoreGuiInset = true; gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; gui.Parent = player.PlayerGui
    local halo = Instance.new("ImageLabel")
    halo.Name = "Halo"; halo.AnchorPoint = Vector2.new(0.5, 0.5)
    halo.Size = UDim2.new(1.8, 0, 1.8, 0); halo.Position = UDim2.new(0.5, 0, 0.5, 0)
    halo.BackgroundTransparency = 1; halo.Image = "rbxassetid://6023426952"
    halo.ImageColor3 = Color3.fromRGB(255, 248, 210); halo.ImageTransparency = 1
    halo.ScaleType = Enum.ScaleType.Fit; halo.ZIndex = 10; halo.Parent = gui
    local streak = Instance.new("ImageLabel")
    streak.Name = "Streak"; streak.AnchorPoint = Vector2.new(0.5, 0.5)
    streak.Size = UDim2.new(1.4, 0, 1.4, 0); streak.Position = UDim2.new(0.5, 0, 0.5, 0)
    streak.BackgroundTransparency = 1; streak.Image = "rbxassetid://6023426952"
    streak.ImageColor3 = Color3.fromRGB(200, 225, 255); streak.ImageTransparency = 1
    streak.Rotation = 45; streak.ZIndex = 11; streak.Parent = gui
    _lensFlareGui = gui
end

local function updateSunEffect()
    if not _sunRaysEffect then return end
    local camera = Workspace.CurrentCamera; if not camera then return end
    local sunDir = getSunDirection(); local camDir = camera.CFrame.LookVector
    local dot = camDir:Dot(sunDir)
    local angleDeg = math.deg(math.acos(math.clamp(dot, -1, 1)))
    local t = 1 - math.clamp((angleDeg - SUN_GLARE_ANGLE2) / (SUN_GLARE_ANGLE - SUN_GLARE_ANGLE2), 0, 1)
    t = t * t
    _sunRaysEffect.Intensity = 0.05 + t * 0.85; _sunRaysEffect.Spread = 0.4 + t * 0.35
    if _bloomEffect then
        _bloomEffect.Intensity = 0.4 + t * 0.7; _bloomEffect.Threshold = 1.5 - t * 0.6
    end
    if _lensFlareGui then
        local halo = _lensFlareGui:FindFirstChild("Halo"); local streak = _lensFlareGui:FindFirstChild("Streak")
        local alpha = 1 - t * FLARE_MAX_ALPHA
        if halo then halo.ImageTransparency = alpha end
        if streak then streak.ImageTransparency = alpha + 0.18 end
    end
end

-- Post-FX setup
local function setupPostProcessing()
    local sr = Lighting:FindFirstChildOfClass("SunRaysEffect") or Instance.new("SunRaysEffect", Lighting)
    sr.Intensity = 0.05; sr.Spread = 0.5; _sunRaysEffect = sr
    local bl = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect", Lighting)
    bl.Intensity = 0.5; bl.Size = 30; bl.Threshold = 1.5; _bloomEffect = bl
    local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect", Lighting)
    cc.Brightness = 0.04; cc.Contrast = 0.06; cc.Saturation = 0.12; cc.TintColor = Color3.fromRGB(255, 248, 235)
    local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect") or Instance.new("DepthOfFieldEffect", Lighting)
    dof.FarIntensity = 0.15; dof.NearIntensity = 0.0; dof.FocusDistance = 80; dof.InFocusRadius = 40
end

-- Lifecycle
function HeavenEnvironmentController:Init()
    _clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds")
    _initialized = true
end

function HeavenEnvironmentController:Start()
    if not _initialized then
        warn("[HeavenEnv] Not initialized"); return
    end
    _clouds = _clouds or Workspace.Terrain:FindFirstChildOfClass("Clouds")

    setupPostProcessing()
    buildLensFlareUI()
    pickNewWindTarget()

    -- Start heartbeat immediately (animateGrass is a no-op until pool is populated)
    local conn = RunService.Heartbeat:Connect(function(dt)
        _clock += dt
        if _clock - _lastWindChange > WIND_CHANGE_INTERVAL then
            pickNewWindTarget(); _lastWindChange = _clock
        end
        updateWind(dt)
        animateGrass()
        updateClouds(_clock)
        updateSunEffect()
        local camera = Workspace.CurrentCamera
        if camera then
            local p  = camera.CFrame.Position
            local dx = p.X - _lastGridX
            local dz = p.Z - _lastGridZ
            if dx * dx + dz * dz > UPDATE_THRESHOLD * UPDATE_THRESHOLD then
                scatterBladesAround(p.X, p.Z)
            end
        end
    end)
    table.insert(_connections, conn)

    -- Defer grass pool build to next frame.
    -- This escapes the synchronous bootstrap pcall() wrapper so that:
    --   1. _CapabilityEnabler.client.lua has already run
    --   2. _EnableEditableMesh.server.lua has propagated workspace.Capabilities
    --   3. Any errors from EditableMesh are caught by our own retry pcall
    task.defer(function()
        local capOk = false
        for attempt = 1, 10 do
            local ok = pcall(function()
                local em = AssetService:CreateEditableMesh()
                em:Destroy()
            end)
            if ok then
                capOk = true
                break
            end
            print("[HeavenEnv] EditableMesh not ready (attempt " .. attempt .. "), retrying in 0.15s...")
            task.wait(0.15)
        end

        if not capOk then
            warn(
            "[HeavenEnv] Grass disabled — EditableMesh inaccessible after 1.5s. Enable 'Allow Mesh/Image Edit APIs' in Game Settings > Security.")
            return
        end

        -- Extra stabilisation wait: capability confirmed but give the engine
        -- one more full frame to fully propagate the security context before
        -- we call CreateEditableMesh for real inside buildBladeMesh.
        task.wait(0.25)

        local poolOk, poolErr = pcall(initGrassPool)
        if not poolOk then
            warn("[HeavenEnv] Grass pool build failed: " .. tostring(poolErr))
            return
        end
        if #_pool == 0 then
            warn("[HeavenEnv] Grass pool build failed — no blades created")
            return
        end

        local cam    = Workspace.CurrentCamera
        local camPos = cam and cam.CFrame.Position or Vector3.new(0, HEAVEN_Y + 5, 0)
        scatterBladesAround(camPos.X, camPos.Z)
        print("[HeavenEnv] Grass active — " .. #_active .. " blades visible")
    end)

    print("[HeavenEnv] Heaven environment running (mesh grass v2 — deferred init)")
end

function HeavenEnvironmentController:Stop()
    for _, c in _connections do c:Disconnect() end
    table.clear(_connections)
    if _bladeFolder then _bladeFolder:Destroy() end
    if _lensFlareGui then
        _lensFlareGui:Destroy(); _lensFlareGui = nil
    end
end

return HeavenEnvironmentController
