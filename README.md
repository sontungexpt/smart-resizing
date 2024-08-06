The built-in function help you improve the resizing behavior of neovim.

## Installation

```lua

    --lazy
    {
        lazy = true,
        "sontungexpt/smart-resizing.nvim",
    }

```

## Features

🌟 **Enhance Your Window Management with Smart Resizing and Centering!**

## 🖼️ **Smart Window Resizing:**

- **Left Side Window:**
  - Press `Alt + L` to **expand** the width and give your content more room.
- **Right Side Window:**
  - Press `Alt + H` to **shrink** the width and make more space for other windows.
- **Top Side Window:**
  - Press `Alt + J` to **increase** the height and view more of your content.
- **Bottom Side Window:**
  - Press `Alt + K` to **decrease** the height and tidy up your workspace.
- 🔄 **Seamlessly adapts to the opposite sides as well!**

### 📍 **Center Your Focus:**

- **When Managing Multiple Windows:**
  - Use `Alt + H` or `Alt + L` to adjust the width of the current window, centering it perfectly on your screen.
  - If resizing is no longer possible, the window will smoothly slide to the rightmost position.
- **For Height Adjustments:**
  - Use `Alt + J` or `Alt + K` to resize and center the height.
  - If the height cannot be resized further, the window will glide to the bottommost position.

### 🚀 **Speed Up When Holding:**

- **Hold the Keybinding:**
  - When you hold the keybinding, the window will resize faster, allowing you to quickly adjust the window size.

✨ **Elevate your productivity with effortless window management!** Experience a more organized and efficient workspace with just a few keystrokes. 🚀

## Usage

Because this plugin is just contain a builtin function, you need to map it to a keybinding.
like this:

```lua
    -- recommended to use this function since it has a speed up behavior when you hold the keybinding
    -- You should map the keybinding with the modifier key + h/j/k/l

    map("n", "<A-h>", function() require("smart-resizing").adjust_current_win_width(1, 1) end)
    map("n", "<A-l>", function() require("smart-resizing").adjust_current_win_width(1, 2) end)
    map("n", "<A-j>", function() require("smart-resizing").adjust_current_win_height(1, 1) end)
    map("n", "<A-k>", function() require("smart-resizing").adjust_current_win_height(1, 2) end)
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
