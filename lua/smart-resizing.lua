local uv = vim.uv or vim.loop
local fn, api, o = vim.fn, vim.api, vim.o

local M = {}

---@class Config
---@field step integer Cells per repetition when `step` is not passed (default: 1)
---@field accelerate boolean Speed up while a key is held down (default: false)
local config = {
	step = 1,
	accelerate = false,
}

-- A key counts as "held" while repeats arrive faster than this (ms)
local HOLD_TIMEOUT_MS = 180
-- Holding longer than this starts the speedup (ms)
local HOLD_THRESHOLD_MS = 600
-- Base added to the speedup step
local HOLD_FACTOR = 2

---`before` is the left/up side, `after` is the right/down side.
---`pos` is the index into nvim_win_get_position() ({row, col}).
local DIMS = {
	width = {
		pos = 2,
		set = api.nvim_win_set_width,
		get = api.nvim_win_get_width,
		winmin = function()
			return o.winminwidth
		end,
		before = "h",
		after = "l",
	},
	height = {
		pos = 1,
		set = api.nvim_win_set_height,
		get = api.nvim_win_get_height,
		winmin = function()
			return o.winminheight
		end,
		before = "k",
		after = "j",
	},
}

local function is_float()
	return api.nvim_win_get_config(0).relative ~= ""
end

---Window id in a direction (e.g. "h", "2l")
local function winid(direction)
	return fn.win_getid(fn.winnr(direction))
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

local function window_middle(d, size)
	return api.nvim_win_get_position(0)[d.pos] + size / 2
end

---Signed step if the window sits on an edge, nil if it has neighbours on both sides.
---Positive moves the separator toward `after`, negative toward `before`.
local function edge_direction(step, d)
	local winnr = fn.winnr()
	if winnr == fn.winnr(d.after) then
		return -step
	elseif winnr == fn.winnr(d.before) then
		return step
	end
end

---One increase of `step` cells. The center check is re-evaluated on every call,
---so repeating it keeps the result balanced around the middle.
local function increase_once(d, step)
	local size = d.get(0)

	if is_float() then
		d.set(0, math.max(1, size + step))
		return
	end

	local edge = edge_direction(step, d)
	if edge then
		d.set(0, math.max(1, size + edge))
		return
	end

	if window_middle(d, size) < editor_middle(d) then
		d.set(0, size + step)
		return
	end

	-- Right/bottom half: take space from windows before us (1h, 2h, 3h, ...)
	local current = api.nvim_get_current_win()
	local chain, last = {}, nil
	for idx = 1, 64 do
		local id = winid(idx .. d.before)
		if id == last or id == current then
			break
		end
		chain[#chain + 1] = { id = id, size = d.get(id) }
		last = id
	end

	-- Take `step` cells from the nearest windows first, never below winmin
	local winmin = d.winmin()
	local targets, remaining, last_donor = {}, step, 0
	for i, w in ipairs(chain) do
		local take = math.min(remaining, math.max(0, w.size - winmin))
		targets[i] = w.size - take
		if take > 0 then
			last_donor = i
		end
		remaining = remaining - take
	end

	if last_donor == 0 then
		d.set(0, size + step)
		return
	end

	-- Apply from the farthest donor towards us so freed space reaches us
	for i = last_donor, 1, -1 do
		d.set(chain[i].id, targets[i])
	end

	if remaining > 0 then
		d.set(0, d.get(0) + remaining)
	end
end

---One decrease of `step` cells.
local function decrease_once(d, step)
	local size = d.get(0)

	if is_float() then
		d.set(0, math.max(1, size - step))
		return
	end

	local edge = edge_direction(step, d)
	if edge then
		d.set(0, math.max(1, size - edge))
		return
	end

	local winmin = d.winmin()
	if size > winmin and window_middle(d, size) >= editor_middle(d) then
		d.set(0, math.max(1, size - step))
		return
	end

	-- Shrink by growing the neighbour before us, if something after us has room
	local current = api.nvim_get_current_win()
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

---Replace `step` with a growing step while the key is held down
local function accelerated(step)
	local now = uv.hrtime() / 1e6
	if not last_press or now - last_press > HOLD_TIMEOUT_MS then
		hold_start = now -- a new hold begins
	end
	last_press = now

	local held = now - hold_start
	if held > HOLD_THRESHOLD_MS then
		return math.ceil(held / 1000 + HOLD_FACTOR)
	end
	return step
end

---The count is read synchronously (before vim.schedule) because
---vim.v.count1 is only valid while the mapping is running.
local function run(once, dim, step, count)
	local d = assert(DIMS[dim], "dim must be 'width' or 'height'")
	step = math.max(1, step or config.step)
	if config.accelerate then
		step = accelerated(step)
	end
	local n = math.max(1, count or vim.v.count1)

	vim.schedule(function()
		for _ = 1, n do
			once(d, step)
		end
	end)
end

---Grow the current window, balanced around the editor center.
---@param dim "width"|"height"
---@param step? integer cells per repetition (default: config.step)
---@param count? integer repetitions (default: vim.v.count1, e.g. `5<key>`)
function M.increase(dim, step, count)
	run(increase_once, dim, step, count)
end

---Shrink the current window, balanced around the editor center.
---@param dim "width"|"height"
---@param step? integer cells per repetition (default: config.step)
---@param count? integer repetitions (default: vim.v.count1)
function M.decrease(dim, step, count)
	run(decrease_once, dim, step, count)
end

---@param opts? Config
function M.setup(opts)
    if type(opts) ~= "table" or not next(opts) then
        return
    end
    config.step = opts.step or config.step
    config.accelerate = opts.accelerate or config.accelerate
end

return M
