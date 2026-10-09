#include <QApplication>
#include <QColor>
#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QGuiApplication>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QPalette>
#include <QQmlApplicationEngine>
#include <QQuickItem>
#include <QQuickItemGrabResult>
#include <QQuickWindow>
#include <QSaveFile>
#include <QTemporaryDir>
#include <QTimer>
#include <cmath>
#include <cstdio>
#include <memory>

namespace {
void settle(int milliseconds = 80)
{
    QEventLoop loop;
    QTimer::singleShot(milliseconds, &loop, &QEventLoop::quit);
    loop.exec();
}
QObject *part(QObject *control, const char *name)
{
    return control ? control->property(name).value<QObject *>() : nullptr;
}
bool colorMatches(QObject *object, const QColor &expected)
{
    if (!object) return false;
    const QColor actual = object->property("color").value<QColor>();
    return std::abs(actual.red() - expected.red()) <= 1
        && std::abs(actual.green() - expected.green()) <= 1
        && std::abs(actual.blue() - expected.blue()) <= 1
        && std::abs(actual.alpha() - expected.alpha()) <= 1;
}
void mouseMove(QQuickWindow *window, QQuickItem *item)
{
    const QPointF point = item->mapToScene(QPointF(item->width() / 2, item->height() / 2));
    QMouseEvent event(QEvent::MouseMove, point, window->mapToGlobal(point.toPoint()),
                      Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    QCoreApplication::sendEvent(window, &event);
    settle();
}
void key(QQuickWindow *window, int value)
{
    QKeyEvent press(QEvent::KeyPress, value, Qt::NoModifier);
    QCoreApplication::sendEvent(window, &press);
    QKeyEvent release(QEvent::KeyRelease, value, Qt::NoModifier);
    QCoreApplication::sendEvent(window, &release);
    settle();
}
QImage renderedWindow(QQuickWindow *window)
{
    QImage result = window->grabWindow();
#if QT_VERSION_MAJOR == 5
    // Qt 5's offscreen software renderer can omit the window backing image.
    // Grabbing its full content item still exercises the real scene graph.
    if (result.isNull()) {
        const auto grab = window->contentItem()->grabToImage();
        if (grab) {
            QEventLoop loop;
            QObject::connect(grab.data(), &QQuickItemGrabResult::ready, &loop, &QEventLoop::quit);
            QTimer::singleShot(1000, &loop, &QEventLoop::quit);
            loop.exec();
            result = grab->image();
        }
    }
#endif
    return result;
}
}

int main(int argc, char **argv)
{
    bool widgets = false;
    bool versioned = false;
    for (int index = 1; index < argc; ++index) {
        widgets |= QByteArray(argv[index]) == "--widgets";
        versioned |= QByteArray(argv[index]) == "--versioned";
    }
    if (qEnvironmentVariableIsEmpty("QT_QUICK_BACKEND")) qputenv("QT_QUICK_BACKEND", "software");
    QTemporaryDir themeDirectory;
    const QString originalTheme = qEnvironmentVariable("AVETHY_QT_THEME",
        qEnvironmentVariable("QUICKSHELL_QT_THEME", QDir::homePath() + "/.config/avethy/palette.json"));
    const QString testTheme = themeDirectory.filePath("palette.json");
    if (!themeDirectory.isValid() || !QFile::copy(originalTheme, testTheme)) {
        std::fprintf(stderr, "FAIL: cannot create isolated palette fixture\n"); return 1;
    }
    qputenv("AVETHY_QT_THEME", testTheme.toUtf8());
    std::unique_ptr<QGuiApplication> application;
    if (widgets) application = std::make_unique<QApplication>(argc, argv);
    else application = std::make_unique<QGuiApplication>(argc, argv);
    QGuiApplication &app = *application;
    QQmlApplicationEngine engine;
    const QUrl fixture = QUrl::fromLocalFile(QStringLiteral(QUICKSHELL_QUICK_TEST));
    if (versioned) {
        QFile file(fixture.toLocalFile());
        if (!file.open(QIODevice::ReadOnly)) return 1;
        QByteArray source = file.readAll();
        const QByteArray version = QT_VERSION_MAJOR == 5 ? QByteArray("2.15")
            : QByteArray::number(QT_VERSION_MAJOR) + "." + QByteArray::number(QT_VERSION_MINOR);
        source.replace("import QtQuick.Controls\n", "import QtQuick.Controls " + version + "\n");
        engine.loadData(source, fixture);
    } else engine.load(fixture);
    if (engine.rootObjects().isEmpty()) return 1;
    QTimer::singleShot(300, &app, [&] {
        const auto fail = [&](const char *message) {
            std::fprintf(stderr, "FAIL: %s\n", message);
            app.exit(1);
        };
        const QColor primary = app.palette().color(QPalette::Highlight);
        const QColor onPrimary = app.palette().color(QPalette::HighlightedText);
        const QColor text = app.palette().color(QPalette::WindowText);
        const QColor button = app.palette().color(QPalette::Button);
        const QColor windowColor = app.palette().color(QPalette::Window);
        const bool dark = windowColor.redF() + windowColor.greenF() + windowColor.blueF() < 1.5;
        QColor floating = button;
        floating.setAlphaF(dark ? .94 : .97);
        const QColor disabled = QColor::fromRgbF(text.redF() * .55 + button.redF() * .45,
                                               text.greenF() * .55 + button.greenF() * .45,
                                               text.blueF() * .55 + button.blueF() * .45);
        QObject *root = engine.rootObjects().first();
        QQuickWindow *window = qobject_cast<QQuickWindow *>(root);
        for (const QString &name : {"button", "tool", "checkbox", "radio", "switch", "slider", "selected"}) {
            QObject *control = root->findChild<QObject *>(name);
            const char *property = name == "checkbox" || name == "radio" || name == "switch" ? "indicator"
                : name == "slider" ? "handle" : "background";
            QObject *background = part(control, property);
            if (!colorMatches(background, primary)) {
                fail(qPrintable(QStringLiteral("Qt Quick %1 does not match shared primary").arg(name))); return;
            }
            if (name == "button" && background->property("radius").toInt() != 8) {
                fail("custom Qt Quick style did not load"); return;
            }
        }
        QMetaObject::invokeMethod(root, "showMenu");
        settle();
        QObject *menu = root->findChild<QObject *>("menu");
        auto *menuBackground = qobject_cast<QQuickItem *>(part(menu, "background"));
        auto *open = root->findChild<QQuickItem *>("menuOpen");
        auto *checked = root->findChild<QQuickItem *>("menuChecked");
        auto *unavailable = root->findChild<QQuickItem *>("menuDisabled");
        if (!window || !menu || !menu->property("visible").toBool() || !menuBackground
            || !menuBackground->isVisible() || !open || !checked || !unavailable) {
            fail("menu did not open with visible content"); return;
        }
        if (!colorMatches(menuBackground, floating)) {
            fail("opened menu background does not match the shared floating surface"); return;
        }
        if (menu->property("height").toDouble() < 120 || open->width() < 150
            || checked->mapToScene(QPointF()).y() < open->mapToScene(QPointF()).y() + open->height() - 1) {
            fail("menu rows overlap or the menu is undersized"); return;
        }
        QObject *separator = root->findChild<QObject *>("menuSeparator");
        if (!separator || separator->property("height").toDouble() < 1
            || part(separator, "contentItem")->property("height").toDouble() != 1) {
            fail("menu separator has incorrect geometry"); return;
        }
        mouseMove(window, open);
        if (!open->property("hovered").toBool() || !colorMatches(part(open, "background"), primary)
            || !colorMatches(part(open, "contentItem"), onPrimary)) {
            fail("pointer menu selection does not use primary and on-primary"); return;
        }
        key(window, Qt::Key_Down);
        if (menu->property("currentIndex").toInt() != 1 || !colorMatches(part(checked, "background"), primary)
            || !colorMatches(part(checked, "contentItem"), onPrimary)
            || !colorMatches(part(checked, "indicator"), onPrimary)) {
            fail("keyboard menu selection or checked indicator has incorrect colors"); return;
        }
        mouseMove(window, unavailable);
        if (!colorMatches(part(unavailable, "contentItem"), disabled)
            || part(unavailable, "background")->property("color").value<QColor>().alpha() != 0) {
            fail("disabled menu row has incorrect colors"); return;
        }
        auto *more = root->findChild<QQuickItem *>("menuMore");
        auto *arrow = qobject_cast<QQuickItem *>(part(more, "arrow"));
        if (!more || !arrow || !arrow->isVisible() || arrow->x() < 0
            || arrow->x() + arrow->width() > more->width()
            || arrow->y() < 0 || arrow->y() + arrow->height() > more->height()) {
            fail("submenu arrow is missing or misplaced"); return;
        }
        const QImage menuImage = renderedWindow(window);
        if (menuImage.isNull()) {
            fail("opened menu could not be rendered"); return;
        }
        const qreal scale = menuImage.devicePixelRatio();
        const QPointF menuFill = menuBackground->mapToScene(QPointF(menuBackground->width() / 2, 3));
        const QColor painted = menuImage.pixelColor(QPoint(qRound(menuFill.x() * scale), qRound(menuFill.y() * scale)));
        const double windowAlpha = dark ? .88 : .94;
        const double surfaceAlpha = dark ? .94 : .97;
        const double composedAlpha = surfaceAlpha + windowAlpha * (1 - surfaceAlpha);
        const auto channel = [&](double foreground, double behind) {
            return (foreground * surfaceAlpha + behind * windowAlpha * (1 - surfaceAlpha)) / composedAlpha;
        };
        const QColor composed = QColor::fromRgbF(channel(button.redF(), windowColor.redF()),
                                                 channel(button.greenF(), windowColor.greenF()),
                                                 channel(button.blueF(), windowColor.blueF()), composedAlpha);
        if (std::abs(painted.red() - composed.red()) > 2 || std::abs(painted.green() - composed.green()) > 2
            || std::abs(painted.blue() - composed.blue()) > 2 || std::abs(painted.alpha() - composed.alpha()) > 2) {
            std::fprintf(stderr, "FAIL: menu render fill RGBA %d,%d,%d,%d expected %d,%d,%d,%d\n",
                         painted.red(), painted.green(), painted.blue(), painted.alpha(),
                         composed.red(), composed.green(), composed.blue(), composed.alpha());
            app.exit(1); return;
        }
        QObject *combo = root->findChild<QObject *>("combo");
        QObject *editor = part(combo, "contentItem");
        if (!editor || !editor->setProperty("text", "Edited wallpaper")
            || combo->property("editText").toString() != QStringLiteral("Edited wallpaper")) {
            fail("editable combo box does not forward edited text"); return;
        }
        QMetaObject::invokeMethod(root, "showTooltip");
        settle();
        QObject *tooltip = root->findChild<QObject *>("tooltip");
        auto *anchor = root->findChild<QQuickItem *>("tooltipAnchor");
        auto *tooltipBackground = qobject_cast<QQuickItem *>(part(tooltip, "background"));
        if (!tooltip || !tooltip->property("visible").toBool() || !anchor || !tooltipBackground
            || !tooltipBackground->isVisible() || !colorMatches(tooltipBackground, floating)
            || !colorMatches(part(tooltip, "contentItem"), text)) {
            fail("opened tooltip does not follow the shared floating surface and text"); return;
        }
        const QRectF tooltipRect(tooltipBackground->mapToScene(QPointF()), tooltipBackground->size());
        const QRectF anchorRect(anchor->mapToScene(QPointF()), anchor->size());
        if (tooltipRect.intersects(anchorRect) || tooltipRect.top() < 0 || tooltipRect.left() < 0
            || tooltipRect.right() > window->width() || tooltipRect.bottom() > window->height()
            || std::abs(tooltipRect.center().x() - anchorRect.center().x()) > 1) {
            fail("tooltip overlaps its anchor or is misplaced"); return;
        }
        QFile paletteFile(testTheme);
        if (!paletteFile.open(QIODevice::ReadOnly)) { fail("cannot read live palette fixture"); return; }
        QJsonObject data = QJsonDocument::fromJson(paletteFile.readAll()).object();
        paletteFile.close();
        const QColor nextPrimary("#5473df");
        const QColor nextText("#fff5dc");
        QJsonObject roles = data.value("roles").toObject();
        roles.insert("primary", nextPrimary.name());
        roles.insert("on_primary", nextText.name());
        data.insert("roles", roles);
        QJsonObject groups = data.value("palette").toObject();
        for (const QString &group : {"Active", "Inactive", "Disabled"}) {
            QJsonArray colors = groups.value(group).toArray();
            colors[12] = nextPrimary.name(QColor::HexArgb);
            colors[13] = nextText.name(QColor::HexArgb);
            if (colors.size() > 21) colors[21] = nextPrimary.name(QColor::HexArgb);
            groups.insert(group, colors);
        }
        data.insert("palette", groups);
        QSaveFile update(testTheme);
        if (!update.open(QIODevice::WriteOnly) || update.write(QJsonDocument(data).toJson()) < 0 || !update.commit()) {
            fail("cannot publish live palette fixture"); return;
        }
        settle(180);
        QMetaObject::invokeMethod(root, "showMenu");
        settle();
        mouseMove(window, open);
        if (!colorMatches(part(open, "background"), nextPrimary)
            || !colorMatches(part(open, "contentItem"), nextText)) {
            fail("live palette update did not refresh menu background and foreground"); return;
        }
        std::printf("PASS: %s with %s Qt Quick imports, shared controls, opened menus, pointer/keyboard states, tooltip layout and live palette updates\n",
                    widgets ? "QApplication" : "QGuiApplication", versioned ? "versioned" : "unversioned");
        app.exit(0);
    });
    return app.exec();
}
