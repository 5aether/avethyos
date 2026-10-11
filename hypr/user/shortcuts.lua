-- Your shortcuts. This file is preserved across system upgrades.
-- Saving a loaded Lua file reloads Hyprland automatically; hyprctl reload
-- also reloads all files manually. Keys use strings such as "SUPER + R".
--
-- Shell command definitions live in the read-only system file below. Requiring
-- it picks up owner updates without replacing your key choices. These are Lua
-- command strings for hl.dsp.exec_cmd(), not process environment variables:
-- commands.shell_path: installed Quickshell config directory (read-only).
-- commands.appmenu: toggle the application launcher.
-- commands.applauncher: alias of appmenu; either name opens the same launcher.
-- commands.control_center: toggle the system controls/settings panel.
-- commands.notifications: toggle the clock and notification history panel.
-- commands.clipboard: toggle clipboard history.
-- commands.screenshot: select a frozen screen region and save a screenshot.
-- commands.restart_shell: restart the image-managed shell safely.
--
-- Define another binding with a command, for example:
-- hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd(commands.applauncher))
-- hl.bind("SUPER + L", hl.dsp.exec_cmd("loginctl lock-session"))
-- The Super-key press/release hooks used by Quickshell are system-managed.
local commands = require("/usr/share/avethyos/hypr/commands.lua")

-- terminal: your preferred terminal; change this string to choose another app.
local terminal = "kitty"
-- fileManager: your preferred file browser; change this string freely.
local fileManager = "nautilus"
-- mainMod: the modifier for the shortcuts below; SUPER is the Windows key.
local mainMod = "SUPER"
-- appmenu / control_center / notifications / clipboard / screenshot /
-- restart_shell are local aliases of the read-only commands documented above.
local appmenu = commands.appmenu
local control_center = commands.control_center
local notifications = commands.notifications
local clipboard = commands.clipboard
local screenshot = commands.screenshot
local restart_shell = commands.restart_shell

hl.bind(mainMod .. " + A", hl.dsp.exec_cmd(restart_shell))

hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + Space", hl.dsp.window.float({ action = "toggle" }))

hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd(control_center))
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd(notifications))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd(clipboard))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(appmenu))

hl.bind("Print", hl.dsp.exec_cmd(screenshot))

hl.bind(mainMod .. " + S", hl.dsp.layout("togglesplit"))

hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key,             hl.dsp.focus({ workspace = i}))
    hl.bind(mainMod .. " + CTRL + " .. key,     hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })

hl.bind(mainMod .. " + Page_Up",   hl.dsp.exec_cmd("playerctl next"),     { locked = true })
hl.bind(mainMod .. " + Page_Down", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

hl.bind(mainMod .. " + Home",      hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind(mainMod .. " + Delete",    hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
