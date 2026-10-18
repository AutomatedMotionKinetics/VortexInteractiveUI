-- this gives the player every item in Items and puts the equipped one in the right hand.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local InteractiveUI = require(ReplicatedStorage:WaitForChild("InteractiveUI"))
local Inventory = require(ReplicatedStorage:WaitForChild("Inventory"))
local Items = require(ReplicatedStorage:WaitForChild("Items"))

local GRIP = CFrame.new(0, -1, 0) -- from the middle of the right arm to the hand

local models = workspace:FindFirstChild("Items")
while not models do
	task.wait(0.1)
	models = workspace:FindFirstChild("Items")
end

local ui = InteractiveUI.new()
local inventory = Inventory.new(ui)

local props = {}

for _, item in Items do
	local model = models:FindFirstChild(item.model)
	local handle = model and model:FindFirstChild("Handle")
	if handle then
		local parts = {}
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") then
				table.insert(parts, { part = part, offset = handle.CFrame:ToObjectSpace(part.CFrame) })
			end
		end
		props[item.id] = { parts = parts, home = handle.CFrame }
		inventory:add({ id = item.id, name = item.name, model = model })
	else
		print("no model named " .. item.model .. " with a Handle in workspace.Items")
	end
end

-- moves a model so its Handle ends up at cframe
local function move(id, cframe)
	for _, entry in props[id].parts do
		entry.part.CFrame = cframe * entry.offset
	end
end

-- scripts can't reach the avatar's own parts but the hitboxes follow its animations
local hand = Instance.new("Part")
hand.Name = "RightHand"
hand.Size = Vector3.new(0.2, 0.2, 0.2)
hand.Anchored = true
hand.CanCollide = false
hand.Parent = workspace
hand.Transparency = 1
hand.CanQuery = false -- it is invisible so rays shouldn't stop at it

local equipped = nil

inventory.onEquip = function(item)
	if equipped then
		move(equipped.id, props[equipped.id].home)
	end
	equipped = item
	print(item and ("equipped item " .. item.id .. " (" .. item.name .. ")") or "nothing equipped")
end

RunService.Heartbeat:Connect(function()
	local character = Players.LocalPlayer.Character
	local arm = character and character:FindFirstChild("Right Arm Hitbox")
	if not arm then
		return
	end
	local grip = arm.CFrame * GRIP
	hand.CFrame = grip
	if equipped then
		move(equipped.id, grip)
	end
end)
