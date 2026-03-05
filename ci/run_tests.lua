--[[
    ci/run_tests.lua
    Roblox Open Cloud Luau Execution test runner for Nightfall.

    Sent verbatim to the Open Cloud Engine API. Roblox loads the place,
    executes this script at GameScript level, and returns the result table.

    Supports TWO test file formats that co-exist in tests/unit/:

      Format A — table return (newer style):
        return {
            name = "Suite Name",
            tests = {
                { name = "test description", fn = function() ... end },
            }
        }

      Format B — self-executing (older style, e.g. AshExpression.test.lua):
        Files that print results inline and do NOT return a table.
        The runner wraps each in pcall; if it errors the whole file is
        counted as one failure.

    Return value (picked up by poll_task.py):
        {
            total   = number,
            passed  = number,
            failed  = number,
            skipped = number,
            suites  = {
                { suite = string, test = string, status = "pass"|"fail"|"skip", error = string? }
            }
        }

    Changing what gets tested:
        • Drop a new *.test.lua into tests/unit/ — it is picked up automatically.
        • To skip a file, rename it to *.test.lua.skip
        • To skip one test inside a Format-A suite, set  skip = true  on its entry.

    Timeout: tasks are given 5 minutes by the API (as of Feb 2025 update).
    If your suite takes longer, split it across multiple files.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─── locate the tests folder ─────────────────────────────────────────────────
-- Rojo syncs tests/ into ServerScriptService or ReplicatedStorage depending on
-- your project.json. Adjust the path below to match YOUR sync target.
-- Default assumption: tests live under ServerScriptService.tests.unit
local ServerScriptService = game:GetService("ServerScriptService")

local function findTestsFolder(): Folder?
    -- Try common Rojo sync locations in order
    local candidates = {
        ServerScriptService:FindFirstChild("tests")
            and ServerScriptService.tests:FindFirstChild("unit"),
        ReplicatedStorage:FindFirstChild("tests")
            and ReplicatedStorage.tests:FindFirstChild("unit"),
        ServerScriptService:FindFirstChild("unit"),
        ReplicatedStorage:FindFirstChild("unit"),
    }
    for _, candidate in ipairs(candidates) do
        if candidate then return candidate :: Folder end
    end
    return nil
end

-- ─── result accumulator ──────────────────────────────────────────────────────
local results = {
    total   = 0,
    passed  = 0,
    failed  = 0,
    skipped = 0,
    suites  = {} :: { {suite: string, test: string, status: string, error: string?} },
}

local function record(suite: string, test: string, status: string, err: string?)
    results.total += 1
    if status == "pass"  then results.passed  += 1 end
    if status == "fail"  then results.failed  += 1 end
    if status == "skip"  then results.skipped += 1 end
    table.insert(results.suites, { suite = suite, test = test, status = status, error = err })
    local icon = status == "pass" and "✓" or status == "skip" and "○" or "✗"
    local msg  = ("[%s] %s › %s"):format(icon, suite, test)
    if err then msg = msg .. "\n      " .. err end
    print(msg)
end

-- ─── Format A runner ─────────────────────────────────────────────────────────
local function runTableSuite(mod: ModuleScript)
    local ok, suite = pcall(require, mod)
    if not ok then
        record(mod.Name, "(require)", "fail", tostring(suite))
        return
    end
    if type(suite) ~= "table" or type(suite.tests) ~= "table" then
        -- Not Format A — caller will try Format B
        return false
    end

    local suiteName = tostring(suite.name or mod.Name)
    print(("\n── %s ──"):format(suiteName))

    for _, entry in ipairs(suite.tests) do
        local testName = tostring(entry.name or "unnamed")
        if entry.skip == true then
            record(suiteName, testName, "skip")
        else
            local testOk, testErr = pcall(entry.fn)
            if testOk then
                record(suiteName, testName, "pass")
            else
                record(suiteName, testName, "fail", tostring(testErr))
            end
        end
    end
    return true -- handled
end

-- ─── Format B runner ─────────────────────────────────────────────────────────
local function runSelfExecutingSuite(mod: ModuleScript)
    local suiteName = mod.Name
    print(("\n── %s (self-executing) ──"):format(suiteName))
    local ok, err = pcall(require, mod)
    if ok then
        record(suiteName, "(suite)", "pass")
    else
        record(suiteName, "(suite)", "fail", tostring(err))
    end
end

-- ─── main discovery loop ─────────────────────────────────────────────────────
local testsFolder = findTestsFolder()

if not testsFolder then
    -- Hard fail — CI should see this in logs and treat it as a setup error
    error("[run_tests] Could not locate tests/unit folder. "
        .. "Check your Rojo project.json sync targets.")
end

print("═══════════════════════════════════════════════════")
print("  Nightfall Test Runner")
print(("  Folder: %s"):format(testsFolder:GetFullName()))
print("═══════════════════════════════════════════════════")

for _, child in ipairs(testsFolder:GetChildren()) do
    if not child:IsA("ModuleScript") then continue end
    -- Skip files ending in .skip (rename to opt-out without deleting)
    if child.Name:sub(-5) == ".skip" then
        print(("[○] Skipping (opted-out): %s"):format(child.Name))
        continue
    end

    -- Try Format A first; fall back to Format B
    local handled = runTableSuite(child :: ModuleScript)
    if not handled then
        runSelfExecutingSuite(child :: ModuleScript)
    end
end

-- ─── summary ─────────────────────────────────────────────────────────────────
print("\n═══════════════════════════════════════════════════")
print(("  Results: %d passed  %d failed  %d skipped  (%d total)"):format(
    results.passed, results.failed, results.skipped, results.total))
print("═══════════════════════════════════════════════════\n")

-- Return the structured table — Open Cloud surfaces this as task.output.results
return results
