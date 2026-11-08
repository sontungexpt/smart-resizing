local uv = vim.uv or vim.loop
local fn, api, o = vim.fn, vim.api, vim.o

local M = {}

---@class AccelerateConfig
---@field enabled boolean Speed up while a key is held down (default: true)
---@field threshold_ms integer Holding longer than this starts the speedup (default: 100)
---@field ramp_ms integer Time to go from normal speed to max speed (default: 1400)
---@field max_multiplier number Max speed as a multiple of `step` (default: 6)

---@class Config
---@field step integer Cells per repetition when `step` is not passed (default: 1)
---@field accelerate AccelerateConfig

--[[
HOW TO TUNE THE FEEL (all values can be overridden in setup({ ... }))

  step
    Base cells moved per key press (and per repeat while a key is held).
    Increase -> every press moves more. Decrease -> finer control.
    Minimum is 1.

  accelerate.enabled
    true  -> speed grows while a key is held down.
    false -> constant speed, always `step` cells per repeat.
    Acceleration is skipped when you use a count (e.g. `5<key>`),
    so a count always moves exactly count * step cells.

  accelerate.threshold_ms   (default 100)
    How long you must hold the key before acceleration starts.
    Increase -> acceleration starts later (safer for short taps).
    Decrease -> acceleration starts sooner (e.g. 50).

  accelerate.ramp_ms        (default 1400)
    How long it takes to go from normal speed to max speed
    after the threshold has passed.
    Increase -> slower, smoother ramp-up (e.g. 2000).
    Decrease -> reaches max speed faster (e.g. 700).

  accelerate.max_multiplier (default 6)
    Top speed as a multiple of `step`. With step = 1, the max is
    6 cells per repeat; with step = 2, it is 12.
    Increase -> faster top speed (e.g. 10). Decrease -> gentler (e.g. 3).
    Set to 1 to effectively disable acceleration.

  HOLD_TIMEOUT_MS (constant below, default 100)
    Max gap between two key repeats to count as "still holding".
    Increase if acceleration keeps resetting (slow OS key-repeat rate).
    Decrease if quick separate taps are mistaken for a hold.

EXAMPLES
  Faster, more aggressive:
    accelerate = { threshold_ms = 50, ramp_ms = 700, max_multiplier = 10 }
  Slower, more precise:
    accelerate = { threshold_ms = 400, ramp_ms = 2000, max_multiplier = 3 }
  No acceleration:
    accelerate = { enabled = false }
--]]
local config = {
	step = 1,
	accelerate = {
		enabled = true,
		threshold_ms = 120,
		ramp_ms = 1500,
		max_multiplier = 6,
	},
}

-- A key counts as "held" while repeats arrive faster than this (ms).
-- Raise it (e.g. 150) if acceleration keeps resetting because your OS
-- key-repeat is slow; lower it if separate quick taps count as a hold.
local HOLD_TIMEOUT_MS = 100

---`before` is the left/up side, `after` is the right/down side.
---`pos` is the index into nvim_win_get_position() ({row, col}).
---`winmin` is the name of the option holding the minimum window size.
local DIMS = {
	width = {
		pos = 2,
		set = api.nvim_win_set_width,
		get = api.nvim_win_get_width,
		winmin = "winminwidth",
		before = "h",
		after = "l",
	},
	height = {
		pos = 1,
		set = api.nvim_win_set_height,
		get = api.nvim_win_get_height,
		winmin = "winminheight",
		before = "k",
		after = "j",
	},
}

local get_position = api.nvim_win_get_position
local win_getid, winnr = fn.win_getid, fn.winnr

---Window id in a direction (e.g. "h", "2l"), relative to the current window
local function winid(direction)
	return win_getid(winnr(direction))
end

---Middle of the usable editor area along a dimension
local function editor_middle(d)
	if d.pos == 2 then
		return o.columns / 2
	end

	local tabline = 0
	if o.showtabline == 2 or (o.showtabline == 1 and #api.nvim_list_tabpages() > 1) then
		tabline = 1
	end
	local statusline = o.laststatus ~= 0 and 1 or 0
	return (o.lines - o.cmdheight - statusline - tabline) / 2
end

---Middle of the window along a dimension
local function window_middle(win, d, size)
	return get_position(win)[d.pos] + size / 2
end

---+1 if the window is on the `before` edge, -1 if on the `after` edge,
---nil if it has neighbours on both sides. +1 moves the separator toward `after`.
local function edge_direction(d)
	local cur = winnr()
	if cur == winnr(d.after) then
		return -1
	elseif cur == winnr(d.before) then
		return 1
	end
end

-- Scratch tables reused between calls to avoid allocating on every repeat
local donor_ids, donor_targets = {}, {}

---One increase of `step` cells (window has neighbours on both sides).
---The center check is re-evaluated on every call, so repeating it keeps
---the result balanced around the middle.
local function increase_once(d, step, current, size, mid, winmin)
	if window_middle(current, d, size) < mid then
		d.set(current, size + step)
		return
	end

	-- Right/bottom half: take space from windows before us (1h, 2h, 3h, ...).
	-- The walk stops as soon as `step` cells are found.
	local remaining, last_donor, last = step, 0, nil
	for idx = 1, 64 do
		if remaining <= 0 then
			break
		end
		local id = winid(idx .. d.before)
		if id == last or id == current then
			break
		end
		local sz = d.get(id)
		local take = sz > winmin and math.min(remaining, sz - winmin) or 0
		donor_ids[idx] = id
		donor_targets[idx] = sz - take
		if take > 0 then
			last_donor = idx
		end
		remaining = remaining - take
		last = id
	end

	if last_donor == 0 then
		d.set(current, size + step)
		return
	end

	-- Apply from the farthest donor towards us so freed space reaches us
	for i = last_donor, 1, -1 do
		d.set(donor_ids[i], donor_targets[i])
	end

	if remaining > 0 then
		d.set(current, d.get(current) + remaining)
	end
end

---One decrease of `step` cells (window has neighbours on both sides).
local function decrease_once(d, step, current, size, mid, winmin)
	if size > winmin and window_middle(current, d, size) >= mid then
		d.set(current, math.max(1, size - step))
		return
	end

	-- Shrink by growing the neighbour before us, if something after us has room
	local last, target = nil, winid(d.after)
	local idx = 1
	while target ~= last and target ~= current do
		if d.get(target) > winmin then
			local push = winid(d.before)
			if push ~= current then
				d.set(push, d.get(push) + step)
			end
			return
		end
		last = target
		idx = idx + 1
		target = winid(idx .. d.after)
	end
end

local hold_start, last_press
local carry = 0 -- fractional cells not yet applied

---Grow `step` smoothly the longer the key is held down.
---Speed follows an ease-in curve (t^2) from 1x to `max_multiplier`x, and the
---fractional part is carried over so the speed ramps without integer jumps.
---@param step integer
---@return integer
local function accelerated(step)
	local acc = config.accelerate
	local now = uv.hrtime() / 1e6

	if not last_press or now - last_press > HOLD_TIMEOUT_MS then
		hold_start = now -- a new hold begins
		carry = 0
	end
	last_press = now

	local t = (now - hold_start - acc.threshold_ms) / acc.ramp_ms
	if t <= 0 then
		return step
	end
	if t > 1 then
		t = 1
	end

	carry = carry + step * (1 + (acc.max_multiplier - 1) * t * t)
	local out = math.floor(carry)
	carry = carry - out
	return out > step and out or step
end

---sign: 1 = increase, -1 = decrease.
---The count is read synchronously (before vim.schedule) because
---vim.v.count1 is only valid while the mapping is running.
local function run(sign, dim, step, count)
	local d = assert(DIMS[dim], "dim must be 'width' or 'height'")
	step = math.max(1, step or config.step)

	-- An explicit count means "exactly this much": no acceleration
	if config.accelerate.enabled and count == nil and vim.v.count == 0 then
		step = accelerated(step)
	end

	-- More repetitions than the screen has cells can never matter
	local limit = d.pos == 2 and o.columns or o.lines
	local n = math.min(count or vim.v.count1, math.ceil(limit / step))

	vim.schedule(function()
		local current = api.nvim_get_current_win()
		local size = d.get(current)

		-- Floating windows and edge windows behave the same on every repeat,
		-- so all repeats collapse into a single resize.
		if api.nvim_win_get_config(current).relative ~= "" then
			d.set(current, math.max(1, size + sign * step * n))
			return
		end

		local edge = edge_direction(d)
		if edge then
			d.set(current, math.max(1, size + sign * edge * step * n))
			return
		end

		-- Neighbours on both sides: the center check depends on the new size,
		-- so repeat. Values that don't change between repeats are read once.
		local mid, winmin = editor_middle(d), o[d.winmin]
		local once = sign > 0 and increase_once or decrease_once

		for _ = 1, n do
			once(d, step, current, size, mid, winmin)
			local new_size = d.get(current)
			-- Nothing left to give or take: further repeats are wasted work
			if new_size == size then
				break
			end
			size = new_size
		end
	end)
end

---Grow the current window, balanced around the editor center.
---@param dim "width"|"height"
---@param step? integer cells per repetition (default: config.step)
---@param count? integer repetitions (default: vim.v.count1, e.g. `5<key>`)
function M.increase(dim, step, count)
	run(1, dim, step, count)
end

---Shrink the current window, balanced around the editor center.
---@param dim "width"|"height"
---@param step? integer cells per repetition (default: config.step)
---@param count? integer repetitions (default: vim.v.count1)
function M.decrease(dim, step, count)
	run(-1, dim, step, count)
end

---@param opts? Config
function M.setup(opts)
	if opts and next(opts) then
		config = vim.tbl_deep_extend("force", config, opts)
	end
end

return M
