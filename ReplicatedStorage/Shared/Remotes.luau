--!strict
-- Single source of truth for remote names. The server creates every remote here
-- (RemotesInit.server.luau); clients resolve them with Remotes.get and never create remotes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type RemoteName =
	"ClaimPlot"
	| "HarvestSeed"
	| "PlaceCore"
	| "StealCore"
	| "TagHit"
	| "GrabCore"
	| "PhaseChanged"
	| "Juice"
	| "TutorialToast"
	| "OfflineSummary"
	| "BuyPedestal"
	| "BuyGadget"
	| "UseGadget"
	| "Rebirth"
	| "Discovery"
	| "BuyTurret"
	| "BuyLaserDoor"
	| "BuyTrapTile"
	| "ClaimQuest"
	| "ClaimDaily"
	| "SkillEvent"
	| "UpgradePedestal"
	| "UpgradeAll"
	| "BuyCrate"
	| "Infuse"
	| "MarketBuy"
	| "FuseCores"
	| "SetCompanion"
	| "RedeemCode"
	| "ClaimGroupReward"
	| "BuyTreeNode"
	| "BuyUpgrade"
	| "ClaimPass"
	| "SetCape"

local NAMES: { RemoteName } = {
	"ClaimPlot",
	"HarvestSeed",
	"PlaceCore",
	"StealCore",
	"TagHit",
	"GrabCore",
	"PhaseChanged",
	"Juice",
	"TutorialToast",
	"OfflineSummary",
	"BuyPedestal",
	"BuyGadget",
	"UseGadget",
	"Rebirth",
	"Discovery",
	"BuyTurret",
	"BuyLaserDoor",
	"BuyTrapTile",
	"ClaimQuest", -- M6-02: (index 1..PerDay)
	"ClaimDaily", -- M6-03: no args
	"SkillEvent", -- M8-02: server -> client XP drops + level-ups
	"UpgradePedestal", -- M8-04: (slot)
	"UpgradeAll", -- no args: buys the cheapest pedestal levels until cash runs out
	"BuyCrate", -- M8-05: (crateId)
	"Infuse", -- M8-04/Alchemy: (slot)
	"MarketBuy", -- M9-04: (slotIndex)
	"FuseCores", -- M9-05: (rarity)
	"SetCompanion", -- M9-07: (companionId | "None")
	"RedeemCode", -- M9-10: (text)
	"ClaimGroupReward", -- M9-10: no args
	"BuyTreeNode", -- M8-07: (nodeId)
	"BuyUpgrade", -- M8-08: (upgradeId)
	"ClaimPass", -- M8-10: (level)
	"SetCape", -- M8-03: (skill | "Max" | "None")
}

local Remotes = {
	names = NAMES,
}

-- Client helper: resolves a remote by name, waiting for replication.
function Remotes.get(name: RemoteName): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	local remote = folder:WaitForChild(name)
	if not remote:IsA("RemoteEvent") then
		error(`Remotes.{name} is not a RemoteEvent`, 2)
	end
	return remote
end

return Remotes
