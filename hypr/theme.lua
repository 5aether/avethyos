-- Managed by the Avethy wallpaper palette.
local home = assert(os.getenv("HOME"))
hl.env("QT_GUI_GTK_JSON", home .. "/.config/qt6ct/gtk3-palette.json")
hl.env("QT_QPA_PLATFORMTHEME", "gtk3")
hl.env("GTK_THEME", "Avethy-dark")
hl.env("GTK2_RC_FILES", home .. "/.gtkrc-2.0")
hl.env("QT_STYLE_OVERRIDE", "Avethy")
hl.env("QT_PLUGIN_PATH", home .. "/.local/lib/avethy/qt-plugins")
hl.env("QT_QPA_GENERIC_PLUGINS", "avethy-theme")
hl.env("AVETHY_QT_THEME", home .. "/.config/avethy/palette.json")
hl.env("QT_QUICK_CONTROLS_STYLE", "Avethy")
hl.env("QT_QUICK_CONTROLS_STYLE_PATH", home .. "/.local/lib/avethy/qt-plugins/qml")
hl.env("QT_QUICK_CONTROLS_FALLBACK_STYLE", "Fusion")
hl.env("QT_QUICK_CONTROLS_CONF", home .. "/.config/avethy/qtquickcontrols2.conf")
hl.env("QML_IMPORT_PATH", home .. "/.local/lib/avethy/qt-plugins/qml")
hl.env("QML2_IMPORT_PATH", home .. "/.local/lib/avethy/qt-plugins/qml")
hl.config({
    general = {
        col = {
            active_border = "rgba(ffb59bff)",
            inactive_border = "rgba(5d4035aa)",
        },
    },
})
