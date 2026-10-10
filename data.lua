data:extend({
  {
    type = "selection-tool",
    name = "cssa-scan-area-tool",
    icon = "__base__/graphics/icons/blueprint.png",
    icon_size = 64,
    flags = {"not-stackable", "only-in-cursor"},
    stack_size = 1,
    select = {
      border_color = {r = 0.2, g = 0.85, b = 1.0},
      cursor_box_type = "copy",
      mode = {"any-entity"},
    },
    alt_select = {
      border_color = {r = 0.2, g = 0.85, b = 1.0},
      cursor_box_type = "copy",
      mode = {"any-entity"},
    },
  }
})


data:extend({
  {
    type = "shortcut",
    name = "cssa_open",
    order = "b[blueprints]-z[circuit-self-subtraction-audit]",
    action = "lua",
    toggleable = false,
    icon = "__base__/graphics/icons/constant-combinator.png",
    icon_size = 64,
    small_icon = "__base__/graphics/icons/constant-combinator.png",
    small_icon_size = 64,
  },
})
