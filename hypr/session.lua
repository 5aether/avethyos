-- Image-owned session environment and startup. Updated with the system.
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
-- GE-Proton 11+ supplies its own Windows named-pipe RPC bridge.
hl.env("PROTON_DISCORD_BRIDGE", os.getenv("PROTON_DISCORD_BRIDGE") or "1")

local home = assert(os.getenv("HOME"))
local config_home = os.getenv("XDG_CONFIG_HOME")
if not config_home or config_home:sub(1, 1) ~= "/" then config_home = home .. "/.config" end
local data_home = os.getenv("XDG_DATA_HOME")
if not data_home or data_home:sub(1, 1) ~= "/" then data_home = home .. "/.local/share" end
local data_dirs = os.getenv("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
for _, directory in ipairs({ data_home .. "/flatpak/exports/share", "/var/lib/flatpak/exports/share" }) do
    if not (":" .. data_dirs .. ":"):find(":" .. directory .. ":", 1, true) then
        data_dirs = directory .. ":" .. data_dirs
    end
end
hl.env("XDG_DATA_DIRS", data_dirs)
local runtime_dir = os.getenv("XDG_RUNTIME_DIR")
if runtime_dir and runtime_dir ~= "" then
    hl.env("DBUS_SESSION_BUS_ADDRESS", "unix:path=" .. runtime_dir .. "/bus")
    -- Steam's supported container settings also expose the stable RPC proxies.
    local rpc_dir = runtime_dir .. "/discord-rpc"
    hl.env("BRIDGE_RPC_PATH", rpc_dir)
    local shared = os.getenv("PRESSURE_VESSEL_FILESYSTEMS_RO") or ""
    if not (":" .. shared .. ":"):find(":" .. rpc_dir .. ":", 1, true) then
        shared = shared == "" and rpc_dir or shared .. ":" .. rpc_dir
    end
    hl.env("PRESSURE_VESSEL_FILESYSTEMS_RO", shared)
end

local function shell_quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end
hl.on("hyprland.start", function()
    hl.exec_cmd("bash /usr/libexec/avethyos-hyprland-session")
    -- Idle and lock appearance are user preferences, seeded once at login.
    hl.exec_cmd("hypridle -c " .. shell_quote(config_home .. "/hypr/hypridle.conf"))
end)
