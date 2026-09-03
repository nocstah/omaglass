-- Omaglass — the engine. Hyprland Lua, loaded by the shell plugin's loader
-- (~/.config/hypr/omaglass.lua) on every config reload, and injected with
-- `hyprctl eval` for immediate effect. Re-entrant: unloads its previous
-- registration first. Everything plugin-side is guarded — the rules are
-- plain Hyprland and apply whether or not hyprglass is loaded.
--
-- Options arrive in _G.GLASS_OPTS (see Service.qml / manifest.json).
--
-- What it does, on every theme:
--   * terminals are glass panes (hyprglass_enabled) that sample the
--     wallpaper only (hyprglass_background, patched hyprglass) and are held
--     compositor-opaque so the glass shows through the terminal's OWN alpha
--   * chilled windows (Omachill's chillmode tag) are glass too
--   * fullscreen windows never are
--   * shadows: contact (an unfocused window over another window casts a
--     shadow only there, a lone one none, the focused window keeps the
--     theme's), theme (Hyprland's as the theme sets them), or flat (none)
--   * the material, unless the theme owns it (_G.glass_theme_owned): light
--     or dark from the theme's mode, neutral colour handling, the frost as
--     the default preset, "sheer" and "crystal" for the looks, glass on the
--     shell's layers
--   * per-window looks on two keys, and omaglass.* for the bar widget:
--       readability   glass -> milky -> solid -> glass
--       looks         glass -> clear -> sheer -> native -> contrast -> block
--     State is one static window tag, glass_<look>; none = the default.
--     Every toggle emits `custom>>omaglass <address> <look>` on the event
--     socket so the bar can follow without polling.

local OPTS = type(_G.GLASS_OPTS) == "table" and _G.GLASS_OPTS or {}
local function opt(key, default)
  local v = OPTS[key]
  if v == nil then return default end
  return v
end

local TERMINALS  = opt("terminal_classes", "^(foot|com\\.mitchellh\\.ghostty|Alacritty|kitty)$")
local HELPER     = tostring(opt("helper", "")) -- bin/glass-foot, absolute path
local NOTIFY     = opt("notify", true) ~= false
local MILKY      = tonumber(opt("milky_alpha", 65)) or 65
local CLEAR      = tonumber(opt("clear_alpha", 45)) or 45
local FROST      = tonumber(opt("frost", 30)) or 30
local KEY_READ   = opt("key_readability", "SUPER + CTRL + G")
local KEY_LOOKS  = opt("key_looks", "SUPER + CTRL + ALT + G")

local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

-- The default look for windows opened from now on ("All windows" in the
-- dropdown). Kept in a file so it survives reloads; the bar reads it too.
local STATE_DIR    = os.getenv("HOME") .. "/.local/state/omaglass"
local DEFAULT_FILE = STATE_DIR .. "/default-look"
local function read_default()
  local f = io.open(DEFAULT_FILE)
  if not f then return "glass" end
  local v = (f:read("*l") or ""):gsub("%s+", "")
  f:close()
  return v ~= "" and v or "glass"
end
local function write_default(name)
  os.execute("mkdir -p " .. q(STATE_DIR))
  local f = io.open(DEFAULT_FILE, "w")
  if f then f:write(name, "\n") f:close() end
end

-- Re-entrant: tear down the previous registration first.
if type(_G.omaglass) == "table" and type(_G.omaglass.unload) == "function" then
  pcall(_G.omaglass.unload)
end
local live = { rules = {}, keys = {}, subs = {} }
local function rule(spec) live.rules[#live.rules + 1] = hl.window_rule(spec) end

-- ---- rules: plain Hyprland ---------------------------------------------------
local background = opt("background", true)
if opt("terminals", true) then
  -- Compositor-opaque with "override" (a plain "1 1" loses the race against
  -- Omarchy's default-opacity rule at map); the glass shows through the
  -- terminal's own alpha. Class match: reliable at map time, tag-chained
  -- rules are not.
  rule({ match = { class = TERMINALS }, tag = "-default-opacity", opacity = "1 override 1 override" })
  rule({ match = { class = TERMINALS }, tag = "+hyprglass_enabled" })
  if background then rule({ match = { class = TERMINALS }, tag = "+hyprglass_background" }) end
end
if opt("chilled", true) then
  rule({ match = { tag = "chillmode" }, tag = "+hyprglass_enabled" })
  if background then rule({ match = { tag = "chillmode" }, tag = "+hyprglass_background" }) end
end
rule({ match = { fullscreen = true }, tag = "+hyprglass_disabled" })

-- Shadows: "contact" (default) — the focused window keeps the theme's
-- shadow, an unfocused one casts the contact shadow only where it lies over
-- another window; "theme" — Hyprland's shadows as the theme sets them, no
-- contact shadow; "flat" — none at all.
local SHADOWS        = tostring(opt("shadows", "contact"))
local SHADOW_RANGE   = math.max(1, tonumber(opt("shadow_range", 28)) or 28)
local SHADOW_PERCENT = math.max(0, math.min(100, tonumber(opt("shadow_strength", 28)) or 28))
if SHADOWS == "contact" then
  -- One shadow system on every theme: the focused window gets a GLOW — wide
  -- (2.5x the contact range), soft falloff, moderate strength (1.5x the
  -- contact shadow's, capped) — inactive windows none (the contact shadow
  -- says when one covers another). Themes and look engines that set their
  -- own are overridden here; pick "theme" to keep theirs.
  hl.config({ decoration = { shadow = {
    enabled = true,
    range = math.floor(SHADOW_RANGE * 2.5 + 0.5),
    render_power = 2,
    offset = "0 6",
    scale = 0.98,
    color = string.format("rgba(000000%02x)", math.floor(math.min(85, SHADOW_PERCENT * 1.5) * 255 / 100 + 0.5)),
    color_inactive = "rgba(00000000)",
  } } })
elseif SHADOWS == "flat" then
  hl.config({ decoration = { shadow = { enabled = false } } })
end

-- ---- the material (hyprglass) ----------------------------------------------
local function theme_mode() -- "light" | "dark" from the current theme's colors.toml
  local f = io.open(os.getenv("HOME") .. "/.local/state/omarchy/current/theme/colors.toml")
  if not f then return "dark" end
  local mode = "dark"
  for line in f:lines() do
    local m = line:match('^mode%s*=%s*"(%a+)"')
    if m then mode = m break end
  end
  f:close()
  return mode
end

local HAVE_PLUGIN = hl.plugin and hl.plugin.hyprglass and true or false
if HAVE_PLUGIN then
  local hg = hl.plugin.hyprglass
  local shadow   = SHADOWS == "contact" and SHADOW_RANGE or 0
  local strength = SHADOW_PERCENT
  hg.config({
    enabled = false, -- whitelist: the rules above opt windows in
    manage_window_blur = true,
    overlap_shadow = {
      range = shadow,
      color = math.floor(strength * 255 / 100 + 0.5), -- 0x000000AA
      clip = opt("shadow_clip", true) and 1 or 0,
    },
  })

  if not _G.glass_theme_owned then
    -- Light themes: neutral, the frost is the wallpaper as it is. Dark
    -- themes: smoked glass — the sampled wallpaper is dimmed and slightly
    -- desaturated, bright areas dimmed further (adaptive_dim), and a black
    -- tint laid over it, so a dark translucent terminal reads as glass
    -- instead of a muddy grey over a bright wallpaper.
    local light = { brightness = 1.0, contrast = 1.0, saturation = 1.0, vibrancy = 0.0, adaptive_boost = 0.05, adaptive_dim = 0.05 }
    local dark  = { brightness = 0.88, contrast = 1.0, saturation = 0.9, vibrancy = 0.05, adaptive_boost = 0.0, adaptive_dim = 0.18, tint_color = 0x00000038 }
    local function preset(name, blur_strength, blur_iterations)
      hg.preset(name, {
        glass_opacity = 1.0, blur_strength = blur_strength, blur_iterations = blur_iterations,
        refraction_strength = 0.0, chromatic_aberration = 0.0, fresnel_strength = 0.0,
        specular_strength = 0.0, lens_distortion = 0.0, edge_thickness = 0.0,
        light = light, dark = dark,
      })
    end
    hg.config({
      default_theme = theme_mode(),
      default_preset = "clear",
      tint_color = 0x00000000,
      light = light,
      dark = dark,
      layers = { enabled = opt("layers", true) and true or false },
    })
    if opt("layers", true) then
      for _, ns in ipairs({ "omarchy-bar", "omarchy-menu", "omarchy-image-selector", "omarchy-emojis",
                            "omarchy-clipboard", "omarchy-keyboard-panel", "omarchy-osd", "omarchy-notifications" }) do
        hg.layer(ns, { preset = "clear", mask_threshold = 0.05 })
      end
    end
    preset("clear", FROST, FROST >= 8 and 5 or 2) -- the frost
    preset("sheer", 0.5, 1)                        -- the lightest frost
    preset("crystal", 0.0, 1)                      -- no blur: a copy of the wallpaper
  end
end

-- ---- terminal alpha (foot.ini) --------------------------------------------
-- Applied on every load, so a theme switch (Omarchy reloads after it) puts
-- the configured alphas back; a theme shipping its own alpha wins (helper).
do
  local light = tonumber(opt("alpha_light", 0)) or 0
  local dark  = tonumber(opt("alpha_dark", 0)) or 0
  if HELPER ~= "" and (light > 0 or dark > 0) then
    hl.exec_cmd(q(HELPER) .. " apply " .. math.floor(light) .. " " .. math.floor(dark))
  end
end

-- ---- per-window looks ---------------------------------------------------------
-- glass:  on | off | <hyprglass preset name>
-- blur:   while glass is off: 1 = no Hyprland blur either, 0 = keep it
-- alpha:  terminal alpha percent, or "reset" (foot.ini's value)
-- bg:     sample the wallpaper only
local LOOK = {
  glass    = { glass = "on",            blur = 0, alpha = "reset", bg = true },
  milky    = { glass = "on",            blur = 0, alpha = MILKY,   bg = true },
  solid    = { glass = "off",           blur = 0, alpha = 100,     bg = false },
  clear    = { glass = "crystal",       blur = 0, alpha = CLEAR,   bg = true },
  native   = { glass = "off",           blur = 0, alpha = "reset", bg = false },
  sheer    = { glass = "sheer",         blur = 0, alpha = "reset", bg = true },
  contrast = { glass = "high_contrast", blur = 0, alpha = "reset", bg = true },
  block    = { glass = "glass",         blur = 0, alpha = "reset", bg = true },
}
local READ_CYCLE = { "milky", "solid" }
local LOOK_CYCLE = { "clear", "sheer", "native", "contrast", "block" }
local PRESETS    = { "sheer", "high_contrast", "glass", "crystal" }

local function tags_of(w)
  local t = w and w.tags
  if type(t) ~= "table" then return {} end
  return t
end
local function look_of(w)
  local t = tags_of(w)
  for i = 1, #t do
    local n = tostring(t[i]):match("^glass_(%a+)$")
    if n and LOOK[n] then return n end
  end
  return "glass"
end
local function tag(w, t) hl.dispatch(hl.dsp.window.tag({ tag = t, window = "address:" .. w.address })) end
local function prop(w, p, v) hl.dispatch(hl.dsp.window.set_prop({ prop = p, value = v, window = "address:" .. w.address })) end
local function foot_alpha(w, value)
  if HELPER == "" or w.class ~= "foot" then return end
  hl.exec_cmd(q(HELPER) .. " alpha " .. tostring(w.pid) .. " " .. tostring(value))
end
local function notify(text)
  if not NOTIFY then return end
  hl.exec_cmd("notify-send -e -t 1200 'Glass' " .. q(text))
end

local function set_look(w, name, quiet)
  local state = look_of(w)
  local prev, next = LOOK[state] or LOOK.glass, LOOK[name] or LOOK.glass
  if state ~= "glass" then tag(w, "-glass_" .. state) end
  for i = 1, #PRESETS do tag(w, "-hyprglass_preset_" .. PRESETS[i]) end
  tag(w, "-hyprglass_background")
  if next.glass == "off" then
    -- hyprglass withdraws its noblur when disabled; give it a frame before
    -- we set the property ourselves, or its withdrawal clobbers ours.
    tag(w, "+hyprglass_disabled")
    local blur = next.blur
    hl.timer(function() pcall(prop, w, "no_blur", blur) end, { timeout = 100, type = "oneshot" })
  else
    -- no_blur is hyprglass's while it is on: hand it back only on the way
    -- out of an off look, before hyprglass is re-enabled and claims it.
    if prev.glass == "off" then prop(w, "no_blur", 0) end
    tag(w, "-hyprglass_disabled")
    if next.glass ~= "on" then tag(w, "+hyprglass_preset_" .. next.glass) end
  end
  if next.bg then tag(w, "+hyprglass_background") end
  foot_alpha(w, next.alpha)
  if name ~= "glass" then tag(w, "+glass_" .. name) end
  if not quiet then notify(name .. " — " .. tostring(w.title or w.class or ""):sub(1, 40)) end
  pcall(function() hl.dispatch(hl.dsp.event("omaglass " .. tostring(w.address) .. " " .. name)) end)
end

local function window_from(selector)
  if selector == nil then return hl.get_active_window() end
  if type(selector) == "table" then return selector end
  return hl.get_window(tostring(selector):match("^address:") and selector or ("address:" .. tostring(selector)))
end
local function cycle(list, selector)
  local w = window_from(selector)
  if not w then return end
  local state = look_of(w)
  local nxt = list[1]
  for i = 1, #list do
    if list[i] == state then nxt = list[i + 1] or "glass" break end
  end
  set_look(w, nxt)
  return nxt
end

-- A glass window: tagged by the rules above (or by a look), or a terminal
-- by class — the rule tags can lag a freshly mapped window by a frame.
local function is_glass(w)
  if not w or not w.mapped then return false end
  local t = tags_of(w)
  for i = 1, #t do
    local n = tostring(t[i]):gsub("%*$", "")
    if n == "hyprglass_enabled" or n:match("^glass_") then return true end
  end
  return type(w.class) == "string" and w.class:match(TERMINALS) ~= nil
end

local function set_all(name)
  name = LOOK[name] and name or "glass"
  local wins = hl.get_windows()
  local n = 0
  if type(wins) == "table" then
    for i = 1, #wins do
      if is_glass(wins[i]) then
        pcall(set_look, wins[i], name, true)
        n = n + 1
      end
    end
  end
  write_default(name)
  notify(string.format("%s — all windows (%d), and new ones", name, n))
  pcall(function() hl.dispatch(hl.dsp.event("omaglass all " .. name)) end)
  return n
end

-- New glass windows start in the default look. A short delay lets the
-- map-time rules land first (is_glass needs the tags or the class).
live.subs[#live.subs + 1] = hl.on("window.open", function(w)
  local d = read_default()
  if d == "glass" or not w then return end
  local address = w.address
  hl.timer(function()
    local ww = hl.get_window("address:" .. address)
    if ww and is_glass(ww) and look_of(ww) == "glass" then pcall(set_look, ww, d, true) end
  end, { timeout = 150, type = "oneshot" })
end)

if KEY_READ ~= "" then
  o.bind(KEY_READ, "Glass: readability (window)", function() cycle(READ_CYCLE) end)
  live.keys[#live.keys + 1] = KEY_READ
end
if KEY_LOOKS ~= "" then
  o.bind(KEY_LOOKS, "Glass: looks (window)", function() cycle(LOOK_CYCLE) end)
  live.keys[#live.keys + 1] = KEY_LOOKS
end

local function unload()
  for i = 1, #live.rules do pcall(function() live.rules[i]:set_enabled(false) end) end
  for i = 1, #live.keys do pcall(hl.unbind, live.keys[i]) end
  for i = 1, #live.subs do pcall(function() live.subs[i]:remove() end) end
  live = { rules = {}, keys = {}, subs = {} }
  _G.omaglass = nil
end

_G.omaglass = {
  version = "0.1.0",
  generation = OPTS.generation,
  have_plugin = HAVE_PLUGIN,
  shadows = SHADOWS, -- "contact" | "theme" | "flat"; Omachill leaves shadows alone when "flat"
  look = function(selector) local w = window_from(selector) return w and look_of(w) or nil end,
  set = function(name, selector) local w = window_from(selector) if w then set_look(w, name) end end,
  cycle_readability = function(selector) return cycle(READ_CYCLE, selector) end,
  cycle_looks = function(selector) return cycle(LOOK_CYCLE, selector) end,
  set_all = set_all,
  default = read_default,
  unload = unload,
}
