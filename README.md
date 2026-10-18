# Vortex Interactive UI

A clickable UI for [Vortex](https://playvortex.io) games, built out of Parts. Panels and buttons sit in front of the camera and react to the mouse: hover, click and drag. It comes with a ready-made hotbar and inventory, where items are ordinary models: they show up in the slots as small copies of themselves, and the equipped one goes to the avatar's right hand.

[![Watch the video](https://img.youtube.com/vi/FFm2kSrUJew/maxresdefault.jpg)](https://youtu.be/FFm2kSrUJew)

The [video](https://youtu.be/FFm2kSrUJew) shows the hotbar and inventory, how to add your own item and how to build your own interface with it.

> Unofficial community project, not affiliated with or endorsed by Vortex.

## Why

* Vortex doesn't have ScreenGui yet, so the interface is drawn with Parts in front of the camera.
* Studio 0.7.0 added mouse input, and that's what makes hovering, clicking and drag and drop possible.
* It's made to be taken apart: a UI module, an inventory built on top of it, a list of items and a short example script.

## Try it

1. Download [`VortexInteractiveUI.vrtx`](VortexInteractiveUI.vrtx).
2. In Vortex Studio pick **Import a .vrtx file**, then press Play.

| Do this | and this happens |
| --- | --- |
| click the button next to slot 9, or press `0` | the inventory opens or closes |
| drag an item | it moves to the slot or cell you drop it on. A full cell swaps with it |
| click a slot, or press `1` to `9` | the slot is selected and its item goes to your right hand. Do it again to put it back |

## Add your own item

1. Build your model, group it and put the group inside the `Items` group in Workspace. It lies there as a prop until somebody equips it.
2. Add a part named `Handle` to it, where the hand should hold it. The front of the Handle is where the item points and its top is the item's top, the same as with Roblox tools.
3. Give it an id in the `Items` module:

```lua
return {
    { id = 1, name = "Knife", model = "Knife" },
    { id = 2, name = "Pistol", model = "Pistol" },
    { id = 6, name = "Axe", model = "Axe" }, -- your model's name in workspace.Items
}
```

That's all. The picture in the slot is a small copy of the model itself, painted in one color.

## The files

| File | Goes in | What it is |
| --- | --- | --- |
| [`InteractiveUI.luau`](src/InteractiveUI.luau) | ReplicatedStorage, ModuleScript | panels, rects and mouse events |
| [`Inventory.luau`](src/Inventory.luau) | ReplicatedStorage, ModuleScript | the hotbar and the inventory window |
| [`Items.luau`](src/Items.luau) | ReplicatedStorage, ModuleScript | the list of items and their ids |
| [`Example.client.luau`](src/Example.client.luau) | StarterPlayerScripts, LocalScript | hands out the items and holds the equipped one |

## The inventory in your own script

```lua
local ui = InteractiveUI.new()
local inventory = Inventory.new(ui)

inventory:add({ id = 1, name = "Knife", model = workspace.Items.Knife })

inventory.onEquip = function(item)
    -- item is nil when nothing is equipped
    print(item and item.id)
end
```

| | |
| --- | --- |
| `inventory:add(item)` | puts the item in the first free cell. Returns `false` when the inventory is full |
| `inventory:select(index)` | selects a hotbar slot, or deselects it if it was selected |
| `inventory:setOpen(open)` | opens or closes the window |
| `inventory.equipped` | the item in the selected slot, or `nil` |
| `inventory.onEquip` | called with the item whenever that changes |

Sizes, colors, the number of slots and the look of the item pictures are at the top of `Inventory.luau`.

## The UI module on its own

Positions and sizes are in screen units. The screen is always 100 units tall, `(0, 0)` is its middle, `x` grows to the right and `y` grows upward.

```lua
local ui = InteractiveUI.new()

local panel = ui:panel({ x = 0, y = -30 })
local button = panel:rect({ width = 14, height = 6, color = Color3.fromRGB(70, 130, 220) })

button.onClick = function()
    print("clicked")
end
```

A panel is a group of rects that is built once and then moves, hides and shows as one. Add its rects right after creating it; after that they can change color, but they can't move and no more can be added. Anything that moves on its own, like a dragged item, gets a panel of its own.

| | |
| --- | --- |
| `ui:panel({ x, y, layer, visible })` | a new panel. Higher layers are drawn on top |
| `ui:model(model, { x, y, layer, size, rotation, color, material })` | a panel showing a small copy of a model, seen from its right side. `color` and `material` paint every part of the copy alike |
| `panel:rect({ x, y, width, height, color, transparency, layer, rotation })` | a rect, measured from the middle of the panel |
| `panel:moveTo(x, y)`, `panel:setLayer(layer)`, `panel:setVisible(visible)` | |
| `rect:setColor(color)` | |
| `ui:onKey(keyCode, callback)` | runs when the key is pressed, unless the player is typing in chat |
| `ui:onUpdate(callback)` | runs every frame |
| `ui.pointer.x`, `ui.pointer.y` | where the mouse is, in screen units |
| `ui.hovered` | the rect under the mouse |

Give a rect any of these functions and it starts reacting to the mouse:

| Function | Called when |
| --- | --- |
| `onClick(rect)` | the left button was pressed and released on the rect |
| `onPress(rect)` | the left button went down on it |
| `onRelease(rect, over)` | the button came back up. `over` is the rect under the mouse at that moment, or `nil` |
| `onEnter(rect)`, `onLeave(rect)` | the mouse moved onto or off the rect |

## How it works

Every rect is a thin Part. The rects of a panel are children of one invisible root Part, and each frame only the roots are moved in front of the camera, so the interface stays put on screen while the camera turns.

The roots are scaled down to a tenth, and child Parts are scaled along with them. That gets around the 0.05 stud minimum part size, which would otherwise make small details impossible this close to the camera. An item's picture is its model's parts cloned under a root that is scaled down further.

The mouse position is read in pixels and turned into screen units. Finding what is under the mouse is then just comparing numbers, without any raycasts.

Vortex nudges child Parts a tiny bit whenever their parent moves, and the interface moves with the camera all the time. In a detailed model that is enough for one part to show through another, which is why the inventory paints an item's picture in a single color and material: parts that swap places then look the same. A long fall shifts the parts far enough to see, so the module looks at a few parts every frame and builds a panel again when one of them has wandered off.

## Good to know

* Needs Vortex Studio 0.7.0 or newer. Tested on 0.7.2.
* The interface is drawn 2 studs in front of the camera. Anything closer than that, like a wall the camera is pushed against, covers it. `InteractiveUI.new({ distance = 1 })` moves it closer.
* Rects are ordinary Parts, so the lighting of your game changes how bright they look.
* There is no text.
* A rect is placed once. Moving a child Part a second time makes Vortex put it somewhere else, which is why moving things are panels.
* After falling off the map the interface can look crooked for a moment. It straightens itself a second or two after the respawn.
* Scripts can't reach the avatar's own parts, so the hand is found through the `Right Arm Hitbox`, which moves with the animations.
* The equipped item is moved by the LocalScript, so only that player sees it in the hand.

## License

[MIT](LICENSE). Vortex and Vortex Studio are proprietary software owned by their developers.

Showcased item models are made by x86.
