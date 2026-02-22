--!strict
--[[
    Logger.lua

    Lightweight debug logging system with per-module toggles. Modules call
    `Logger.Log(moduleName, fmt, ...)` and output will only appear when the
    corresponding flag has been enabled via DebugSettings.

    Logging defaults to *off* for every module; this keeps the console quiet in
    release runs while allowing developers to turn on granular output during
    debugging.

    Public API:
      * Log(moduleName, fmt, ...)            -- formatted message (like printf)
      * Enable(moduleName)                  -- convenience wrapper
      * Disable(moduleName)                 -- convenience wrapper
      * IsEnabled(moduleName) -> boolean    -- check current state

    Internally this forwards to DebugSettings for storage so that the same
    mechanism can be toggled from the in-game console if desired.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Utils = require(ReplicatedStorage.Shared.modules.Utils)
local DebugSettings = require(ReplicatedStorage.Shared.modules.DebugSettings)

local Logger = {}

-- helper to build prefix
local function makeTag(moduleName: string): string
    return Utils.MakeTag(moduleName)
end

--[[
    Log a message for a specific module.  Arguments are identical to `string.format`.
    Output is suppressed unless logging has been enabled for the module.
]]
function Logger.Log(moduleName: string, fmt: string, ...: any)
    if not DebugSettings.IsLoggingEnabled(moduleName) then
        return
    end

    local prefix = makeTag(moduleName)
    if select("#", ...) > 0 then
        print(prefix .. " " .. string.format(fmt, ...))
    else
        -- avoid fmt being treated as format string when no extra args
        print(prefix .. " " .. fmt)
    end
end

-- convenience wrappers that mirror DebugSettings
function Logger.Enable(moduleName: string)
    DebugSettings.EnableLogging(moduleName)
end

function Logger.Disable(moduleName: string)
    DebugSettings.DisableLogging(moduleName)
end

function Logger.IsEnabled(moduleName: string): boolean
    return DebugSettings.IsLoggingEnabled(moduleName)
end

return Logger
