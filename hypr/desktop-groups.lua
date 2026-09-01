-- omarchy-desktop-groups -- Windows-style virtual desktops for Hyprland.
--
-- Hyprland workspaces belong to exactly one monitor. There is no built-in notion
-- of a desktop that spans monitors, so nothing moves every screen at once the way
-- Win+Ctrl+Arrow does on Windows. This module adds that.
--
-- A "desktop" is one workspace per monitor. With three monitors and three
-- desktops you get:
--
--                left    middle   right
--   SUPER+F1        1        2       3
--   SUPER+F2        5        6       7
--   SUPER+F3        9       10      11
--
-- Monitors are ordered by their x position -- left to right as they physically
-- sit on your desk. This is deliberate: Hyprland's monitor `id` is DRM probe
-- order, which routinely bears no relation to physical layout (a laptop panel is
-- commonly id 0 while sitting at the far right of the desk), so numbering by id
-- produces a scrambled mapping on exactly the multi-monitor setups this is for.
--
-- Usage, in ~/.config/hypr/hyprland.lua:
--
--   require("hypr.desktop-groups").setup()
--   require("hypr.desktop-groups").setup({ desktops = 4, slots = 4 })
--
-- See README.md for the full option list.

local M = {}

local DEFAULTS = {
  -- How many desktops to create.
  desktops = 3,

  -- Key pattern for the switch bindings. %d is the desktop number.
  -- F1..F12 are unbound in stock Omarchy; arrow combinations are not.
  bind = "SUPER + F%d",

  -- Workspaces reserved per desktop. Defaults to the number of monitors
  -- connected when setup() runs.
  --
  -- Set this explicitly to your maximum monitor count if you dock and undock.
  -- The stride determines the workspace numbering, so letting it follow the
  -- live monitor count means the numbers shift when a monitor disappears --
  -- desktop 2 starts at 5 with four monitors but at 4 with three. Pinning
  -- `slots` keeps the mapping stable and simply leaves the tail unused.
  slots = nil,
}

-- Settings the bar widget can flip, persisted so a reload or reboot keeps them.
--
-- Kept in XDG state rather than in hyprland.lua: these are runtime toggles, and
-- rewriting a user's config file from a bar click is a worse trade than a small
-- state file the module reads at setup.
local state_dir = (os.getenv("XDG_STATE_HOME") or ((os.getenv("HOME") or "") .. "/.local/state")) .. "/omarchy"
local state_path = state_dir .. "/desktop-groups.conf"

local function read_state()
  local values = {}
  local file = io.open(state_path, "r")
  if not file then
    return values
  end

  for line in file:lines() do
    local key, value = line:match("^([%w_]+)=([01])$")
    if key then
      values[key] = value == "1"
    end
  end

  file:close()
  return values
end

local function write_state(values)
  os.execute("mkdir -p '" .. state_dir .. "'")

  local file = io.open(state_path, "w")
  if not file then
    return
  end

  for key, value in pairs(values) do
    file:write(key .. "=" .. (value and "1" or "0") .. "\n")
  end

  file:close()
end

local settings = { enabled = true, hide_special = true }

-- Rules and binds created by the last apply(), so a rebuild can retire them.
local created = { rules = {}, binds = {} }
local options = {}

-- Monitors left to right. Mirrored outputs are skipped: they duplicate another
-- screen, so giving them their own workspace would strand it out of view.
local function monitors_by_position()
  local list = {}

  for _, monitor in ipairs(hl.get_monitors() or {}) do
    if not monitor.is_mirror then
      list[#list + 1] = monitor
    end
  end

  table.sort(list, function(a, b)
    if a.x ~= b.x then
      return a.x < b.x
    end
    return a.y < b.y
  end)

  return list
end

local function slot_count(monitors)
  return options.slots or math.max(#monitors, 1)
end

-- Workspaces are laid out desktop-major: desktop 1 takes the first `slots`
-- numbers, desktop 2 the next, and so on. Returned as a string -- every
-- workspace-facing API here wants one, and passing a number fails in ways that
-- are not obvious from the error ("attempt to index a number value").
local function workspace_for(desktop, column, slots)
  return tostring((desktop - 1) * slots + column)
end

-- Pin each workspace to its monitor.
--
-- Without these rules a monitor claims the lowest free workspace as it comes up,
-- in probe order, so the mapping is whatever the hardware happened to enumerate
-- and it reshuffles on every reload and hotplug.
--
-- `monitor` and `default` do different jobs: `monitor` says where a workspace
-- lives once it exists, `default` picks the one a monitor opens on when it first
-- appears. Only desktop 1 can carry `default`, since a monitor boots into a
-- single workspace.
local function apply_rules(monitors)
  -- Workspace rules expose set_enabled but no remove, so stale ones are
  -- disabled rather than deleted. Skipping this would stack a fresh set of
  -- rules on every hotplug.
  for _, rule in ipairs(created.rules) do
    rule:set_enabled(false)
  end
  created.rules = {}

  local slots = slot_count(monitors)

  for desktop = 1, options.desktops do
    for column, monitor in ipairs(monitors) do
      -- More monitors than slots means the extras have no workspace in this
      -- scheme; raise `slots` to include them.
      if column <= slots then
        created.rules[#created.rules + 1] = hl.workspace_rule({
          workspace = workspace_for(desktop, column, slots),
          monitor = monitor.name,
          default = desktop == 1,
        })
      end
    end
  end
end

-- Move every monitor onto the given desktop.
--
-- Hyprland has no "switch everything" dispatcher, so this focuses each workspace
-- in turn and lets the pinning rules route it to the right screen.
--
-- monitor:set_workspace() is the API this looks like it should use, and it is
-- not: it silently does nothing when the target workspace currently lives on
-- another monitor, which is the normal case here. Focusing is what moves it.
--
-- The monitor under the cursor is focused last so switching desktops leaves you
-- where you started rather than dumping focus on whichever screen came last.
function M.switch(desktop)
  local monitors = monitors_by_position()
  if #monitors == 0 then
    return
  end

  local slots = slot_count(monitors)
  local here = hl.get_monitor_at_cursor()
  local last

  for column, monitor in ipairs(monitors) do
    if column <= slots then
      local workspace = workspace_for(desktop, column, slots)

      if here and monitor.name == here.name then
        last = workspace
      else
        hl.dispatch(hl.dsp.focus({ workspace = workspace }))
      end
    end
  end

  if last then
    hl.dispatch(hl.dsp.focus({ workspace = last }))
  end
end

-- Which desktop the focused monitor is currently showing, or nil if it is on a
-- workspace outside the scheme. Useful for a status bar indicator.
function M.current()
  local monitors = monitors_by_position()
  local slots = slot_count(monitors)
  local here = hl.get_monitor_at_cursor()

  if not here or not here.active_workspace then
    return nil
  end

  local id = here.active_workspace.id
  if type(id) ~= "number" or id < 1 then
    return nil
  end

  local desktop = math.floor((id - 1) / slots) + 1
  if desktop >= 1 and desktop <= options.desktops then
    return desktop
  end

  return nil
end

local function apply_binds()
  for _, bind in ipairs(created.binds) do
    bind:remove()
  end
  created.binds = {}

  if not settings.enabled then
    return
  end

  for desktop = 1, options.desktops do
    local keys = string.format(options.bind, desktop)

    created.binds[#created.binds + 1] = hl.bind(keys, function()
      M.switch(desktop)
    end, { description = "Switch all monitors to desktop " .. desktop })
  end
end

local function apply_all()
  apply_rules(monitors_by_position())
  apply_binds()
end

-- ---- Toggles the bar widget drives ----------------------------------------

function M.is_enabled()
  return settings.enabled
end

-- Turning this off retires the bindings and disables the workspace rules, so
-- Hyprland goes back to its own workspace placement. It does not move any
-- window: whatever sits on workspace 7 stays there.
function M.set_enabled(on)
  settings.enabled = on and true or false
  write_state(settings)
  apply_all()
  return settings.enabled
end

function M.hides_special()
  return settings.hide_special
end

-- binds:hide_special_on_workspace_change -- whether the SUPER+S scratchpad is
-- put away when the workspace changes. Surfaced here because a desktop switch
-- changes the workspace on every monitor at once, which makes this setting far
-- more noticeable than it is on a single screen.
function M.set_hide_special(on)
  settings.hide_special = on and true or false
  write_state(settings)
  hl.config({ binds = { hide_special_on_workspace_change = settings.hide_special } })
  return settings.hide_special
end

function M.setup(opts)
  options = {}
  for key, value in pairs(DEFAULTS) do
    options[key] = value
  end
  for key, value in pairs(opts or {}) do
    options[key] = value
  end

  -- setup() runs again on every config reload, so the stored toggles have to be
  -- re-read and re-applied here or a reload would silently reset them.
  local stored = read_state()
  for key, value in pairs(stored) do
    settings[key] = value
  end

  hl.config({ binds = { hide_special_on_workspace_change = settings.hide_special } })
  apply_all()

  -- Rebuild when the monitor set changes. Two reasons this matters: monitors may
  -- not be enumerated yet while the config is first parsed, and undocking or
  -- plugging in a screen changes the left-to-right order the mapping is built
  -- from. Binds compute their layout at press time and so need no rebuild.
  for _, event in ipairs({ "monitor.added", "monitor.removed", "monitor.layout_changed" }) do
    hl.on(event, function()
      apply_rules(monitors_by_position())
    end)
  end

  return M
end

return M
