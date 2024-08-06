The built-in function help you improve the resizing behavior of neovim.

This is just a sudden thought, so there may be many functions that are not reasonable. Please give me your feedback.

## Installation

```lua

    --lazy
    {
        lazy = true,
        "sontungexpt/smart-resizing.nvim",
    }

```

## Features

### 🖼️ **Smart Window Resizing:**

- **Calculate the area with a lot of empty space compared to the total window and resize based on that.**

  - Compared with the middle position of vim and choose the side with the most empty space to maximize and least empty space to minimize.

  - If the height cannot be resized further, the window will glide to the bottommost or rightmost position.

### 🚀 **Speed Up When Holding:**

- **Hold the Keybinding:**
  - When you hold the keybinding, the window will resize faster, allowing you to quickly adjust the window size.

✨ **Elevate your productivity with effortless window management!** Experience a more organized and efficient workspace with just a few keystrokes. 🚀

## What's Bad?

When there are more than 3 windows in a direction, the resizing behavior can feel uncomfortable. (It's not very bad, but for me, it sometimes feels uncomfortable, and I still haven't found a better behavior to solve this).

But I think it's find than the default behavior of neovim since there never seems to be more than 3 windows in a direction.

## Preiview

https://github.com/user-attachments/assets/0c87fc05-2415-4470-823e-f88b15e68465

https://github.com/user-attachments/assets/3a958a6b-59c6-433b-9585-0afe02ed49b6

https://github.com/user-attachments/assets/a0d5861c-930f-4ee9-b558-feaa786bed81

## Usage

Because this plugin is just contain a builtin function, you need to map it to a keybinding.
like this:

```lua
    -- recommended to use this function since it has a speed up behavior when you hold the keybinding
    -- You should map the keybinding with the modifier key + h/j/k/l

    vim.keymap.set("n", "<A-h>", function() require("smart-resizing").adjust_current_win_width(1, 1) end)
    vim.keymap.set("n", "<A-l>", function() require("smart-resizing").adjust_current_win_width(1, 2) end)
    vim.keymap.set("n", "<A-j>", function() require("smart-resizing").adjust_current_win_height(1, 1) end)
    vim.keymap.set("n", "<A-k>", function() require("smart-resizing").adjust_current_win_height(1, 2) end)
```

## Built-in function

### Action:

- 1: decrease
- 2: increase

You can access this enum by `require("smart-resizing").Action`

### Dimension:

- 1: height
- 2: width

You can access this enum by `require("smart-resizing").Dimension`

### Functions:

- `adjust_current_win_width(step, action)`: adjust the width of the current window (speed up behavior when you hold the keybinding)

  - `adjust_current_win_width(1, 1)`: decrease the width of the current window by 1
  - `adjust_current_win_width(1, 2)`: increase the width of the current window by 1

- `adjust_current_win_height(step, action)`: adjust the height of the current window (speed up behavior when you hold the keybinding)

  - `adjust_current_win_height(1, 1)`: decrease the height of the current window by 1
  - `adjust_current_win_height(1, 2)`: increase the height of the current window by 1

- `increase_current_win_size(step, dimension)`: increase the size of the current window

  - `increase_current_win_size(1, 1)`: increase the height of the current window by 1
  - `increase_current_win_size(1, 2)`: increase the width of the current window by 1

- `decrease_current_win_size(step, dimension)`: decrease the size of the current window

  - `decrease_current_win_size(1, 1)`: decrease the height of the current window by 1
  - `decrease_current_win_size(1, 2)`: decrease the width of the current window by 1

- `increase_current_win_width(step)`: increase the width of the current window by 1

- `decrease_current_win_width(step)`: decrease the width of the current window by 1

- `increase_current_win_height(step)`: increase the height of the current window by 1

- `decrease_current_win_height(step)`: decrease the height of the current window by 1

## License

[MIT](./LICENSE)
