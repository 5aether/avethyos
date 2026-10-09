// Pure application searching and ordering helpers. Kept free of Qt APIs so
// the launcher behaviour can be covered by the regular Node test suite.

function text(value) {
    return value === undefined || value === null ? "" : String(value);
}

function appKey(app) {
    return text(app.id || app.desktopId || app.name);
}

function appName(app) {
    return text(app.name).toLocaleLowerCase();
}

function compareNames(a, b) {
    return appName(a).localeCompare(appName(b), undefined, {
        sensitivity: "base",
        numeric: true
    });
}

function usageFor(app, usage) {
    return Number(usage[appKey(app)]) || 0;
}

function searchableText(app, desktopText) {
    // Qt exposes the common fields; the index adds every value from the file,
    // including localized strings, MIME types and custom desktop-entry keys.
    const key = appKey(app).replace(/\.desktop$/, "");
    return [app.name, app.genericName, app.comment, app.description,
        app.keywords, app.categories, app.id, app.desktopId, app.execString,
        app.command, app.workingDirectory, app.startupClass, app.icon,
        desktopText[key]].map(text).join("\n").toLocaleLowerCase();
}

function rankApps(apps, query, usage, desktopText) {
    const list = Array.prototype.slice.call(apps || []);
    const counts = usage || {};
    const needle = text(query).trim().toLocaleLowerCase();
    const terms = needle.split(/\s+/).filter(Boolean);
    const metadata = desktopText || {};

    // Each word can occur anywhere in the metadata. Keep launch-history order.
    return list.filter(function(app) {
        if (!terms.length)
            return true;
        const haystack = searchableText(app, metadata);
        return terms.every(function(term) { return haystack.includes(term); });
    }).sort(function(a, b) {
        return usageFor(b, counts) - usageFor(a, counts)
            || compareNames(a, b);
    });
}
