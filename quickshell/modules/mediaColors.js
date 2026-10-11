// Lift a cover's accent toward white until small labels remain readable over
// the brightest possible artwork after the media backdrop's dark tint.
function luminance(rgb) {
    return rgb.map(function(channel) {
        return channel <= 0.04045 ? channel / 12.92
            : Math.pow((channel + 0.055) / 1.055, 2.4);
    }).reduce(function(total, channel, index) {
        return total + channel * [0.2126, 0.7152, 0.0722][index];
    }, 0);
}

function readableAccent(value) {
    const hex = String(value || "").replace(/^#/, "");
    const rgb = /^[0-9a-f]{6}$/i.test(hex)
        ? [0, 2, 4].map(function(index) { return parseInt(hex.slice(index, index + 2), 16) / 255; })
        : [0.9, 0.88, 0.93];
    const backdrop = luminance([0.33, 0.32, 0.35]);
    const target = 4.5 * (backdrop + 0.05) - 0.05;
    let low = 0;
    let high = 1;
    if (luminance(rgb) < target) {
        for (let i = 0; i < 20; ++i) {
            const amount = (low + high) / 2;
            const candidate = rgb.map(function(channel) { return channel + (1 - channel) * amount; });
            if (luminance(candidate) < target)
                low = amount;
            else
                high = amount;
        }
    } else {
        high = 0;
    }
    return "#" + rgb.map(function(channel) {
        // Round upward so quantization cannot fall below the contrast target.
        return Math.ceil(255 * (channel + (1 - channel) * high)).toString(16).padStart(2, "0");
    }).join("");
}

if (typeof module !== "undefined")
    module.exports = { luminance, readableAccent };
