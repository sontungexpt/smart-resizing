local vim = vim
local uv = vim.uv or vim.loop
local fn = vim.fn
local api = vim.api
local o = vim.o
local fn_winnr = fn.winnr

local M = {}

---@alias DimensionEnum number
---| 1 # HEIGHT
---| 2 # WIDTH
---

---@type table<string, DimensionEnum>
local Dimension = {
	HEIGHT = 1,
	WIDTH = 2,
}
M.Dimension = Dimension

---@alias ActionEnum number
---| 1 # INCREASE
---| 2 # DECREASE

---@type table<string, ActionEnum>
local Action = {
	INCREASE = 1,
	DECREASE = 2,
}

M.Action = Action

--- Create a speedup callback
--- @param cb fun(step: number, action: ActionEnum) The callback function
--- @param speedup_threshold? uinteger The threshold of the speedup
--- @param adjustment_factor? uinteger The adjustment factor of the speedup
--- @return fun(step: number, action: ActionEnum) The adjust size callback
local create_hold_pressed_callback = function(cb, speedup_threshold, adjustment_factor)
	---@diagnostic disable: undefined-field
	local timer = uv.new_timer()
	local last_call_time = -1
	local is_speedup = false

	speedup_threshold = speedup_threshold or 600
	adjustment_factor = adjustment_factor or 2

	--- @param step number The step of increasing
	--- @param action ActionEnum The action of the window resizing
	return function(step, action)
		timer:stop()
		timer:start(
			180, -- Stop holding and speedup after 250
			0,
			vim.schedule_wrap(function()
				timer:stop()
				is_speedup = false
				last_call_time = -1
			end)
		)

		if is_speedup then
			cb(math.ceil((uv.now() - last_call_time) / 1000 + adjustment_factor), action)
		else
			if last_call_time < 0 then
				last_call_time = uv.now()
			end
			cb(step, action)

			if uv.now() - last_call_time > speedup_threshold then
				is_speedup = true
			end
		end
	end
end

local is_float = function()
	return api.nvim_win_get_config(0).relative ~= ""
end

--- Get the window id of the direction or the current window
local winid = function(direction)
	return direction and fn.win_getid(fn_winnr(direction)) or api.nvim_get_current_win()
end

---Get the middle position of the vim
---@param dimension DimensionEnum The dimension of the window
---@return number The middle position of the vim
local middle_vim_position = function(dimension)
	if dimension == Dimension.WIDTH then
		return o.columns / 2
	else
		return (
			o.lines
			- o.cmdheight
			- (o.laststatus ~= 0 and 1 or 0)
			- (o.showtabline ~= 0 and #api.nvim_list_tabpages() > 1 and 1 or 0)
		) / 2
	end
end

---Get the window properties
---@param dimension DimensionEnum The dimension of the window
---@param step uinteger The step of increasing
local get_window_properties = function(step, dimension)
	local width_dimension = dimension == Dimension.WIDTH
	local winnr = fn_winnr()
	local set_fn, get_fn, winmin, primary_direction = nil, nil, nil, nil

	if width_dimension then
		primary_direction = winnr == fn_winnr("l") and -step or winnr == fn_winnr("h") and step or nil
		set_fn = api.nvim_win_set_width
		get_fn = api.nvim_win_get_width
		winmin = o.winminwidth
	else
		primary_direction = winnr == fn_winnr("j") and -step or winnr == fn_winnr("k") and step or nil
		set_fn = api.nvim_win_set_height
		get_fn = api.nvim_win_get_height
		winmin = o.winminheight
	end

	local win_size = get_fn(0)

	return {
		width_dimension = width_dimension,
		primary_direction = primary_direction, -- The primary direction of the window resizing in increasing if decreasing then change this prop to negative
		set_fn = set_fn,
		get_fn = get_fn,
		winmin = winmin,
		win_size = win_size,
		middle_position = api.nvim_win_get_position(0)[dimension] + win_size / 2,
	}
end

---Adjust the window dimension smartly
---@param step uinteger The step of increasing
---@param dimension DimensionEnum The dimension of the window
M.increase_current_win_size = function(step, dimension)
	vim.schedule(function()
		local props = get_window_properties(step, dimension)
		local set_fn = props.set_fn
		local win_size = props.win_size

		if is_float() then
			set_fn(0, win_size + step)
			return
		end

		local get_fn = props.get_fn

		if props.primary_direction then
			set_fn(0, win_size + props.primary_direction)
		elseif props.middle_position < middle_vim_position(dimension) - win_size / 3 then -- move the threshold to left than the middle_vim_position
			set_fn(0, win_size + step)
		else
			local hork = props.width_dimension and "h" or "k"
			local idx = 1
			local last_id = -1
			local target_id = winid(hork)
			local winmin = props.winmin

			local dimensions = {
				{ id = target_id, size = get_fn(target_id) },
			}

			while dimensions[idx].size - step <= winmin do
				if last_id == target_id then
					set_fn(0, win_size + step)
					break
				else
					last_id = target_id
					idx = idx + 1
					target_id = winid(hork)
					dimensions[idx] = { id = target_id, size = get_fn(target_id) }
				end
			end

			for i = idx, 1, -1 do
				local adjust_size = step * idx
				local new_size = dimensions[i].size - adjust_size
				if new_size < winmin then
					adjust_size = dimensions[i].size - winmin
					new_size = winmin
				end
				set_fn(dimensions[i].id, new_size)
				if i > 1 then
					dimensions[i - 1].size = dimensions[i - 1].size + adjust_size
				end
			end
		end
	end)
end

--- Decrease the window dimension smartly
--- @param step uinteger The step of decreasing
--- @param dimension DimensionEnum The dimension of the window
M.decrease_current_win_size = function(step, dimension)
	vim.schedule(function()
		local props = get_window_properties(step, dimension)
		local win_size = props.win_size
		local set_fn = props.set_fn

		if is_float() then
			set_fn(0, win_size - step)
			return
		end

		local get_fn = props.get_fn
		local winmin = props.winmin

		if props.primary_direction then
			set_fn(0, win_size - props.primary_direction)
		elseif win_size > winmin and props.middle_position > middle_vim_position(dimension) - win_size / 3 then -- move the threshold to left than the middle_vim_position
			set_fn(0, win_size - step)
		elseif fn.winwidth(fn.winnr(props.width_dimension and "l" or "j")) > winmin or win_size > winmin then
			local target_id = winid(props.width_dimension and "h" or "k")
			set_fn(target_id, get_fn(target_id) + step)
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

M.adjust_current_win_width = create_hold_pressed_callback(function(step, action)
	if action == Action.INCREASE then
		M.increase_current_win_size(step, Dimension.WIDTH)
	else
		M.decrease_current_win_size(step, Dimension.WIDTH)
	end
end)

M.adjust_current_win_height = create_hold_pressed_callback(function(step, action)
	if action == Action.DECREASE then
		M.increase_current_win_size(step, Dimension.HEIGHT)
	else
		M.decrease_current_win_size(step, Dimension.HEIGHT)
	end
end)

return M
