local uv = vim.uv or vim.loop
local fn, api, o = vim.fn, vim.api, vim.o

local M = {}

---@alias Dimension integer
---| 1 # HEIGHT
---| 2 # WIDTH

---@type table<string, Dimension>
local Dimension = { HEIGHT = 1, WIDTH = 2 }
M.Dimension = Dimension

---@alias ActionEnum integer
---| 1 # INCREASE
---| 2 # DECREASE

---@type table<string, ActionEnum>
local Action = { INCREASE = 1, DECREASE = 2 }
M.Action = Action

-- A key is considered "held" while repeats arrive faster than this (ms)
local HOLD_TIMEOUT_MS = 180


---Per-dimension API and direction lookup, so the logic below is written once.
---`before` is the left/up side, `after` is the right/down side.
local DIMS = {
	[Dimension.WIDTH] = {
		set = api.nvim_win_set_width,
		get = api.nvim_win_get_width,
		winmin = function()
			return o.winminwidth
		end,
		before = "h",
		after = "l",
	},
	[Dimension.HEIGHT] = {
		set = api.nvim_win_set_height,
		get = api.nvim_win_get_height,
		winmin = function()
			return o.winminheight
		end,
		before = "k",
		after = "j",
	},
}

---Create a callback that speeds up while a key is held down
---@param cb fun(step: integer, action: ActionEnum)
---@param speedup_threshold? integer ms of holding before speedup starts (default 600)
---@param adjustment_factor? integer base added to the speedup step (default 2)
---@return fun(step: integer, action: ActionEnum)
local function create_hold_pressed_callback(cb, speedup_threshold, adjustment_factor)
	local timer = assert(uv.new_timer(), "failed to create timer")
	local last_call_time = -1
	local is_speedup = false

	speedup_threshold = speedup_threshold or 600
	adjustment_factor = adjustment_factor or 2

	local reset = vim.schedule_wrap(function()
		is_speedup = false
		last_call_time = -1
	end)

	return function(step, action)
		step = step or 1
		timer:stop()
		timer:start(HOLD_TIMEOUT_MS, 0, reset)

		local now = uv.now()
		if is_speedup then
			cb(math.ceil((now - last_call_time) / 1000 + adjustment_factor), action)
			return
		end

		if last_call_time < 0 then
			last_call_time = now
		end
		cb(step, action)

		if now - last_call_time > speedup_threshold then
			is_speedup = true
		end
	end
end

local function is_float()
	return api.nvim_win_get_config(0).relative ~= ""
end

---Window id in a direction (e.g. "h", "2l") or the current window
local function winid(direction)
	return direction and fn.win_getid(fn.winnr(direction)) or api.nvim_get_current_win()
end

---Middle of the usable editor area along a dimension
local function middle_vim_position(dimension)
	if dimension == Dimension.WIDTH then
		return o.columns / 2
	end

	local tabline = 0
	if o.showtabline == 2 or (o.showtabline == 1 and #api.nvim_list_tabpages() > 1) then
		tabline = 1
	end
	local statusline = o.laststatus ~= 0 and 1 or 0
	return (o.lines - o.cmdheight - statusline - tabline) / 2
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

local function window_middle(dimension, size)
	return api.nvim_win_get_position(0)[dimension] + size / 2
end

---Adjust the window dimension smartly
---@param step integer
---@param dimension Dimension
M.increase_current_win_size = function(step, dimension)
	vim.schedule(function()
		local d = DIMS[dimension]
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

		if window_middle(dimension, size) < middle_vim_position(dimension) then
			d.set(0, size + step)
			return
		end

		-- Right/bottom half: take space from windows before us.
		-- Collect the chain of neighbours: 1h, 2h, 3h, ...
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

		-- Nearest window that can actually give up space
		local winmin = d.winmin()
		local donor
		for i, w in ipairs(chain) do
			if w.size > winmin then
				donor = i
				break
			end
		end

		if not donor then
			d.set(0, size + step)
			return
		end

		local amount = math.min(step, chain[donor].size - winmin)
		d.set(chain[donor].id, chain[donor].size - amount)
		-- Pass the freed space along: restore each window between donor and us
		for i = donor - 1, 1, -1 do
			d.set(chain[i].id, chain[i].size)
		end
	end)
end

---Decrease the window dimension smartly
---@param step integer
---@param dimension Dimension
M.decrease_current_win_size = function(step, dimension)
	vim.schedule(function()
		local d = DIMS[dimension]
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
		if size > winmin and window_middle(dimension, size) >= middle_vim_position(dimension) then
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
	end)
end

M.increase_current_win_width = function(step)
	M.increase_current_win_size(step, Dimension.WIDTH)
end
M.decrease_current_win_width = function(step)
	M.decrease_current_win_size(step, Dimension.WIDTH)
end
M.increase_current_win_height = function(step)
	M.increase_current_win_size(step, Dimension.HEIGHT)
end
M.decrease_current_win_height = function(step)
	M.decrease_current_win_size(step, Dimension.HEIGHT)
end

---@param dimension Dimension
---@param grow_action ActionEnum which action maps to `increase_current_win_size`
local function make_adjuster(dimension, grow_action)
	return create_hold_pressed_callback(function(step, action)
		if action == grow_action then
			M.increase_current_win_size(step, dimension)
		else
			M.decrease_current_win_size(step, dimension)
		end
	end)
end

M.adjust_current_win_width = make_adjuster(Dimension.WIDTH, Action.INCREASE)
-- Height is intentionally inverted, as in the original: DECREASE maps to increase_current_win_size
M.adjust_current_win_height = make_adjuster(Dimension.HEIGHT, Action.DECREASE)

---@param opts? table
M.setup = function (opts)
    -- Keep empty setup just to satisfy the format of normal plugins

end

return M
