--!strict
-- Shared collision groups (M5-04). Decoration (trees, rocks, stones) never blocks
-- monsters, which chase with straight Humanoid:MoveTo; players still collide with it.
-- Safe to call at runtime and in Edit mode (registration is idempotent).

local PhysicsService = game:GetService("PhysicsService")

local CollisionGroups = {
	Decor = "Decor",
	Monsters = "Monsters",
}

local ensured = false

function CollisionGroups.ensure()
	if ensured then
		return
	end
	for _, name in { CollisionGroups.Decor, CollisionGroups.Monsters } do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(CollisionGroups.Decor, CollisionGroups.Monsters, false)
	ensured = true
end

return CollisionGroups
