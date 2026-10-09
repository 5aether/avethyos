pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

QtObject {
    id: root

    // History is owned by NotificationStore, which keeps it on disk
    // permanently. The server's tracked list is not used: it does not survive a
    // restart, and keepOnReload only covers reloads, not reboots.
    readonly property var notifications: NotificationStore.entries
    readonly property int historyCount: NotificationStore.entries.length

    // Visible toasts, newest first. Only a few are shown at once so a burst of
    // notifications does not bury the screen; the rest stay in the history.
    property var toastQueue: []
    // Keep notification-owned image provider handles alive while their toast
    // is visible. image://qsimage URLs cease to exist with the Notification.
    property var liveNotifications: ({})
    readonly property var visibleToasts: Config.doNotDisturb
        ? [] : toastQueue.slice(0, Config.maxVisibleToasts)

    property Connections dndConnection: Connections {
        target: Config
        function onDoNotDisturbChanged() {
            if (Config.doNotDisturb)
                root.clearToasts();
        }
    }

    // A notification carries two visual fields: `appIcon` (the sending
    // application's icon) and `image` (an image representing the notification
    // itself). For chat, mail, contacts, calls, and similar notifications,
    // `image` is commonly the sender's avatar. That notification image takes
    // priority universally; `appIcon` remains the fallback when it is absent
    // or cannot be loaded.
    // Both helpers are shared by the toast and the history list so the rule
    // cannot drift between them.
    function primaryAppIcon(entry) {
        return entry ? String(entry.appIcon || "") : "";
    }

    function primaryImage(entry) {
        return entry ? String(entry.image || "") : "";
    }

    // A toast is a plain JS snapshot, never the live QObject: keeping QObject
    // pointers inside a `property var` array loses entries and turns a
    // destroyed notification into a dangling reference.
    function pushToast(notification) {
        if (Config.doNotDisturb) {
            notification.tracked = false;
            return;
        }
        notification.tracked = true;
        const snapshot = {
            id: String(notification.id),
            summary: notification.summary ? String(notification.summary) : "",
            body: notification.body ? String(notification.body) : "",
            appIcon: notification.appIcon ? String(notification.appIcon) : "",
            image: notification.image ? String(notification.image) : ""
        };
        const retained = Object.assign({}, liveNotifications);
        retained[snapshot.id] = notification;
        liveNotifications = retained;
        // Newest first, dropping any earlier copy of the same notification.
        const next = [snapshot];
        for (let i = 0; i < toastQueue.length; ++i) {
            const item = toastQueue[i];
            if (item && item.id !== snapshot.id)
                next.push(item);
        }
        toastQueue = next;
    }

    function removeToast(id) {
        const key = String(id);
        toastQueue = toastQueue.filter(item => item && item.id !== key);
        const retained = Object.assign({}, liveNotifications);
        const notification = retained[key];
        if (notification)
            notification.tracked = false;
        delete retained[key];
        liveNotifications = retained;
    }

    function clearToasts() {
        const retained = liveNotifications;
        for (const key in retained) {
            if (retained[key])
                retained[key].tracked = false;
        }
        liveNotifications = ({});
        toastQueue = [];
    }

    // Only the user clearing the list removes anything from the history; a
    // toast ageing out never touches it.
    function dismissAll() {
        clearToasts();
        NotificationStore.clear();
    }

    function removeFromHistory(id) {
        NotificationStore.remove(id);
    }

    // Nothing is restored into the server: the on-disk history is authoritative,
    // so a reboot or restart still shows every old notification, and no stale
    // toast is ever replayed.
    property NotificationServer notificationServer: NotificationServer {
        id: notifServer
        bodySupported: true
        bodyMarkupSupported: false
        imageSupported: true
        bodyImagesSupported: true
        actionsSupported: true
        persistenceSupported: false
        keepOnReload: false

        onNotification: notification => {
            // Written to the permanent history first, so it is never lost even
            // if the shell dies before the toast finishes animating.
            NotificationStore.add(
                notification.id,
                notification.summary,
                notification.body,
                notification.appName,
                notification.appIcon,
                notification.image,
                Date.now()
            );
            root.pushToast(notification);
        }
    }
}
