# Omaglass

Glass terminals on every Omarchy theme. A terminal becomes a frosted pane that
shows the **wallpaper** through it and never the windows beneath; an unfocused
pane lying over another window gets a slight contact shadow; and every window
has a few looks you can cycle from the bar or a key.

Companion to [Omachill](https://github.com/nocstah/omachill): chill is about
layout, glass is about material. Each works without the other.

## Install

Two steps. The material is drawn by the [hyprglass](https://github.com/hyprnux/hyprglass)
Hyprland plugin, which has to be compiled against your Hyprland — `hyprpm`
does that. Until the two features this plugin relies on are merged upstream,
use the fork:

```bash
hyprpm add https://github.com/nocstah/hyprglass && hyprpm enable hyprglass
omarchy plugin add https://github.com/nocstah/omaglass --enable
```

Without hyprglass the plugin still applies its window rules; there is just no
glass, and the bar tells you once.

On enable the plugin writes a small loader, `~/.config/hypr/omaglass.lua`,
and appends one guarded, marked line to `~/.config/hypr/hyprland.lua` that
runs it. Hyprland rebuilds its Lua state from the config on every reload, so
that is what keeps the engine alive across reloads and theme switches. Disabling
the plugin removes the loader again.

## What it does

- **Terminals are glass**: foot, ghostty, alacritty and kitty windows get the
  frost, held compositor-opaque so the glass shows through the terminal's own
  background alpha. The plugin sets that alpha (per light/dark theme) in
  foot's config and repaints open windows; a theme shipping its own alpha wins.
- **Wallpaper only**: the glass is sampled from a snapshot of the desktop
  taken before any window is drawn, so windows underneath never show through.
- **Shadows**, three modes. *Contact* (default): an unfocused window that lies
  over another window casts a slight shadow there, cut at the underlying
  window's outline, so the part resting on the desktop casts nothing; a lone
  inactive window casts none; the focused window keeps the theme's shadow.
  *Theme*: Hyprland's shadows exactly as the theme sets them, no contact
  shadow. *Flat*: no shadows at all.
- **Chilled windows** (Omachill) are glass too; fullscreen windows never are.
- **The bar and menus** get the same frost.
- **Looks per window, or for all**: click the bar widget for a dropdown that
  lists every look with a one-line description and marks the current one.
  "Window" applies to the focused window; "All" applies to every glass window
  and makes it the default for windows opened from then on. The same looks
  are on two keys:

  | key | cycle |
  | --- | --- |
  | `SUPER + CTRL + G` | glass → milky → solid |
  | `SUPER + CTRL + ALT + G` | glass → clear → sheer → native → contrast → block |

  milky and solid trade transparency for readability; clear is the wallpaper
  sharp through the pane; sheer the lightest frost; native Hyprland's own blur;
  contrast and block are hyprglass's built-in presets.

Every option — which windows, the frost, the shadows, the alphas, the keys — is
a widget setting stored in `~/.config/omarchy/shell.json`. The shadows mode
is switchable from the dropdown; Omarchy has no editor for the others yet, so
they are set from the command line, for example:

```bash
omarchy bar set io.github.nocstah.omaglass shadows flat      # contact | theme | flat
omarchy bar set io.github.nocstah.omaglass frost 12          # lighter default frost
omarchy bar set io.github.nocstah.omaglass alphaLight 60     # terminal alpha on light themes
omarchy bar set io.github.nocstah.omaglass background false  # sample the live frame again
```

The keys are the ones in `manifest.json`.

## Themes

Nothing per theme is needed: light or dark is read from the active theme, and
Omarchy's reload after a theme switch re-applies everything. A theme that
tunes its own glass sets `_G.glass_theme_owned = true` in its `hyprland.lua`
and the plugin leaves the material to it, applying only the rules.

## Scripting

```bash
hyprctl eval 'omaglass.cycle_looks()'            # focused window
hyprctl eval 'omaglass.set("clear", "0x...")'    # a window by address
hyprctl eval 'omaglass.look()'                   # current look
hyprctl eval 'omaglass.set_all("sheer")'         # every glass window, and the default for new ones
```

Every change emits `custom>>omaglass <address> <look>` on the event socket.

## License

MIT
