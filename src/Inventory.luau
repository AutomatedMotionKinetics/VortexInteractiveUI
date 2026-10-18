-- built on Interactive UI
-- Items are tables like { id = 1, name = "Knife", model = <Model> }

local SLOTS = 9
local ROWS = 3
local CELL = 7
local STEP = 8 -- from the middle of one cell to the next
local HOTBAR_Y = -44.5

local ICON_SIZE = 5.4
local ICON_TILT = 30
local ICON_MATERIAL = Enum.Material.Metal

local LAYER = { item = 10, selection = 14, dragged = 24 }
local BACK = 5 -- an item's dark square sits that many layers behind its picture

local COLORS = {
	slot = Color3.fromRGB(31, 31, 31),
	hover = Color3.fromRGB(160, 160, 160),
	window = Color3.fromRGB(20, 20, 20),
	itemBack = Color3.fromRGB(52, 52, 52),
	selected = Color3.fromRGB(90, 142, 233),
	icon = Color3.fromRGB(255, 255, 255),
}
local SEE_THROUGH = 0.5

local NUMBER_KEYS = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
	Enum.KeyCode.Six,
	Enum.KeyCode.Seven,
	Enum.KeyCode.Eight,
	Enum.KeyCode.Nine,
}

local Inventory = {}
Inventory.__index = Inventory

function Inventory.new(ui)
	local self = setmetatable({}, Inventory)
	self.ui = ui
	self.slots = {}
	self.cells = {}
	self.selected = nil -- index of the selected slot
	self.equipped = nil -- the item in it
	self.isOpen = false
	self.onEquip = nil -- function(item) item is nil when nothing is equipped afterwards
	self._dragging = nil

	local columns = SLOTS + 1 -- the inventory button takes the last slot
	local firstX = -STEP * (columns - 1) / 2

	local hotbar = ui:panel({ name = "Hotbar", y = HOTBAR_Y })
	for index = 1, SLOTS do
		local cell = self:_cell(hotbar, firstX + (index - 1) * STEP, 0, 0)
		cell.slot = index
		cell.rect.onClick = function()
			self:select(index)
		end
		self.slots[index] = cell
	end

	-- inventory button with a 3 x 3 dots on it
	local buttonX = firstX + SLOTS * STEP
	local button = hotbar:rect({
		x = buttonX,
		width = CELL,
		height = CELL,
		color = COLORS.slot,
		transparency = SEE_THROUGH,
	})
	for row = -1, 1 do
		for column = -1, 1 do
			hotbar:rect({
				x = buttonX + column * 1.6,
				y = row * 1.6,
				width = 1,
				height = 1,
				color = COLORS.icon,
				layer = 1,
			})
		end
	end
	button.onEnter = function()
		button:setColor(COLORS.hover)
	end
	button.onLeave = function()
		button:setColor(COLORS.slot)
	end
	button.onClick = function()
		self:setOpen(not self.isOpen)
	end

	-- inv is right above the hotbar and is as wide as it
	local height = ROWS * STEP + 1
	local window = ui:panel({
		name = "Inventory",
		y = HOTBAR_Y + CELL / 2 + 1 + height / 2,
		visible = false,
	})
	window:rect({
		width = columns * STEP + 1,
		height = height,
		color = COLORS.window,
		transparency = SEE_THROUGH,
	})
	for row = 1, ROWS do
		for column = 1, columns do
			local x = firstX + (column - 1) * STEP
			local y = height / 2 - 1 - CELL / 2 - (row - 1) * STEP
			table.insert(self.cells, self:_cell(window, x, y, 1))
		end
	end
	self._window = window

	-- frame around the selected slot
	local selection = ui:panel({ name = "Selection", layer = LAYER.selection, visible = false })
	local edge = 0.45
	local reach = CELL / 2 - edge / 2
	selection:rect({ y = reach, width = CELL, height = edge, color = COLORS.selected })
	selection:rect({ y = -reach, width = CELL, height = edge, color = COLORS.selected })
	selection:rect({ x = -reach, width = edge, height = CELL - 2 * edge, color = COLORS.selected })
	selection:rect({ x = reach, width = edge, height = CELL - 2 * edge, color = COLORS.selected })
	self._selection = selection

	ui:onUpdate(function()
		local drag = self._dragging
		if drag then
			self:_draw(drag.entry, ui.pointer.x + drag.offsetX, ui.pointer.y + drag.offsetY, LAYER.dragged)
		end
	end)

	for index, key in NUMBER_KEYS do
		ui:onKey(key, function()
			self:select(index)
		end)
	end
	ui:onKey(Enum.KeyCode.Zero, function()
		self:setOpen(not self.isOpen)
	end)

	return self
end

-- puts the item in the first free cell of the inv returns false if it is full
function Inventory:add(item)
	local free = nil
	for _, cell in self.cells do
		if not cell.entry then
			free = cell
			break
		end
	end
	if not free then
		return false
	end

	local entry = {
		item = item,
		icon = self.ui:model(item.model, {
			size = ICON_SIZE,
			rotation = ICON_TILT,
			color = COLORS.icon,
			material = ICON_MATERIAL,
		}),
		back = self.ui:panel({ name = "ItemBack" }),
	}
	entry.back:rect({ width = CELL, height = CELL, color = COLORS.itemBack })
	self:_place(entry, free)
	return true
end

-- selecting the selected slot again deselects it
function Inventory:select(index)
	if self.selected == index then
		self.selected = nil
	else
		self.selected = index
	end

	if self.selected then
		local cell = self.slots[self.selected]
		self._selection:moveTo(cell.x, cell.y)
	end
	self._selection:setVisible(self.selected ~= nil)
	self:_refresh()
end

function Inventory:setOpen(open)
	self.isOpen = open
	self._window:setVisible(open)
	for _, cell in self.cells do
		local entry = cell.entry
		if entry and not (self._dragging and self._dragging.entry == entry) then
			self:_show(entry, open)
		end
	end
end

function Inventory:_cell(panel, x, y, layer)
	local cell = { x = panel.x + x, y = panel.y + y, entry = nil }
	cell.rect = panel:rect({
		x = x,
		y = y,
		width = CELL,
		height = CELL,
		color = COLORS.slot,
		transparency = SEE_THROUGH,
		layer = layer,
	})
	cell.rect.cell = cell

	cell.rect.onEnter = function(rect)
		rect:setColor(COLORS.hover)
	end
	cell.rect.onLeave = function(rect)
		rect:setColor(COLORS.slot)
	end
	cell.rect.onPress = function()
		if cell.entry then
			-- this keeps the spot where the item was grabbed under the mouse
			self._dragging = {
				entry = cell.entry,
				from = cell,
				offsetX = cell.x - self.ui.pointer.x,
				offsetY = cell.y - self.ui.pointer.y,
			}
		end
	end
	cell.rect.onRelease = function(_, over)
		self:_drop(over and over.cell)
	end

	return cell
end

function Inventory:_draw(entry, x, y, layer)
	entry.back:moveTo(x, y)
	entry.back:setLayer(layer - BACK)
	entry.icon:moveTo(x, y)
	entry.icon:setLayer(layer)
end

function Inventory:_show(entry, visible)
	entry.back:setVisible(visible)
	entry.icon:setVisible(visible)
end

function Inventory:_place(entry, cell)
	entry.cell = cell
	cell.entry = entry
	self:_draw(entry, cell.x, cell.y, LAYER.item)
	self:_show(entry, cell.slot ~= nil or self.isOpen)
end

-- a full cell swaps with the dragged item and put anywhere else the item goes back
function Inventory:_drop(target)
	local drag = self._dragging
	if not drag then
		return
	end
	self._dragging = nil

	if target and target ~= drag.from then
		local other = target.entry
		drag.from.entry = nil
		self:_place(drag.entry, target)
		if other then
			self:_place(other, drag.from)
		end
	else
		self:_place(drag.entry, drag.from)
	end
	self:_refresh()
end

function Inventory:_refresh()
	local entry = self.selected and self.slots[self.selected].entry
	local item = entry and entry.item or nil
	if item ~= self.equipped then
		self.equipped = item
		if self.onEquip then
			self.onEquip(item)
		end
	end
end

return Inventory
