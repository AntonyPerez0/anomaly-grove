--!strict
-- Studio-only debug bridge: lets execute_luau drive LIVE server systems.
-- BindableEvent callbacks run in the VM that connected them, so firing this event
-- from the assistant's separate VM executes code with live module state.
-- Inert outside Studio; harmless in published games.

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local DebugBridge = {}

local EVENT_NAME = "DebugCommand"

export type Command = (player: Player?, args: { any }) -> ()

local commands: { [string]: Command } = {}
local event: BindableEvent? = nil

-- Register a command; name convention: "system:action".
function DebugBridge.register(name: string, fn: Command)
	commands[name] = fn
end

function DebugBridge.fire(name: string, player: Player?, ...: any)
	local ev = event
	if not ev then
		error("[DebugBridge] not initialized", 2)
	end
	ev:Fire(name, player, { ... })
end

function DebugBridge.init()
	if not RunService:IsStudio() then
		return
	end
	local existing = ServerScriptService:FindFirstChild(EVENT_NAME)
	if existing and existing:IsA("BindableEvent") then
		existing:Destroy()
	end
	local bindable = Instance.new("BindableEvent")
	bindable.Name = EVENT_NAME
	bindable.Parent = ServerScriptService
	event = bindable
	bindable.Event:Connect(function(name, player, args)
		local command = commands[name :: string]
		if not command then
			warn(`[DebugBridge] unknown command {name}`)
			return
		end
		local ok, err = pcall(command :: any, player :: Player?, args :: { any })
		if not ok then
			warn(`[DebugBridge] command {name} failed: {err}`)
		end
	end)
	print("[DebugBridge] ready (studio)")
end

return DebugBridge
