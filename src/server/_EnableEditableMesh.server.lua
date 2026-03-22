-- _EnableEditableMesh.server.lua
-- Runs at server startup to set workspace.Capabilities to include DynamicGeneration
-- (required for EditableMesh / EditableImage APIs to work in Play mode)
-- This must live in ServerScriptService so it executes before any LocalScript loads.

workspace.Capabilities = SecurityCapabilities.new(Enum.SecurityCapability.DynamicGeneration)
print("[CapabilityFix] DynamicGeneration enabled on workspace (server)")
