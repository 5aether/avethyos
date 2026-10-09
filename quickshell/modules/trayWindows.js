// Tray items do not expose a window handle. Compare their application identity
// with window classes, never document titles (which can mention other apps).
function appKey(value) {
    return String(value || "").toLowerCase()
        .replace(/\.desktop$/, "")
        .replace(/^appindicator[-_]/, "")
        .replace(/[-_]\d+$/, "")
        .replace(/[^a-z0-9]/g, "");
}

function matchScore(item, client) {
    if (client.mapped === false || !client.address)
        return 0;
    const names = [item.id, item.title, item.tooltipTitle].map(appKey).filter(Boolean);
    const classes = [client.class, client.initialClass].filter(Boolean);
    let score = 0;
    for (const cls of classes) {
        const full = appKey(cls);
        const short = appKey(cls.split(".").pop());
        for (const name of names) {
            if (name === full)
                score = Math.max(score, 2);
            else if (name === short)
                score = Math.max(score, 1);
        }
    }
    return score;
}

function findWindow(item, clients) {
    let best = null;
    let bestScore = 0;
    let bestHistory = Infinity;
    for (const client of clients) {
        const score = matchScore(item, client);
        const history = client.focusHistoryID >= 0 ? client.focusHistoryID : Infinity;
        if (score > bestScore || (score > 0 && score === bestScore && history < bestHistory)) {
            best = client;
            bestScore = score;
            bestHistory = history;
        }
    }
    return best;
}
