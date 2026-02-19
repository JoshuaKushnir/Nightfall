--!strict
-- MovementService unit tests (server-side validation for slide requests)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementService = require(ReplicatedStorage.Server.services.MovementService)

return {
	name = "MovementService Unit Tests",
	tests = {
		{
			name = "Module exposes Init and Start",
			fn = function()
				assert(type(MovementService.Init) == "function")
				assert(type(MovementService.Start) == "function")
			end,
		},
		{
			name = "Registers RequestSlide handler on Start",
			fn = function()
				local stubNet = {
					handlers = {},
					RegisterHandler = function(self, name, fn) self.handlers[name] = fn end,
					SendToClient = function() end,
				}
				MovementService:Init({ NetworkService = stubNet })
				MovementService:Start()
				assert(stubNet.handlers["RequestSlide"] ~= nil)
			end,
		},
		{
			name = "Rejects malformed slide packet and notifies client",
			fn = function()
				local sent = {}
				local stubNet = {
					handlers = {},
					RegisterHandler = function(self, name, fn) self.handlers[name] = fn end,
					SendToClient = function(self, player, eventName, payload) table.insert(sent, { event = eventName, payload = payload }) end,
				}
				MovementService:Init({ NetworkService = stubNet })
				MovementService:Start()
				local handler = stubNet.handlers["RequestSlide"]
				assert(type(handler) == "function")
				-- Call handler with a fake player and malformed packet
				handler({}, { invalid = true })
				assert(#sent > 0, "Expected DebugInfo to be sent to client")
				assert(sent[1].event == "DebugInfo")
				assert(sent[1].payload and sent[1].payload.Category == "Movement")
			end,
		},
	},
}