pragma Singleton

import QtQuick

// Attached glass belongs to the bar's native surface so live compositor blur
// samples the desktop once, before either the bar or its popups are tinted.
QtObject {
    id: service

    property var bars: []
    property var backgrounds: []

    function registerBar(bar): void {
        if (bar && bars.indexOf(bar) === -1)
            bars = bars.concat([bar]);
    }

    function unregisterBar(bar): void {
        bars = bars.filter(candidate => candidate !== bar);
    }

    function registerBackground(background): void {
        if (background && backgrounds.indexOf(background) === -1)
            backgrounds = backgrounds.concat([background]);
    }

    function unregisterBackground(background): void {
        backgrounds = backgrounds.filter(candidate => candidate !== background);
    }

    function barFor(screen) {
        if (!screen)
            return null;
        for (const bar of bars) {
            if (bar && (bar.screen === screen || bar.screen?.name === screen.name))
                return bar;
        }
        return null;
    }

    function backgroundsForScreen(screen) {
        return backgrounds.filter(background => background
            && background.active && background.integrated
            && (background.screen === screen || background.screen?.name === screen?.name));
    }

    function heightFor(screen): real {
        let height = Theme.barHeight;
        for (const background of backgroundsForScreen(screen)) {
            const window = background.sourceWindow;
            // Native popup surfaces reserve animation space already. Reuse
            // that space instead of resizing the bar on every motion frame.
            const popupHeight = Math.max(window?.height ?? 0,
                window?.implicitHeight ?? 0, background.y + background.height);
            height = Math.max(height, background.globalY + popupHeight);
        }
        return Math.ceil(height);
    }
}
