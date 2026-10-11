// Cursor coordinates and monitor positions use Hyprland's scaled layout.
// Quarter-turn transforms swap the native mode dimensions before scaling.
function screenAt(point, screens, monitors) {
    if (!point || !Number.isFinite(point.x) || !Number.isFinite(point.y))
        return null;
    for (const screen of screens) {
        const monitor = monitors.find(item => item.name === screen.name);
        const scale = monitor ? Math.max(0.01, monitor.scale || 1) : 1;
        const rotated = monitor && Number(monitor.lastIpcObject?.transform || 0) % 2 !== 0;
        const width = monitor ? (rotated ? monitor.height : monitor.width) / scale : screen.width;
        const height = monitor ? (rotated ? monitor.width : monitor.height) / scale : screen.height;
        const x = monitor ? monitor.x : screen.x;
        const y = monitor ? monitor.y : screen.y;
        if (point.x >= x && point.x < x + width && point.y >= y && point.y < y + height)
            return screen;
    }
    return null;
}
