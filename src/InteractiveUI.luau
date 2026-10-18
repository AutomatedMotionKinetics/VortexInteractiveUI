local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local FIELD_OF_VIEW = 70 -- vertical, in degrees
local PANEL_SCALE = 0.1
local SMALLEST_PART = 0.05
local LAYER_GAP = 0.004
local RECT_DEPTH = 0.1
local BEHIND_CAMERA = CFrame.new(0, 0, 50)
local FAR_AWAY = CFrame.new(0, 10000, 0)

local CHECKS_PER_FRAME = 24
local MOVED = 0.05
local REST = 60
local SETTLE = 120

local InteractiveUI = {}
InteractiveUI.__index = InteractiveUI

local Panel = {}
Panel.__index = Panel

local Rect = {}
Rect.__index = Rect

local function adopt(part, parent)
	part.Anchored = true
	part.CanCollide = false
	pcall(function()
		part.CastShadow = false
	end)
	part.Parent = parent
	pcall(function()
		part.CanQuery = false
	end)
end

local function newPart(name, size, color, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	adopt(part, parent)
	return part
end

-- a panel is an invisible root part with its rects as children
-- children take the root's size as scale
local function makeRoot(panel)
	local scale = panel._scale
	panel._root = newPart(panel._name, Vector3.new(scale, scale, scale), Color3.fromRGB(255, 255, 255), workspace)
	panel._root.Transparency = 1
	panel._fresh = true
	panel._rest = REST
end

-- a child is a rect or a clone of one of a model's parts
local function makeChild(panel, child)
	local part
	if child.source then
		part = child.source:Clone()
		if child.color then
			part.Color = child.color
		end
		if child.material then
			part.Material = child.material
		end
		adopt(part, panel._root)
	else
		part = newPart(child.name, Vector3.new(1, 1, 1), child.color, panel._root)
		if child.transparency then
			part.Transparency = child.transparency
		end
	end
	-- sized and placed once
	if child.size then
		part.Size = child.size
	end
	part.CFrame = child.cframe
	child.part = part
end

local function hasMoved(child)
	local ok, at = pcall(function()
		return child.part.Position
	end)
	if not ok or not at then
		return true
	end
	local put = child.cframe.Position
	return math.abs(at.X - put.X) + math.abs(at.Y - put.Y) + math.abs(at.Z - put.Z) > MOVED
end

local function newPanel(ui, props, scale)
	local panel = setmetatable({}, Panel)
	panel.ui = ui
	panel.x = props.x or 0
	panel.y = props.y or 0
	panel.layer = props.layer or 0
	panel.visible = props.visible ~= false
	panel._name = props.name or "Panel"
	panel._scale = scale
	panel._rects = {}
	panel._children = {}
	panel._onScreen = false

	makeRoot(panel)
	table.insert(ui._panels, panel)
	return panel
end

local function isInteractive(rect)
	return rect.onClick or rect.onPress or rect.onRelease or rect.onEnter or rect.onLeave
end

-- options.distance: studs between the camera and the interface (default 2)
function InteractiveUI.new(options)
	options = options or {}

	local self = setmetatable({}, InteractiveUI)
	self.distance = options.distance or 2
	self.studsPerUnit = 2 * self.distance * math.tan(math.rad(FIELD_OF_VIEW / 2)) / 100
	self.pointer = { x = 0, y = 0, down = false }
	self.hovered = nil

	self._panels = {}
	self._keys = {}
	self._updates = {}
	self._pressed = nil
	self._mouse = nil
	self._checkPanel = 1
	self._checkChild = 1
	self._settle = 0

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:_press()
		elseif not gameProcessed then
			for _, binding in self._keys do
				if input.KeyCode == binding.key then
					binding.callback()
				end
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:_release()
		end
	end)

	RunService.Heartbeat:Connect(function()
		self:_step()
	end)

	return self
end

-- props: x, y, layer, visible, name
function InteractiveUI:panel(props)
	return newPanel(self, props or {}, PANEL_SCALE)
end

-- a panel showing a small copy of a model visible from its right side
-- props: x, y, layer, visible, name, size (units), rotation (degrees), color, material
function InteractiveUI:model(model, props)
	props = props or {}

	local handle = model:FindFirstChild("Handle")
	local origin = handle and handle.CFrame or CFrame.new(0, 0, 0)
	local view = CFrame.Angles(0, 0, math.rad(props.rotation or 0)) * CFrame.Angles(0, -math.pi / 2, 0)

	local pieces = {}
	local low = { math.huge, math.huge, math.huge }
	local high = { -math.huge, -math.huge, -math.huge }
	for _, part in model:GetChildren() do
		if part.Name ~= "Handle" and part:IsA("BasePart") then
			local placed = view * origin:ToObjectSpace(part.CFrame)
			local size = part.Size
			local across = placed:VectorToWorldSpace(Vector3.new(size.X / 2, 0, 0))
			local up = placed:VectorToWorldSpace(Vector3.new(0, size.Y / 2, 0))
			local out = placed:VectorToWorldSpace(Vector3.new(0, 0, size.Z / 2))
			local middle = placed.Position
			local reach = {
				math.abs(across.X) + math.abs(up.X) + math.abs(out.X),
				math.abs(across.Y) + math.abs(up.Y) + math.abs(out.Y),
				math.abs(across.Z) + math.abs(up.Z) + math.abs(out.Z),
			}
			local at = { middle.X, middle.Y, middle.Z }
			for axis = 1, 3 do
				low[axis] = math.min(low[axis], at[axis] - reach[axis])
				high[axis] = math.max(high[axis], at[axis] + reach[axis])
			end
			table.insert(pieces, { part = part, placed = placed, size = size })
		end
	end

	local longest = math.max(high[1] - low[1], high[2] - low[2], 0.01)
	local scale = (props.size or 5) * self.studsPerUnit / longest

	-- the root can't go below the smallest part size past that the parts shrink too
	local rootScale = math.max(scale, SMALLEST_PART)
	local shrink = scale / rootScale

	local panel = newPanel(self, {
		name = props.name or model.Name,
		x = props.x,
		y = props.y,
		layer = props.layer,
		visible = props.visible,
	}, rootScale)

	for _, piece in pieces do
		local at = piece.placed.Position
		local turn = CFrame.new(-at.X, -at.Y, -at.Z) * piece.placed
		local child = {
			source = piece.part,
			color = props.color,
			material = props.material,
			cframe = CFrame.new(
				(at.X - (low[1] + high[1]) / 2) * shrink,
				(at.Y - (low[2] + high[2]) / 2) * shrink,
				(at.Z - (low[3] + high[3]) / 2) * shrink
			) * turn,
		}
		if shrink < 1 then
			child.size = Vector3.new(piece.size.X * shrink, piece.size.Y * shrink, piece.size.Z * shrink)
		end
		makeChild(panel, child)
		table.insert(panel._children, child)
	end

	return panel
end

function InteractiveUI:onKey(key, callback)
	table.insert(self._keys, { key = key, callback = callback })
end

-- callback runs every frame
function InteractiveUI:onUpdate(callback)
	table.insert(self._updates, callback)
end

function InteractiveUI:rectAt(x, y)
	local top, topLayer = nil, 0
	for _, panel in self._panels do
		if panel.visible then
			for _, rect in panel._rects do
				local layer = panel.layer + rect.layer
				if (not top or layer >= topLayer) and isInteractive(rect) and rect:contains(x, y) then
					top, topLayer = rect, layer
				end
			end
		end
	end
	return top
end

function InteractiveUI:_readPointer()
	local mouse = self._mouse
	if not mouse then
		local player = Players.LocalPlayer
		if not player then
			return
		end
		mouse = player:GetMouse()
		self._mouse = mouse
	end

	local x, y = mouse.X, mouse.Y
	local viewWidth, viewHeight = mouse.ViewSizeX, mouse.ViewSizeY
	if x and y and viewWidth and viewHeight and viewHeight > 0 then
		local unitsPerPixel = 100 / viewHeight
		self.pointer.x = (x - viewWidth / 2) * unitsPerPixel
		self.pointer.y = (viewHeight / 2 - y) * unitsPerPixel
	end
end

-- looks at a few parts each frame and rebuilds a panel if one of them has moved
function InteractiveUI:_check()
	for _ = 1, CHECKS_PER_FRAME do
		local panel = self._panels[self._checkPanel]
		if not panel then
			self._checkPanel = 1
			self._checkChild = 1
			break
		end

		local child = panel._children[self._checkChild]
		if not child or panel._rest > 0 then
			self._checkPanel += 1
			self._checkChild = 1
		else
			self._checkChild += 1
			if hasMoved(child) then
				panel:_rebuild()
				self._settle = SETTLE
			end
		end
	end

	-- panels made while parts were still moving can be a little off themselves
	-- so once it has been quiet for a while all of them are made again
	if self._settle > 0 then
		self._settle -= 1
		if self._settle == 0 then
			for _, panel in self._panels do
				panel:_rebuild()
			end
		end
	end
end

function InteractiveUI:_step()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	self:_readPointer()

	local over = self:rectAt(self.pointer.x, self.pointer.y)
	if over ~= self.hovered then
		local previous = self.hovered
		self.hovered = over
		if previous and previous.onLeave then
			previous.onLeave(previous)
		end
		if over and over.onEnter then
			over.onEnter(over)
		end
	end

	for _, callback in self._updates do
		callback()
	end

	self:_check()

	-- only the roots move the rects follow as their children
	local cameraCFrame = camera.CFrame
	for _, panel in self._panels do
		panel._onScreen = true
		if panel._rest > 0 then
			panel._rest -= 1
		end
		if panel._fresh then
			panel._fresh = false
		elseif panel.visible then
			-- closer layers look bigger so pull them toward the middle to match
			local depth = self.distance - panel.layer * LAYER_GAP
			local scale = self.studsPerUnit * depth / self.distance
			panel._root.CFrame = cameraCFrame * CFrame.new(panel.x * scale, panel.y * scale, -depth)
		else
			panel._root.CFrame = cameraCFrame * BEHIND_CAMERA
		end
	end
end

function InteractiveUI:_press()
	self.pointer.down = true
	local rect = self.hovered
	self._pressed = rect
	if rect and rect.onPress then
		rect.onPress(rect)
	end
end

function InteractiveUI:_release()
	self.pointer.down = false
	local rect = self._pressed
	self._pressed = nil
	if not rect then
		return
	end
	local over = self.hovered
	if rect.onRelease then
		rect.onRelease(rect, over)
	end
	if over == rect and rect.onClick then
		rect.onClick(rect)
	end
end

-- props: x, y, width, height, color, transparency, layer, rotation, name
function Panel:rect(props)
	if self._onScreen then
		error("add rects to a panel right after creating it", 2)
	end

	local rect = setmetatable({}, Rect)
	rect.panel = self
	rect.x = props.x or 0
	rect.y = props.y or 0
	rect.width = props.width or 10
	rect.height = props.height or 10
	rect.layer = props.layer or 0
	rect.name = props.name or "Rect"
	rect.color = props.color or Color3.fromRGB(255, 255, 255)
	rect.transparency = props.transparency

	local scale = self.ui.studsPerUnit / self._scale
	rect.size = Vector3.new(rect.width * scale, rect.height * scale, RECT_DEPTH)
	rect.cframe = CFrame.new(rect.x * scale, rect.y * scale, rect.layer * LAYER_GAP / self._scale)
		* CFrame.Angles(0, 0, math.rad(props.rotation or 0))

	makeChild(self, rect)
	table.insert(self._rects, rect)
	table.insert(self._children, rect)
	return rect
end

-- Falling off the map makes Vortex shift child parts out of place
-- They can't be put back, so the panel gets a new root with new parts
function Panel:_rebuild()
	local old = self._root
	makeRoot(self)
	for _, child in self._children do
		makeChild(self, child)
	end
	old.CFrame = FAR_AWAY
	task.delay(0.2, function()
		old:Destroy()
	end)
end

function Panel:moveTo(x, y)
	self.x = x
	self.y = y
end

function Panel:setLayer(layer)
	self.layer = layer
end

function Panel:setVisible(visible)
	self.visible = visible
end

function Rect:setColor(color)
	self.color = color
	self.part.Color = color
end

-- rotation is ignored here
function Rect:contains(x, y)
	local panel = self.panel
	return math.abs(x - panel.x - self.x) <= self.width / 2 and math.abs(y - panel.y - self.y) <= self.height / 2
end

return InteractiveUI
