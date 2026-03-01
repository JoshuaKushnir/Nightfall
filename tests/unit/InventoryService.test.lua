--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryService = require(ReplicatedStorage.Server.services.InventoryService)
local DataService = require(ReplicatedStorage.Server.services.DataService)
local AspectService = require(ReplicatedStorage.Server.services.AspectService)
local AspectRegistry = require(ReplicatedStorage.Shared.modules.AspectRegistry)

-- stub StateService for ability casting
local StateService = require(ReplicatedStorage.Shared.modules.StateService)
StateService.GetState = function() return "Idle" end
StateService.SetState = function() end

return {
    name = "InventoryService Unit Tests",
    tests = {
        {
            name = "Give and remove item updates profile inventory",
            fn = function()
                local fakePlayer = {}
                -- prepare fake profile
                DataService._profiles[fakePlayer] = {
                    IsActive = function() return true end,
                    Data = {
                        Inventory = {},
                        EquippedItems = {},
                    },
                }

                local item = {
                    Id = "test1",
                    Name = "Test Item",
                    Description = "",
                    Category = "Consumable",
                }

                assert(InventoryService.GiveItem(fakePlayer, item) == true)
                local profile = DataService:GetProfile(fakePlayer)
                assert(#profile.Inventory == 1 and profile.Inventory[1].Id == "test1")

                assert(InventoryService.RemoveItem(fakePlayer, "test1") == true)
                assert(#profile.Inventory == 0)
            end,
        },
        {
            name = "Equip and unequip functionality stores item in slot",
            fn = function()
                local fakePlayer = {}
                DataService._profiles[fakePlayer] = {
                    IsActive = function() return true end,
                    Data = {Inventory = {}, EquippedItems = {}}
                }
                local item = {Id = "foo", Name="foo", Description="", Category="Consumable"}
                InventoryService.GiveItem(fakePlayer, item)
                assert(InventoryService.SetEquipped(fakePlayer, "hotbar1", "foo") == true)
                local profile = DataService:GetProfile(fakePlayer)
                assert(profile.EquippedItems.hotbar1 and profile.EquippedItems.hotbar1.Id == "foo")
                InventoryService.SetEquipped(fakePlayer, "hotbar1", nil)
                assert(profile.EquippedItems.hotbar1 == nil)
            end,
        },
        {
            name = "Equipping AspectMove triggers use and does not populate slot",
            fn = function()
                local called = false
                -- stub AspectService.ExecuteAbility
                AspectService.ExecuteAbility = function(p, abilityId, tp)
                    called = true
                    return true
                end
                local fakePlayer = {}
                DataService._profiles[fakePlayer] = {
                    IsActive = function() return true end,
                    Data = {Inventory = {}, EquippedItems = {}}
                }
                local moveItem = {Id = "move1", Name="m", Description="", Category="AspectMove", AbilityId="a1", AspectId="Ash"}
                InventoryService.GiveItem(fakePlayer, moveItem)
                assert(InventoryService.SetEquipped(fakePlayer, "hotbar2", "move1") == true)
                assert(called == true, "AspectService should have been invoked")
                local profile = DataService:GetProfile(fakePlayer)
                assert(profile.EquippedItems.hotbar2 == nil, "AspectMove should not stay equipped")
            end,
        },
        {
            name = "Using AspectMove forwards to AspectService",
            fn = function()
                local fakePlayer = {}
                DataService._profiles[fakePlayer] = {
                    IsActive = function() return true end,
                    Data = {
                        Inventory = {},
                        EquippedItems = {},
                        Mana = {Current = 100, Max = 100, Regen = 0, RegenDelay = 0},
                        ActiveCooldowns = {},
                        AspectData = {
                            AspectId = "Ash",
                            Branches = {
                                Expression = {Depth = 3, ShardsInvested = 0},
                                Form = {Depth = 0, ShardsInvested = 0},
                                Communion = {Depth = 0, ShardsInvested = 0},
                            },
                            TotalShardsInvested = 0,
                        },
                    }
                }

                -- choose an existing ability from registry
                local ability = next(AspectRegistry.GetAbilitiesForAspect("Ash"))
                assert(ability, "expected at least one Ash ability")

                local moveItem = {
                    Id = "move1",
                    Name = "Move",
                    Description = "",
                    Category = "AspectMove",
                    AbilityId = ability.Id,
                    AspectId = "Ash",
                }
                InventoryService.GiveItem(fakePlayer, moveItem)
                local success, reason = InventoryService.UseItem(fakePlayer, "move1")
                assert(success == true)
            end,
        },
        {
            name = "New player receives test moves automatically",
            fn = function()
                local fakePlayer = {}
                DataService._profiles[fakePlayer] = {
                    IsActive = function() return true end,
                    Data = {Inventory = {}, EquippedItems = {}}
                }
                -- trigger join
                InventoryService._onPlayerAdded(fakePlayer)
                local profile = DataService:GetProfile(fakePlayer)
                -- should have two moves, fists, and ability items
                -- moves: 2, fists:1, abilities: >= 1
                assert(#profile.Inventory >= 4, "Expected at least two moves, fists, and abilities")
                local foundFists, foundAbility = false, false
                for _, v in ipairs(profile.Inventory) do
                    if v.Id == "weapon_fists" then
                        foundFists = true
                    end
                    if v.Category == "Abilities" then
                        foundAbility = true
                    end
                end
                assert(foundFists, "Fists item should be granted")
                assert(foundAbility, "At least one ability item should be granted")
            end,
        },
        {
            name = "Grant test moves even if inventory nonempty, no duplicates",
            fn = function()
                local fakePlayer = {}
                DataService._profiles[fakePlayer] = {
                    IsActive = function() return true end,
                    Data = {Inventory = {{Id="other"}} , EquippedItems = {}}
                }
                InventoryService._onPlayerAdded(fakePlayer)
                local profile = DataService:GetProfile(fakePlayer)
                local foundQuick, foundStrong, foundFists, foundAbility = false, false, false, false
                for _, v in ipairs(profile.Inventory) do
                    if v.Id == "move_Test_Move_Quick" then foundQuick = true end
                    if v.Id == "move_Test_Move_Strong" then foundStrong = true end
                    if v.Id == "weapon_fists" then foundFists = true end
                    if v.Category == "Abilities" then foundAbility = true end
                end
                assert(foundQuick and foundStrong and foundFists and foundAbility, "Starter moves, fists and abilities should be present")
            end,
        },
        {
            name = "Explicit EquipWeapon syncs profile",
            fn = function()
                local fakePlayer = {}
                DataService._profiles[fakePlayer] = {
                    IsActive = function() return true end,
                    Data = {Inventory = {{Id="weapon_fists", Name="Fists", Category="Weapons"}}, EquippedItems = {}}
                }
                -- call the updated handler logic, which places weapon in slot "1"
                InventoryService.SetEquipped(fakePlayer, "1", "weapon_fists")
                local profile = DataService:GetProfile(fakePlayer)
                assert(profile.EquippedItems["1"] ~= nil, "profile should record weapon in slot 1")
            end,
        },
        {
            name = "EquipWeapon handler respects provided slot",
            fn = function()
                local fakePlayer = {}
                DataService._profiles[fakePlayer] = {
                    IsActive = function() return true end,
                    Data = {Inventory = {{Id="weapon_axe",Name="Axe",Category="Weapons"}}, EquippedItems = {}}
                }
                -- simulate network event with table including slot
                local handler = function(player, packet)
                    local weaponId, slot
                    if type(packet) == "string" then
                        weaponId = packet
                    elseif type(packet) == "table" then
                        weaponId = packet.WeaponId
                        slot = packet.Slot
                    end
                    if weaponId then
                        InventoryService.SetEquipped(player, slot or "1", weaponId)
                    end
                end
                handler(fakePlayer, {WeaponId="weapon_axe", Slot="5"})
                local profile = DataService:GetProfile(fakePlayer)
                assert(profile.EquippedItems["5"] ~= nil, "weapon should be in provided slot")
            end,
        },

        {
            name = "EquipWeapon handler accepts string payload",
            fn = function()
                local fakePlayer = {}
                DataService._profiles[fakePlayer] = {
                    IsActive = function() return true end,
                    Data = {Inventory = {{Id="weapon_fists", Name="Fists", Category="Weapons"}}, EquippedItems = {}}
                }
                -- replicate handler logic from InventoryService:Start
                local function handler(player, packet)
                    local weaponId
                    if type(packet) == "string" then
                        weaponId = packet
                    elseif type(packet) == "table" then
                        weaponId = packet.WeaponId
                    end
                    if weaponId then
                        InventoryService.SetEquipped(player, weaponId, weaponId)
                    end
                end
                handler(fakePlayer, "weapon_fists")
                local profile = DataService:GetProfile(fakePlayer)
                assert(profile.EquippedItems.weapon_fists ~= nil, "string payload should equip weapon")
            end,
        },

    },
}
