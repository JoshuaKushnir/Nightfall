--!strict
--[[
	Class: MovementBlackboard
	Description: Client-side shared physics state for the movement system.
	             Written every Heartbeat by MovementController.
	             Read by any client system that needs locomotion context
	             (ActionController, PlayerHUDController, VFX handlers, etc.).

	Architecture:
	  MovementController  →  writes each frame via state modules + flush
	  ActionController    →  reads IsSprinting / IsSliding for lunge / buffer logic
	  PlayerHUDController →  reads Breath / MomentumMultiplier for HUD bars
	  VFX handlers        →  reads IsWallRunning / IsSliding etc. for particle cues

	NOTE: This is LOCAL to the client only. Server-side movement validation
	(MovementService) runs its own lightweight simulation and does NOT share this table.
	Use NetworkTypes packets to cross the boundary when needed.

	Dependencies: none
]]

-- Blackboard is a plain table — no metatables, no signals.
-- Kept flat and cheap to read: just index into the table.

local MovementBlackboard = {
	-- ── Locomotion flags ──────────────────────────────────────────
	IsGrounded      = false :: boolean,
	IsSprinting     = false :: boolean,
	IsSliding       = false :: boolean,
	IsWallRunning   = false :: boolean,
	IsVaulting      = false :: boolean,
	IsLedgeCatching = false :: boolean,
	IsClimbing      = false :: boolean,
	IsDodging       = false :: boolean,

	-- ── Vectors ──────────────────────────────────────────────────
	MoveDir     = Vector3.zero :: Vector3,  -- this-frame input direction (world)
	LastMoveDir = Vector3.zero :: Vector3,  -- last non-zero input direction (world)

	-- Last known wall-run surface normal (written by WallRunState).
	-- Readable by _OnJumpRequest for wall-kick direction.
	WallRunNormal = Vector3.zero :: Vector3,

	-- ── Speed ────────────────────────────────────────────────────
	CurrentSpeed = 0 :: number,

	-- ── Resources ────────────────────────────────────────────────
	MomentumMultiplier = 1.0 :: number,
	Breath             = 100 :: number,
	BreathExhausted    = false :: boolean,

	-- ── State machine ────────────────────────────────────────────
	ActiveState  = "Idle" :: string,

	-- ── Slide-jump flag ───────────────────────────────────────────
	-- Set by SlideState.OnJumpRequest; cleared on landing in _Update.
	SlideJumped = false :: boolean,
}

return MovementBlackboard
