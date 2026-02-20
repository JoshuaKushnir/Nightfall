--!strict
--[[
	Class: StateContext (type definition only)
	Description: Runtime context table passed to every movement state module's
	             Enter / Exit / Update / TryStart / OnJumpRequest methods.

	MovementController builds one StateContext per frame (in _Update) and per
	trigger event (slide key, jump press) from its current private state.
	State modules NEVER store the ctx reference beyond their call scope.

	Dependencies: MovementBlackboard (type reference only)
]]

export type StateContext = {
	-- ── Character refs (non-nil by the time ctx is built) ──────
	Humanoid        : Humanoid,
	RootPart        : BasePart,
	Character       : Model,

	-- ── Per-frame computed values ────────────────────────────────
	MoveDir         : Vector3,   -- camera-relative WASD input (world space)
	OnGround        : boolean,   -- FloorMaterial ~= Air
	IsSprinting     : boolean,   -- wantsSprint evaluated this frame
	LastMoveDir     : Vector3,   -- last non-zero MoveDir (world space)

	-- ── Shared state ─────────────────────────────────────────────
	Blackboard      : any,       -- MovementBlackboard table (state modules write flags here)

	-- ── Helper callbacks (bound to MovementController upvalues) ──
	ChainAction           : () -> (),
	DrainBreath           : (amount: number) -> boolean,
	GetMomentumMultiplier : () -> number,

	-- ── Module references ─────────────────────────────────────────
	AnimationLoader  : any,  -- shared AnimationLoader module
	NetworkController: any,  -- client NetworkController (optional, may be nil early on)
}

return {}
