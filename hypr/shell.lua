-- Image-owned Quickshell integration. Updated with the system.
hl.layer_rule({
    name         = "qs-bar-blur",
    match        = { namespace = "^quickshell:(bar|popup-backdrop|clipboard)$" },
    blur         = true,
    -- Blur the actual windows behind the translucent shell surfaces.
    xray         = false,
    blur_popups  = true,
    ignore_alpha = 0.2,
})
-- QML owns popup motion; the compositor must not add another fade or slide.
hl.layer_rule({
    name    = "qs-popups-qml-motion",
    match   = { namespace = "^quickshell:(bar|osd|nowplaying|mediaplayer|mediaplayer-dismiss|popup-backdrop|launcher|clipboard|polkit|notifications|clock|clock-dismiss|controlcenter|controlcenter-dismiss|tooltip)$" },
    no_anim = true,
})
hl.layer_rule({
    name         = "qs-launcher-blur",
    match        = { namespace = "^quickshell:launcher$" },
    blur         = true,
    xray         = false,
    blur_popups  = true,
    ignore_alpha = 0.2,
})
hl.layer_rule({
    name         = "qs-polkit-blur",
    match        = { namespace = "^quickshell:polkit$" },
    blur         = true,
    xray         = false,
    blur_popups  = true,
    ignore_alpha = 0.2,
})

local mainMod = "SUPER"

for _, key in ipairs({ { mainMod .. "_L", "left" }, { mainMod .. "_R", "right" } }) do
    hl.bind(key[1], hl.dsp.event("quickshell-workspace-apps," .. key[2] .. ",1"), {
        non_consuming = true, ignore_mods = true, transparent = true,
        submap_universal = true,
    })
    hl.bind(key[1], hl.dsp.event("quickshell-workspace-apps," .. key[2] .. ",0"), {
        release = true, non_consuming = true, ignore_mods = true,
        transparent = true, submap_universal = true,
    })
end
hl.on("config.reloaded", function()
    -- The standalone config verifier has no compositor/event socket. Sending
    -- events is only meaningful once an actual monitor/session exists.
    if hl.get_active_monitor() then
        hl.dispatch(hl.dsp.event("quickshell-workspace-apps,reset"))
    end
end)
