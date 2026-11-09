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
HOW IT BALANCES (no cached state)

  Every repetition reads the live layout and splits its `step` cells evenly
  between the `before` side (left/up) and the `after` side (right/down).
  When `step` is odd, the spare cell goes to whichever side the current
  window size's parity selects, so consecutive repeats alternate sides.
  Nothing is remembered between calls, so other plugins, mouse drags,
  :wincmd or any other event can change the layout at any time without
  confusing the next resize.

  Space is always taken from the nearest neighbour first, and a farther
  neighbour is only touched once the nearer one is at its minimum size.
  If one side has no room left, the other side covers the rest.

  STATE POLICY
  Layout state (window sizes, positions, neighbours, minimum sizes) is read
  live inside every resize and never stored. The only thing remembered
  between calls is the key-hold timer used for acceleration. It holds no
  layout information, it is discarded as soon as it is older than
  HOLD_TIMEOUT_MS, and it is also discarded when the key, direction or
  window changes, so it cannot go stale.

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
		threshold_ms = 110,
		ramp_ms = 1500,
		max_multiplier = 6,
	},
}

-- A key counts as "held" while repeats arrive faster than this (ms).
-- Raise it (e.g. 150) if acceleration keeps resetting because your OS
-- key-repeat is slow; lower it if separate quick taps count as a hold.
local HOLD_TIMEOUT_MS = 80

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

local win_getid, winnr = fn.win_getid, fn.winnr

---Window id in a direction (e.g. "h", "2l"), relative to the current window
local function winid(direction)
	return win_getid(winnr(direction))
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

---Split `step` cells between the `before` and `after` side.
---Even steps split evenly. For an odd step the spare cell goes to a side
---chosen by the parity of the live window size, so it alternates between
---repeats without remembering anything.
---@return integer before_amount
---@return integer after_amount
local function split_step(step, size)
	local base = math.floor(step / 2)
	local spare = step - 2 * base -- 0 or 1
	if size % 2 == 0 then
		return base + spare, base
	end
	return base, base + spare
end

---Take up to `want` cells from the windows AFTER us (3, then 4, ...).
---Growing the current window makes Neovim take space from the nearest window
---after us first, and only move on to the next one when the nearer one is at
---its minimum. So we only need to check that there is enough room and grow
---the current window; the farther windows stay untouched until needed.
---Returns how many cells were taken.
local function take_after(d, want, current, winmin)
	if want <= 0 then
		return 0
	end

	local room, last = 0, nil
	for idx = 1, 64 do
		local id = winid(idx .. d.after)
		if id == last or id == current then
			break
		end
		local sz = d.get(id)
		if sz > winmin then
			room = room + (sz - winmin)
		end
		last = id
		if room >= want then
			break
		end
	end

	local amount = math.min(want, room)
	if amount > 0 then
		d.set(current, d.get(current) + amount)
	end
	return amount
end

---Take up to `want` cells from the windows BEFORE us (1 is nearest, then 2, ...).
---Shrinking a window hands its space to the window after it, so the freed
---cells flow towards us. Apply from the farthest donor to the nearest, and do
---NOT resize the current window afterwards (that would also eat from the
---windows after us).
---Returns how many cells were taken.
local function take_before(d, want, current, winmin)
	if want <= 0 then
		return 0
	end

	-- Fresh tables on every call: nothing survives between resizes
	local donor_ids, donor_targets = {}, {}
	local remaining, last_donor, last = want, 0, nil
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
		return 0
	end

	for i = last_donor, 1, -1 do
		d.set(donor_ids[i], donor_targets[i])
	end
	return want - remaining
end

---One increase of `step` cells (window has neighbours on both sides).
---Half comes from each side; if a side cannot give its share, the other
---side covers the shortfall.
local function increase_once(d, step, current, size, winmin)
	local want_before, want_after = split_step(step, size)

	local taken = take_before(d, want_before, current, winmin)
	taken = taken + take_after(d, want_after, current, winmin)

	local short = step - taken
	if short > 0 then
		short = short - take_after(d, short, current, winmin)
	end
	if short > 0 then
		short = short - take_before(d, short, current, winmin)
	end
	if short == step then
		d.set(current, size + step)
	end
end

---One decrease of `step` cells (window has neighbours on both sides).
---Half is given back through each edge.
local function decrease_once(d, step, current, size, winmin)
	local floor_size = math.max(1, winmin)
	local amount = math.min(step, size - floor_size)
	if amount <= 0 then
		return
	end

	local from_before, from_after = split_step(amount, size)

	-- Before edge: grow the neighbour before us, it takes the cells from us.
	if from_before > 0 then
		local push = winid(d.before)
		if push ~= current then
			d.set(push, d.get(push) + from_before)
		end
	end

	-- After edge: shrink ourselves, the cells go to the nearest window after us.
	if from_after > 0 then
		local now = d.get(current)
		local target = math.max(floor_size, now - from_after)
		if target < now then
			d.set(current, target)
		end
	end
end

-- The only state kept between calls: when the current hold started, when
-- the last repeat arrived, and the fractional cells not yet applied.
-- It never stores anything about the layout. It is replaced whenever it is
-- older than HOLD_TIMEOUT_MS or belongs to a different key/window.
local hold = nil

---Grow `step` smoothly the longer the key is held down.
---Speed follows an ease-in curve (t^2) from 1x to `max_multiplier`x, and the
---fractional part is carried over so the speed ramps without integer jumps.
---@param step integer
---@param key string identifies the held key (direction, dimension, window)
---@return integer
local function accelerated(step, key)
	local acc = config.accelerate
	local now = uv.hrtime() / 1e6

	if not hold or hold.key ~= key or now - hold.last > HOLD_TIMEOUT_MS then
		hold = { key = key, start = now, last = now, carry = 0 } -- a new hold begins
	end
	hold.last = now

	local t = (now - hold.start - acc.threshold_ms) / acc.ramp_ms
	if t <= 0 then
		return step
	end
	if t > 1 then
		t = 1
	end

	hold.carry = hold.carry + step * (1 + (acc.max_multiplier - 1) * t * t)
	local out = math.floor(hold.carry)
	hold.carry = hold.carry - out
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
		step = accelerated(step, sign .. dim .. api.nvim_get_current_win())
	end

	-- More repetitions than the screen has cells can never matter
	local limit = d.pos == 2 and o.columns or o.lines
	local n = math.min(count or vim.v.count1, math.ceil(limit / step))

	vim.schedule(function()
		-- The command-line window does not allow resizing other windows
		if fn.getcmdwintype() ~= "" then
			return
		end

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

		-- Neighbours on both sides: every repeat reads the live layout and
		-- splits its cells between both sides. Nothing is cached.
		local winmin = o[d.winmin]
		local once = sign > 0 and increase_once or decrease_once

		for _ = 1, n do
			once(d, step, current, size, winmin)
			local new_size = d.get(current)
			-- Nothing left to give or take: further repeats are wasted work
			if new_size == size then
				break
			end
			size = new_size
		end
	end)
end

---Grow the current window evenly towards both sides.
---@param dim "width"|"height"
---@param step? integer cells per repetition (default: config.step)
---@param count? integer repetitions (default: vim.v.count1, e.g. `5<key>`)
function M.increase(dim, step, count)
	run(1, dim, step, count)
end

---Shrink the current window evenly from both sides.
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
