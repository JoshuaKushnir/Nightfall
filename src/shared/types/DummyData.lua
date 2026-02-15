--!strict
--[[
	Class: DummyData
	Description: Data structure for combat test dummies
	Dependencies: None
]]

export type DummyData = {
	Id: string,
	Position: Vector3,
	Health: number,
	MaxHealth: number,
	IsActive: boolean,
	SpawnTime: number,
}

return {}