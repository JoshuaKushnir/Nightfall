--!strict
-- Logger and DebugSettings unit tests (per-module logging toggles)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugSettings = require(ReplicatedStorage.Shared.modules.DebugSettings)
local Logger = require(ReplicatedStorage.Shared.modules.Logger)

return {
    name = "Logger/DebugSettings Unit Tests",
    tests = {
        {
            name = "Logging defaults to off",
            fn = function()
                assert(not DebugSettings.IsLoggingEnabled("SomeModule"))
                assert(not Logger.IsEnabled("SomeModule"))
            end,
        },
        {
            name = "Enable/disable toggles logging",
            fn = function()
                -- start clean
                DebugSettings.DisableLogging("Foo")
                assert(not Logger.IsEnabled("Foo"))
                -- verify storage table
                local all = DebugSettings.GetAll()
                assert(all.Logging and all.Logging["Foo"] == false)

                DebugSettings.EnableLogging("Foo")
                assert(Logger.IsEnabled("Foo"))
                all = DebugSettings.GetAll()
                assert(all.Logging and all.Logging["Foo"] == true)

                DebugSettings.ToggleLogging("Foo")
                assert(not Logger.IsEnabled("Foo"))
            end,
        },
        {
            name = "Logger.Log only prints when enabled",
            fn = function()
                local captured = {}
                local origPrint = print
                print = function(...)
                    local parts = {}
                    for i = 1, select("#", ...) do
                        parts[i] = tostring(select(i, ...))
                    end
                    table.insert(captured, table.concat(parts, " "))
                end

                -- ensure disabled
                DebugSettings.DisableLogging("Bar")
                Logger.Log("Bar", "hello %d", 1)
                assert(#captured == 0, "Expected no output when module logging disabled")

                -- enable and log again
                DebugSettings.EnableLogging("Bar")
                Logger.Log("Bar", "hello %d", 2)
                assert(#captured == 1, "Expected one printed message")
                assert(captured[1]:find("hello 2"), "Printed message should contain formatted text")

                -- restore
                print = origPrint
            end,
        },
    },
}
