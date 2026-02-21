--!strict
--[[
	CombatBlackboard

	Client-side shared combat state for the advanced combat system.  Mirrors the
	role of MovementBlackboard: written each frame by CombatController and
	read by other client systems (ActionController, PlayerHUDController, VFX, etc.).

	This is intentionally lightweight: just flat flags and values that are
	cheap to read.
]]

local CombatBlackboard = {
	-- primary flags
	IsAttacking   = false :: boolean,
	IsBlocking    = false :: boolean,
	IsParrying    = false :: boolean,
	IsStunned     = false :: boolean,

	-- optional data
	ActiveState   = "Idle" :: string,
	LastHitTime   = 0 :: number, -- for hitstop or stagger windows
}

return CombatBlackboard
