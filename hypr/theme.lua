-- Image-owned theme environment and initial palette. Updated with the system.
-- Wallpaper-generated colors are loaded from $XDG_STATE_HOME/avethyos/hypr.
local home = assert(os.getenv("HOME"))
local config_home = os.getenv("XDG_CONFIG_HOME")
if not config_home or config_home:sub(1, 1) ~= "/" then config_home = home .. "/.config" end
local shell_path = "/usr/share/avethyos/quickshell"
local plugins = shell_path .. "/native/qt-theme/build-qt6/plugins:"
    .. shell_path .. "/native/qt-theme/build-qt5/plugins"
local qml_path = shell_path .. "/native/qt-theme/qml"
hl.env("QT_GUI_GTK_JSON", config_home .. "/qt6ct/gtk3-palette.json")
hl.env("QT_QPA_PLATFORMTHEME", "gtk3")
hl.env("GTK_THEME", "Avethy-dark")
hl.env("GTK2_RC_FILES", home .. "/.gtkrc-2.0")
hl.env("QT_STYLE_OVERRIDE", "Avethy")
hl.env("QT_PLUGIN_PATH", plugins)
hl.env("QT_QPA_GENERIC_PLUGINS", "avethy-theme")
hl.env("AVETHY_QT_THEME", config_home .. "/avethy/palette.json")
hl.env("QT_QUICK_CONTROLS_STYLE", "Avethy")
hl.env("QT_QUICK_CONTROLS_STYLE_PATH", qml_path)
hl.env("QT_QUICK_CONTROLS_FALLBACK_STYLE", "Fusion")
hl.env("QT_QUICK_CONTROLS_CONF", config_home .. "/avethy/qtquickcontrols2.conf")
hl.env("QML_IMPORT_PATH", qml_path)
hl.env("QML2_IMPORT_PATH", qml_path)
hl.config({
    general = {
        col = {
            active_border = "rgba(ffb59bff)",
            inactive_border = "rgba(5d4035aa)",
        },
    },
})
