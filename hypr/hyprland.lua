-- Avethyos owns this entry point and its system modules in the bootc image.
-- Edit the files in $XDG_CONFIG_HOME/hypr (usually ~/.config/hypr) instead.
-- Hyprland's require() watches each loaded Lua file for automatic reloads.
local system_dir = "/usr/share/avethyos/hypr"
local home = assert(os.getenv("HOME"))
local function xdg_dir(name, fallback)
    local value = os.getenv(name)
    return value and value:sub(1, 1) == "/" and value or home .. fallback
end
local user_dir = xdg_dir("XDG_CONFIG_HOME", "/.config") .. "/hypr"
local state_dir = xdg_dir("XDG_STATE_HOME", "/.local/state") .. "/avethyos/hypr"

local function exists(path)
    local file = io.open(path, "r")
    if file then file:close() end
    return file ~= nil
end

require(system_dir .. "/session.lua")

-- Seeded once by the session initializer, then exclusively owned by the user.
-- Image templates are a fallback when a user deliberately removes a file.
for _, name in ipairs({ "monitors", "input", "appearance", "shortcuts", "window-rules", "custom" }) do
    local path = user_dir .. "/" .. name .. ".lua"
    require(exists(path) and path or system_dir .. "/user/" .. name .. ".lua")
end

require(system_dir .. "/theme.lua")

-- The generated wallpaper palette is mutable state, not a user config file.
local palette = state_dir .. "/theme.lua"
if exists(palette) then require(palette) end

-- Always load shell integration from the image, including after a user error.
require(system_dir .. "/shell.lua")
