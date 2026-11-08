# smart-resizing.nvim

A lightweight Neovim plugin that provides intelligent window resizing with center-aware space distribution, edge-aware behavior, and configurable hold-to-accelerate support.

Unlike Neovim's default window resizing, `smart-resizing.nvim` considers the current window's position relative to the editor center and distributes space between neighboring windows to provide a more balanced and predictable resizing experience.

## Features

### Smart Window Resizing

- **Center-aware resizing:** Uses the editor center as a reference when deciding how to distribute space.
- **Edge-aware behavior:** Automatically adjusts resizing direction when the current window is at an edge.
- **Neighbor space distribution:** Borrows space from neighboring windows when necessary instead of blindly resizing the current window.
- **Minimum size awareness:** Respects `winminwidth` and `winminheight` when distributing space.
- **Floating window support:** Supports resizing floating windows without applying tiled-window balancing logic.
- **Width and height support:** Provides independent resizing operations for both dimensions.
- **Vim count support:** Supports built-in counts, such as `5` followed by your resize mapping.

### Hold-to-Accelerate

Provides optional progressive acceleration when holding a resize key.

- **Continuous hold detection:** Consecutive key repeats are treated as one continuous hold within a configurable timeout.
- **Configurable threshold:** Determines how long a key must be held before acceleration begins.
- **Smooth acceleration:** Uses a quadratic ease-in curve to progressively increase the resizing step.
- **Configurable maximum speed:** Controls the maximum resizing speed relative to the base step.
- **Fractional step accumulation:** Carries fractional movement between repetitions to make acceleration smoother.
- **Predictable counts:** Explicit Vim counts bypass acceleration and always perform the requested number of repetitions.

Acceleration is enabled by default.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "sontungexpt/smart-resizing.nvim",
    lazy = true,
    opts = {
        step = 1,
        accelerate = {
            enabled = true,
            threshold_ms = 120,
            ramp_ms = 1500,
            max_multiplier = 6,
        },
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

    -- Hold-to-accelerate configuration.
    accelerate = {
        enabled = true,
        threshold_ms = 120,
        ramp_ms = 1500,
        max_multiplier = 6,
    },
})
```

### Configuration options

| Option | Type | Default | Description |
|---|---|---:|---|
| `step` | integer | `1` | Default number of cells per resize repetition. |
| `accelerate` | boolean or table | `true` | Enables or configures hold-to-accelerate behavior. |
| `accelerate.enabled` | boolean | `true` | Enables or disables acceleration. |
| `accelerate.threshold_ms` | integer | `120` | Holding duration required before acceleration starts. |
| `accelerate.ramp_ms` | integer | `1500` | Duration required to reach maximum acceleration after the threshold. |
| `accelerate.max_multiplier` | number | `6` | Maximum resizing speed relative to the base step. |

### Acceleration tuning

The acceleration behavior can be customized depending on your preferred resizing feel.

| Parameter | Increase | Decrease |
|---|---|---|
| `threshold_ms` | Acceleration starts later. | Acceleration starts sooner. |
| `ramp_ms` | Slower, smoother acceleration. | Faster acceleration. |
| `max_multiplier` | Higher maximum speed. | Lower maximum speed. |

#### Faster, more aggressive

```lua
require("smart-resizing").setup({
    accelerate = {
        threshold_ms = 50,
        ramp_ms = 700,
        max_multiplier = 10,
    },
})
```

#### Slower, more precise

```lua
require("smart-resizing").setup({
    accelerate = {
        threshold_ms = 400,
        ramp_ms = 2000,
        max_multiplier = 3,
    },
})
```

#### Disable acceleration

Using the boolean shorthand:

```lua
require("smart-resizing").setup({
    accelerate = false,
})
```

Or using the configuration table:

```lua
require("smart-resizing").setup({
    accelerate = {
        enabled = false,
    },
})
```

Setting `max_multiplier = 1` also effectively disables progressive acceleration.

### Internal hold detection

The plugin uses an internal constant to determine whether consecutive key repeats belong to the same hold operation.

| Constant | Default | Description |
|---|---:|---|
| `HOLD_TIMEOUT_MS` | `100` ms | Maximum interval between consecutive key repeats before a new hold is detected. |

This is currently an internal implementation detail rather than a public configuration option.

If acceleration frequently resets while holding a key, your terminal or operating system may have a relatively slow key-repeat rate. In that case, consider increasing `HOLD_TIMEOUT_MS`.

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

The plugin supports Vim's built-in count:

```lua
-- Press 5 followed by your resize mapping
-- to perform 5 resizing repetitions.
vim.keymap.set("n", "<A-l>", function()
    require("smart-resizing").increase("width")
end)
```

When a count is provided, acceleration is skipped to ensure predictable results.

For example, `5<A-l>` performs exactly five resizing repetitions using the configured base step.

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
    accelerate = {
        enabled = true,
        threshold_ms = 120,
        ramp_ms = 1500,
        max_multiplier = 6,
    },
})
```

Supports both boolean and table-based acceleration configuration:

```lua
-- Enable acceleration.
require("smart-resizing").setup({
    accelerate = true,
})

-- Disable acceleration.
require("smart-resizing").setup({
    accelerate = false,
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

## How Acceleration Works

The plugin calculates resizing speed based on how long the key has been continuously held.

After the configured threshold, acceleration follows a quadratic ease-in curve:

\[
speed(t) = 1 + (M - 1)t^2
\]

Where:

- `M` is the configured `max_multiplier`.
- `t` is the normalized acceleration progress, clamped between `0` and `1`.

The normalized progress is calculated as:

\[
t = \frac{elapsed - threshold}{ramp}
\]

The resulting speed gradually increases from the base step to the maximum multiplier.

Fractional movement is accumulated between repetitions, allowing the resizing step to increase progressively without unnecessarily discarding fractional values.

When the key is released or the interval between repeats exceeds `HOLD_TIMEOUT_MS`, the next operation starts a new acceleration cycle.

## Limitations

- Resizing behavior can be less predictable in complex layouts with many neighboring windows.
- When neighboring windows cannot provide enough space, the algorithm may fall back to resizing the current window directly.
- Acceleration depends on repeated key events, so its behavior is influenced by terminal and operating system key-repeat settings.
- Floating windows use a simpler resizing strategy and do not participate in tiled-window space distribution.
- Vim counts intentionally bypass acceleration.

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
