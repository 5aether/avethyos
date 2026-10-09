// Pure JS string formatting helpers (no Qt dependency) so they can be unit tested.

/** Left-pads a number below 10 with a single leading zero. */
function pad2(n) {
    return n < 10 ? "0" + n : "" + n;
}

/**
 * Formats a Date as a local 24-hour clock (HH:mm).
 * @param {Date} date
 * @returns {string}
 */
function formatTime(date) {
    return pad2(date.getHours()) + ":" + pad2(date.getMinutes());
}
