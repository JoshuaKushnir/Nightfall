--!strict
--[[
	Class: DummyData
	Description: Data structure for combat test dummies
	Dependencies: None
]]

export type DummyState = 
    "Normal" 
    | "Blocking" 
    | "Staggered"
    | "Idle" 
    | "Attacking" 
    | "Clashing" 
    | "ClashWindow" 
    | "ClashFollowSuccess" 
    | "ClashFollowMiss"

export type DummyData = {
	Id: string,
	Position: Vector3,
	Health: number,
	MaxHealth: number,
	Posture: number,
	MaxPosture: number,
	State: DummyState,
	IsActive: boolean,
	SpawnTime: number,
}

return {}