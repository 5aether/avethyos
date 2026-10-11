-- Image-owned commands for user keybindings. Updated with the system.
-- Use require("/usr/share/avethyos/hypr/commands.lua") in a user Lua module.
local shell_path = "/usr/share/avethyos/quickshell"
local ipc = "qs -p " .. shell_path .. " ipc call "

return {
    shell_path = shell_path,
    appmenu = ipc .. "applauncher toggle",
    applauncher = ipc .. "applauncher toggle",
    control_center = ipc .. "controlcenter toggle",
    notifications = ipc .. "clock toggle",
    clipboard = ipc .. "clipboard toggle",
    screenshot = "hyprshot -m region --freeze",
    restart_shell = "python3 " .. shell_path .. "/scripts/restart-shell.py --daemonize",
}
