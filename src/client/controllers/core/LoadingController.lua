--!strict
--[[
    LoadingController.lua

    Displays a client-side loading screen during bootstrap and asset
    preloading. Provides a progress bar, status text, rotating quotes, and
    a skip button.

    Usage:
        LoadingController:Init()
        LoadingController:Report("Waiting for LocalPlayer...", 0.1)
        ...
        LoadingController:Hide()

    The screen is created under PlayerGui and persists until Hide/Skip.
    Quotes can be edited in the _quotes table below.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LoadingController = {}

-- private fields
LoadingController._gui = nil :: ScreenGui?
LoadingController._statusLabel = nil :: TextLabel?
LoadingController._progressBar = nil :: Frame?
LoadingController._quoteLabel = nil :: TextLabel?
LoadingController._quotes = {
    "“Darkness reveals the stars.” — Unknown",
    "“In the Nightfall, we endure.”",
    "" -- add more phrases or keep editable via script
}
LoadingController._quoteIndex = 1
LoadingController._rotating = false

-- create the UI hierarchy
local function createGui(): ScreenGui
    local player = Players.LocalPlayer
    assert(player, "LoadingController requires LocalPlayer")

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "LoadingScreen"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = player:WaitForChild("PlayerGui")

    local bg = Instance.new("Frame")
    bg.Name = "Background"
    bg.Size = UDim2.new(1,0,1,0)
    bg.BackgroundColor3 = Color3.new(0,0,0)
    bg.BackgroundTransparency = 0.5
    bg.Parent = screenGui

    local container = Instance.new("Frame")
    container.Name = "Container"
    container.Size = UDim2.new(0.6,0,0.2,0)
    container.Position = UDim2.new(0.2,0,0.4,0)
    container.BackgroundColor3 = Color3.fromRGB(30,30,30)
    container.BorderSizePixel = 0
    container.Parent = bg

    local status = Instance.new("TextLabel")
    status.Name = "Status"
    status.Size = UDim2.new(1,-20,0,30)
    status.Position = UDim2.new(0,10,0,10)
    status.BackgroundTransparency = 1
    status.TextColor3 = Color3.new(1,1,1)
    status.TextScaled = true
    status.Text = "Starting..."
    status.Parent = container

    local progressBg = Instance.new("Frame")
    progressBg.Name = "ProgressBG"
    progressBg.Size = UDim2.new(1,-20,0,20)
    progressBg.Position = UDim2.new(0,10,0,50)
    progressBg.BackgroundColor3 = Color3.fromRGB(60,60,60)
    progressBg.BorderSizePixel = 0
    progressBg.Parent = container

    local progress = Instance.new("Frame")
    progress.Name = "ProgressBar"
    progress.Size = UDim2.new(0,0,1,0)
    progress.BackgroundColor3 = Color3.fromRGB(0,170,255)
    progress.BorderSizePixel = 0
    progress.Parent = progressBg

    local quote = Instance.new("TextLabel")
    quote.Name = "Quote"
    quote.Size = UDim2.new(1,-20,0,40)
    quote.Position = UDim2.new(0,10,0,80)
    quote.BackgroundTransparency = 1
    quote.TextColor3 = Color3.new(0.8,0.8,0.8)
    quote.TextScaled = true
    quote.TextWrapped = true
    quote.Text = ""
    quote.Parent = container

    local skip = Instance.new("TextButton")
    skip.Name = "SkipButton"
    skip.Size = UDim2.new(0,80,0,30)
    skip.Position = UDim2.new(1,-90,1,-40)
    skip.Text = "Skip"
    skip.BackgroundColor3 = Color3.fromRGB(50,50,50)
    skip.TextColor3 = Color3.new(1,1,1)
    skip.Parent = container

    skip.MouseButton1Click:Connect(function()
        screenGui.Enabled = false
    end)

    return screenGui
end

function LoadingController:Init()
    if self._gui then return end
    self._gui = createGui()
    self._statusLabel = self._gui:FindFirstChild("Background")
        :FindFirstChild("Container")
        :FindFirstChild("Status") :: TextLabel
    self._progressBar = self._gui:FindFirstChild("Background")
        :FindFirstChild("Container")
        :FindFirstChild("ProgressBG")
        :FindFirstChild("ProgressBar") :: Frame
    self._quoteLabel = self._gui:FindFirstChild("Background")
        :FindFirstChild("Container")
        :FindFirstChild("Quote") :: TextLabel
    self._gui.Enabled = true
    self:_startQuoteRotation()
end

function LoadingController:_startQuoteRotation()
    if self._rotating then return end
    self._rotating = true
    spawn(function()
        while self._gui and self._gui.Enabled do
            if #self._quotes > 0 then
                local q = self._quotes[self._quoteIndex] or ""
                self._quoteLabel.Text = q
                self._quoteIndex = self._quoteIndex % #self._quotes + 1
            end
            task.wait(5)
        end
        self._rotating = false
    end)
end

function LoadingController:Report(status: string, fraction: number?)
    if self._statusLabel then
        self._statusLabel.Text = status or ""
    end
    if self._progressBar and fraction then
        self._progressBar.Size = UDim2.new(math.clamp(fraction,0,1),0,1,0)
    end
end

function LoadingController:Hide()
    if self._gui then
        self._gui.Enabled = false
    end
end

return LoadingController
