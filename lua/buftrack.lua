local M = {}

M.buffers = {}
M.index = 1
M.cycling = false
M.max_tracked = nil

M.sidebar = {
  bufnr = nil,
  winid = nil,
  width = 36,
}

local function bufvalid(bufnr)
  return vim.api.nvim_buf_is_loaded(bufnr)
      and vim.api.nvim_buf_is_valid(bufnr)
      and vim.bo[bufnr].buflisted
      and vim.bo[bufnr].buftype == ""
end

local function sidebar_is_open()
  return M.sidebar.winid
    and vim.api.nvim_win_is_valid(M.sidebar.winid)
    and M.sidebar.bufnr
    and vim.api.nvim_buf_is_valid(M.sidebar.bufnr)
end

local function sidebar_close()
  if M.sidebar.winid and vim.api.nvim_win_is_valid(M.sidebar.winid) then
    pcall(vim.api.nvim_win_close, M.sidebar.winid, true)
  end
  if M.sidebar.bufnr and vim.api.nvim_buf_is_valid(M.sidebar.bufnr) then
    pcall(vim.api.nvim_buf_delete, M.sidebar.bufnr, { force = true })
  end
  M.sidebar.winid = nil
  M.sidebar.bufnr = nil
end

local function sidebar_render()
  if not sidebar_is_open() then return end

  local header = { "buftrack.nvim", string.rep("─", M.sidebar.width), "" }
  local lines = { }

  if #M.buffers == 0 then
    table.insert(lines, "[No tracked buffers]")
  else
    for i, buf in ipairs(M.buffers) do
      if bufvalid(buf) then
        name = vim.api.nvim_buf_get_name(buf)
        if name == "" then
          name = "???"
        else
          name = vim.fn.fnamemodify(name, ":t")
        end

        local mark = (i == M.index) and "  <--" or ""
        table.insert(lines, string.format("%s%s", name, mark))
      end
    end
  end

  local reversed = {}

  for i = #lines, 1, -1 do
    local val = lines[i]
    table.insert(reversed, val)
  end

  for _,v in ipairs(reversed) do
      table.insert(header, v)
  end

  vim.api.nvim_buf_set_option(M.sidebar.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(M.sidebar.bufnr, 0, -1, false, header)
  vim.api.nvim_buf_set_option(M.sidebar.bufnr, "modifiable", false)
end

function M.open_sidebar()
  if sidebar_is_open() then
    sidebar_render()
    return
  end

  local cur_win = vim.api.nvim_get_current_win()

  -- Create scratch buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "buftrack"

  -- Open left split and put buffer in it
  vim.cmd("topleft vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_width(win, M.sidebar.width)

  -- Window-local options
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"

  M.sidebar.bufnr = buf
  M.sidebar.winid = win

  -- Auto-clear state when the sidebar buffer is wiped
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    callback = function()
      M.sidebar.winid = nil
      M.sidebar.bufnr = nil
    end,
  })

  if vim.api.nvim_win_is_valid(cur_win) then
    vim.api.nvim_set_current_win(cur_win)
  end

  sidebar_render()
end

function M.toggle_sidebar()
  if sidebar_is_open() then
    sidebar_close()
  else
    M.open_sidebar()
  end
end

function M.track_buffer()
  if M.cycling then return end
  local buf = vim.api.nvim_get_current_buf()

  -- Remove existing entry if present
  for i, b in ipairs(M.buffers) do
    if b == buf then
      table.remove(M.buffers, i)
      break
    end
  end

  table.insert(M.buffers, buf)
  -- Cap buffer list size
  if #M.buffers > M.max_tracked then
    table.remove(M.buffers, 1)
  end

  M.index = #M.buffers
  sidebar_render()
end

local function get_valid_buffer(start_index, direction)
  local count = #M.buffers
  local index = start_index
  while index >= 1 and index <= count do
    if bufvalid(M.buffers[index]) then
      return index
    else
      table.remove(M.buffers, index)
      count = math.max(0, M.index - 1)
      M.index = math.max(1, M.index - 1)
      if count == 0 then return nil end
    end
    index = index + direction
  end
  return nil
end

function M.next_buffer()
  if #M.buffers == 0 then return end
  M.cycling = true
  local new_index = get_valid_buffer(M.index + 1, 1)
  if new_index then
    M.index = new_index
    vim.api.nvim_set_current_buf(M.buffers[M.index])
    sidebar_render()
  else
    print("[buftrack.nvim] Reached the latest buffer.")
  end
  M.cycling = false
end

function M.prev_buffer()
  if #M.buffers == 0 then return end
  M.cycling = true
  local new_index = get_valid_buffer(M.index - 1, -1)
  if new_index then
    M.index = new_index
    vim.api.nvim_set_current_buf(M.buffers[M.index])
    sidebar_render()
  else
    print("[buftrack.nvim] Reached the oldest buffer.")
  end
  M.cycling = false
end


function M.print_tracked_buffers()
  if #M.buffers == 0 then
    print("[buftrack.nvim] No tracked buffers.")
    return
  end

  print("[buftrack.nvim] Tracked Buffers:")
  for i, buf in ipairs(M.buffers) do
    if vim.api.nvim_buf_is_valid(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name == "" then name = "[No Name]" end
      print(i .. ": " .. name)
    end
  end
  print("[buftrack.nvim] Cursor: ", M.index)
end

function M.clear_tracked_buffers()
  M.buffers = {}
  M.index = 1
  sidebar_render()
  print("[buftrack.nvim] Cleared tracked buffers.")
end

local function sidebar_is_last_window_in_tab()
  if not sidebar_is_open() then return false end
  local wins = vim.api.nvim_tabpage_list_wins(0)
  return (#wins == 1) and (wins[1] == M.sidebar.winid)
end

local function sidebar_handle_last_window()
  if not sidebar_is_last_window_in_tab() then return end

  if vim.fn.tabpagenr("$") > 1 then
    vim.cmd("tabclose")
  else
    vim.cmd("quit")
  end
end

function M.setup(opts)
  opts = opts or {}
  M.max_tracked = opts["max_tracked"] or 16

  vim.api.nvim_create_autocmd({ "BufEnter", "BufLeave" }, {
    callback = M.track_buffer
  })

  local aug = vim.api.nvim_create_augroup("BufTrackSidebar", { clear = true })
  vim.api.nvim_create_autocmd({ "WinEnter", "WinClosed", "TabEnter" }, {
    group = aug,
    callback = function()
      vim.schedule(sidebar_handle_last_window)
    end,
  })

  vim.api.nvim_create_user_command("BufTrack", M.track_buffer, {})
  vim.api.nvim_create_user_command("BufTrackPrev", M.prev_buffer, {})
  vim.api.nvim_create_user_command("BufTrackNext", M.next_buffer, {})
  vim.api.nvim_create_user_command("BufTrackList", M.print_tracked_buffers, {})
  vim.api.nvim_create_user_command("BufTrackClear", M.clear_tracked_buffers, {})
  vim.api.nvim_create_user_command("BufTrackSidebar", M.toggle_sidebar, {})
end

return M
