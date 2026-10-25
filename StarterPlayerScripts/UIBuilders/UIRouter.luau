--!strict
-- One-modal-at-a-time router (M5-09). Controllers register their modal under a
-- name; the side menu, hub stalls and hotkeys call open/toggle. Module state is
-- shared by every client script (same VM), so this is the single source of truth.

local UIRouter = {}

type Modal = {
	open: (arg: any?) -> (),
	close: () -> (),
}

local modals: { [string]: Modal } = {}
local current: string? = nil
local listeners: { (string?) -> () } = {}

local function notify()
	for _, listener in listeners do
		task.spawn(listener, current)
	end
end

function UIRouter.register(name: string, modal: Modal)
	modals[name] = modal
end

function UIRouter.open(name: string, arg: any?)
	if current and current ~= name and modals[current] then
		modals[current].close()
	end
	local modal = modals[name]
	if modal then
		current = name
		modal.open(arg)
		notify()
	end
end

function UIRouter.close(name: string?)
	local target = name or current
	if target and modals[target] then
		modals[target].close()
	end
	if target == current then
		current = nil
		notify()
	end
end

function UIRouter.toggle(name: string, arg: any?)
	if current == name then
		UIRouter.close(name)
	else
		UIRouter.open(name, arg)
	end
end

function UIRouter.current(): string?
	return current
end

-- Fires with the open modal name (or nil) whenever it changes.
function UIRouter.onChanged(listener: (string?) -> ())
	table.insert(listeners, listener)
end

return UIRouter
