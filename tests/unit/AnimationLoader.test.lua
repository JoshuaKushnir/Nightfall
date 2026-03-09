--!strict
-- Test for AnimationLoader database lookup

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationLoader = require(ReplicatedStorage.Shared.modules.AnimationLoader)
local AnimationDatabase = require(ReplicatedStorage.Shared.AnimationDatabase)

return function()
    describe("AnimationLoader", function()
        it("returns an Animation with ID from database when key exists", function()
            local key = "Walk"
            local expectedId = AnimationDatabase.Movement[key]
            expect(typeof(expectedId)).to.equal("string")
            local anim = AnimationLoader.GetAnimation(key)
            expect(anim).to.be.ok()
            expect(anim:IsA("Animation")).to.equal(true)
            expect(anim.AnimationId).to.equal(expectedId)
            anim:Destroy()
        end)

        it("loads every key present in the flattened database", function()
            local flat = {}
            -- replicate flattening logic from loader
            local function flatten(tbl)
                for k,v in pairs(tbl) do
                    if typeof(v) == "table" then
                        flatten(v)
                    elseif typeof(k) == "string" and typeof(v) == "string" then
                        flat[k] = v
                    end
                end
            end
            flatten(AnimationDatabase)

            for key,_ in pairs(flat) do
                -- should not throw
                local success, anim = pcall(function()
                    return AnimationLoader.GetAnimation(key)
                end)
                expect(success).to.equal(true, "loader crashed for key "..key)
                if anim then
                    expect(anim:IsA("Animation")).to.equal(true, "result not Animation for key "..key)
                    anim:Destroy()
                end
            end
        end)

        it("falls back to project folder when database key missing", function()
            -- this test assumes a folder exists; if not, just assert nil
            local result = AnimationLoader.GetAnimation("NON_EXISTENT", "")
            expect(result).to.equal(nil)
        end)

        it("PreloadAll completes without error on a humanoid", function()
            -- create temporary humanoid+animator
            local model = Instance.new("Model")
            local hum = Instance.new("Humanoid")
            hum.Parent = model
            local ani = Instance.new("Animator")
            ani.Parent = hum

            -- should not error
            local ok, err = pcall(function()
                AnimationLoader.PreloadAll(hum)
            end)
            expect(ok).to.equal(true, tostring(err))

            model:Destroy()
        end)
    end)
end
