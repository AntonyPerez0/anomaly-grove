--!strict
-- Creates every game remote under ReplicatedStorage.Remotes on server start.
-- Clients resolve them with ReplicatedStorage.Shared.Remotes.get(name).
--
-- M4-02 EXPLOIT-HARDENING AUDIT (every handler re-validates types/ranges/cooldowns;
-- all money math is server-side — the client never sends amounts):
--   ClaimPlot      plotIndex:number; reach gate <= Map.ClaimDistance to the plot's
--                  ClaimZone; plot must be free; touch debounce. (PlotSystem)
--   HarvestSeed    no args; nearest node within Seeds.HarvestDistance; backpack cap.
--                  (SeedSystem)
--   PlaceCore      no args; nearest pedestal; must be the player's own plot,
--                  pedestal free, seed carried; seed consumption server-side.
--                  (CoreSystem)
--   StealCore      plotIndex+slot numbers (malformed dropped + rate-limited log);
--                  canStealFrom rules + reach gate <= Steal.InteractDistance to
--                  the pedestal; steal immunity; vault/lockdown/owner checks. (StealSystem)
--   GrabCore       no args; nearest drop within Seeds.HarvestDistance; owner-lock
--                  + already-carrying checks. (StealSystem)
--   TagHit         victim must be a Player instance; zapper cooldown + range +
--                  not-self checks. (StealSystem)
--   BuyPedestal    no args; slots/plot/cash validated in checkPedestalPurchase +
--                  re-checked spend (server price table). (PlotSystem)
--   BuyGadget      gadget:string in the known set; owned check; server price.
--                  (GadgetSystem)
--   UseGadget      gadget:string in the known set; owned + per-gadget cooldown;
--                  aim Vector3 optional. (GadgetSystem)
--   Rebirth        no args; NetWorth gate + capacity rules server-side. (RebirthSystem)
--   BuyTurret      no args; claim + turret limit + capacity + server price. (DefenseSystem)
--   BuyLaserDoor   no args; shared gap-defense gate + server price. (DefenseSystem)
--   BuyTrapTile    no args; shared gap-defense gate + server price. (DefenseSystem)
--   ClaimQuest     (index) integer 1..Quests.PerDay; quest must be complete + unclaimed;
--                  reward computed server-side; per-player 0.5 s rate limit. (QuestService)
--   ClaimDaily     no args; once per UTC day; reward from Config.Daily by server streak. (DailyRewardService)
--   PhaseChanged   server -> client only (never fired by clients; server never reads it).
--   Juice          server -> client only.
--   TutorialToast  server -> client only.
--   OfflineSummary server -> client only.
--   Discovery      server -> client only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)

-- Re-running (hot reload) replaces the old folder wholesale.
local existing = ReplicatedStorage:FindFirstChild("Remotes")
if existing then
	existing:Destroy()
end

local folder = Instance.new("Folder")
folder.Name = "Remotes"

for _, name in Remotes.names do
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
end

folder.Parent = ReplicatedStorage
print(`[RemotesInit] created {#Remotes.names} remotes`)
