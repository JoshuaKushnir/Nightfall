import re

with open("src/client/controllers/MovementController.lua", "r") as f:
    content = f.read()

replacement = """local _cachedCtx: any = {
	Blackboard            = Blackboard,
	AnimationLoader       = AnimationLoader,
}

-- Builds the context table passed to all state module methods.
-- Call with current-frame values so state modules always see fresh data.
local function _buildCtx(moveDir: Vector3, onGround: boolean, wantsSpr: boolean): any
	if not _cachedCtx.ChainAction then
		_cachedCtx.ChainAction           = ChainAction
		_cachedCtx.DrainBreath           = DrainBreath
		_cachedCtx.GetMomentumMultiplier = MovementController.GetMomentumMultiplier
		_cachedCtx.NetworkController     = NetworkController
	end

	_cachedCtx.Humanoid    = Humanoid
	_cachedCtx.RootPart    = RootPart
	_cachedCtx.Character   = Character
	_cachedCtx.MoveDir     = moveDir
	_cachedCtx.OnGround    = onGround
	_cachedCtx.IsSprinting = wantsSpr
	_cachedCtx.LastMoveDir = lastMoveDirection

	return _cachedCtx
end"""

old_code = """-- Builds the context table passed to all state module methods.
-- Call with current-frame values so state modules always see fresh data.
local function _buildCtx(moveDir: Vector3, onGround: boolean, wantsSpr: boolean): any
	return {
		Humanoid              = Humanoid :: Humanoid,
		RootPart              = RootPart :: BasePart,
		Character             = Character :: Model,
		MoveDir               = moveDir,
		OnGround              = onGround,
		IsSprinting           = wantsSpr,
		LastMoveDir           = lastMoveDirection,
		Blackboard            = Blackboard,
		ChainAction           = ChainAction,
		DrainBreath           = DrainBreath,
		GetMomentumMultiplier = MovementController.GetMomentumMultiplier,
		AnimationLoader       = AnimationLoader,
		NetworkController     = NetworkController,
	}
end"""

content = content.replace(old_code, replacement)

with open("src/client/controllers/MovementController.lua", "w") as f:
    f.write(content)
