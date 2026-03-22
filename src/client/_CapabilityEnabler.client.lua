-- _CapabilityEnabler.client.lua
-- Runs at client startup (before Client/ClientInit) to ensure workspace.Capabilities
-- includes DynamicGeneration for EditableMesh / EditableImage APIs.
-- Lives in StarterPlayerScripts root (not inside Client/) so it executes first.

workspace.Capabilities = SecurityCapabilities.new(Enum.SecurityCapability.DynamicGeneration)
print("[CapabilityEnabler] DynamicGeneration set on workspace (client-side)")
