# smart-resizing.nvim

A lightweight Neovim plugin that provides smarter window resizing with center-aware space distribution and optional hold-to-accelerate behavior.

Instead of relying entirely on Neovim's default window resizing, `smart-resizing.nvim` considers the current window's position and its neighboring windows to make resizing feel more balanced and predictable.

## Features

### Smart Window Resizing

- **Center-aware resizing:** Uses the center of the editor as a reference when deciding how to resize the current window.
- **Edge-aware behavior:** Adjusts resizing direction when the current window is at an edge.
- **Neighbor space distribution:** When necessary, borrows space from neighboring windows instead of blindly resizing the current window.
- **Minimum size awareness:** Respects `winminwidth` and `winminheight` when distributing space between windows.
- **Floating window support:** Supports resizing floating windows without applying the normal tiled-window balancing logic.
- **Count support:** Supports Vim counts, such as `5` followed by your resize mapping.

### Hold-to-Accelerate

Optionally increases the resizing step when a key is held down.

- Repeated key presses within a configurable detection interval are treated as one continuous hold.
- Acceleration starts after the hold threshold.
- The resizing step increases progressively while the key continues to be repeated.

This is disabled by default.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "sontungexpt/smart-resizing.nvim",
    lazy = true,
    opts = {
        step = 1,
        accelerate = true,
    },
}
```

The plugin exposes functions that can be loaded directly from keymaps, so it does not need to load during startup.

## Configuration

All options are optional.

```lua
require("smart-resizing").setup({
    -- Default number of cells per resize operation.
    step = 1,

    -- Enable hold-to-accelerate behavior.
    accelerate = false,
})
```

| Option | Type | Default | Description |
|---|---|---|---|
| `step` | integer | `1` | Default number of cells per resize operation. |
| `accelerate` | boolean | `false` | Enable progressive acceleration when holding a resize key. |

### Acceleration behavior

The current implementation uses these internal constants:

| Constant | Value | Description |
|---|---:|---|
| `HOLD_TIMEOUT_MS` | `180` ms | Maximum interval between repeated presses to consider a key held. |
| `HOLD_THRESHOLD_MS` | `600` ms | Time before acceleration starts. |
| `HOLD_FACTOR` | `2` | Base added to the accelerated step. |

These are currently internal implementation details rather than public configuration options.

## Usage

The plugin only provides resizing functions. You can bind them to your preferred key combinations.

### Recommended keymaps

```lua
local resize = require("smart-resizing")

-- Width
vim.keymap.set("n", "<A-h>", function()
    resize.decrease("width")
end, { desc = "Decrease window width" })

vim.keymap.set("n", "<A-l>", function()
    resize.increase("width")
end, { desc = "Increase window width" })

-- Height
vim.keymap.set("n", "<A-k>", function()
    resize.decrease("height")
end, { desc = "Decrease window height" })

vim.keymap.set("n", "<A-j>", function()
    resize.increase("height")
end, { desc = "Increase window height" })
```

### Custom step

You can override the default step for individual operations:

```lua
local resize = require("smart-resizing")

-- Resize by 3 cells.
resize.increase("width", 3)
resize.decrease("height", 3)
```

### Vim counts

The plugin also supports Vim's built-in count:

```lua
-- Press 5 followed by your resize mapping to repeat
-- the resizing operation five times.
vim.keymap.set("n", "<A-l>", function()
    require("smart-resizing").increase("width")
end)
```

You can also pass the repetition count explicitly:

```lua
-- Increase width by 1 cell, repeated 5 times.
require("smart-resizing").increase("width", 1, 5)
```

## API

### `setup(opts?)`

Configure the plugin.

```lua
require("smart-resizing").setup({
    step = 1,
    accelerate = true,
})
```

### `increase(dim, step?, count?)`

Increase the size of the current window.

| Parameter | Type | Description |
|---|---|---|
| `dim` | `"width"` or `"height"` | Dimension to resize. |
| `step` | integer? | Number of cells per repetition. Defaults to `config.step`. |
| `count` | integer? | Number of repetitions. Defaults to `vim.v.count1`. |

Examples:

```lua
-- Increase width by 1.
resize.increase("width")

-- Increase height by 2.
resize.increase("height", 2)

-- Increase width by 1, repeated 5 times.
resize.increase("width", 1, 5)
```

### `decrease(dim, step?, count?)`

Decrease the size of the current window.

It accepts the same parameters as `increase()`.

```lua
-- Decrease width by 1.
resize.decrease("width")

-- Decrease height by 2.
resize.decrease("height", 2)

-- Decrease width by 1, repeated 5 times.
resize.decrease("width", 1, 5)
```

## Limitations

- Resizing behavior can feel less predictable in layouts with many windows along the same direction.
- When neighboring windows cannot provide enough space, the operation may fall back to resizing the current window directly.
- Acceleration depends on repeated key events. Its behavior therefore depends partly on the terminal's key-repeat settings.
- Floating windows use a simpler resizing strategy and do not participate in tiled-window space distribution.

The resizing algorithm is intentionally kept lightweight. Feedback and suggestions for improving its behavior are welcome.

## Preview

### Preview 1

https://github.com/user-attachments/assets/0c87fc05-2415-4470-823e-f88b15e68465

### Preview 2

https://github.com/user-attachments/assets/3a958a6b-59c6-433b-9585-0afe02ed49b6

### Preview 3

https://github.com/user-attachments/assets/a0d5861c-930f-4ee9-b558-feaa786bed81

## License

[MIT](./LICENSE)
