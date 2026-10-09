#include "palette.h"
#include <QApplication>
#include <QDir>
#include <QEvent>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QGraphicsView>
#include <QJsonArray>
#include <QJsonDocument>
#include <QPainter>
#include <QStyle>
#include <QStyleFactory>
#include <QWidget>

namespace AvethyTheme {
Palette *Palette::instance()
{
    // Both style and generic plugins use this source. Share one controller via
    // the application instead of installing two competing event filters.
    if (qApp) {
        if (QObject *value = qApp->property("_quickshellPalette").value<QObject *>())
            return static_cast<Palette *>(value);
    }
    static Palette *value = new Palette(QCoreApplication::instance());
    if (qApp)
        qApp->setProperty("_quickshellPalette", QVariant::fromValue(static_cast<QObject *>(value)));
    return value;
}

Palette::Palette(QObject *parent) : QObject(parent)
{
    // QApplication copies QT_STYLE_OVERRIDE into the Qt Quick style override
    // after generic plugins initialize. Migrate our old name here as well as
    // in the session config, so apps launched from existing terminals work.
    for (const char *key : {"QT_STYLE_OVERRIDE", "QT_QUICK_CONTROLS_STYLE"}) {
        const QString previous = qEnvironmentVariable(key);
        if (previous.compare("Quickshell", Qt::CaseInsensitive) == 0
            || previous.compare("QuickshellDesktop", Qt::CaseInsensitive) == 0)
            qputenv(key, "Avethy");
    }
#if QT_VERSION_MAJOR == 5
    // Qt 5 discovers custom Controls styles separately from QML imports.
    // Older terminals predate this export; recover it from their import paths.
    if (qEnvironmentVariableIsEmpty("QT_QUICK_CONTROLS_STYLE_PATH")) {
        for (const char *key : {"QML2_IMPORT_PATH", "QML_IMPORT_PATH"}) {
            for (const QString &directory : qEnvironmentVariable(key).split(QDir::listSeparator())) {
                if (QFileInfo::exists(directory + "/Avethy/Menu.qml")) {
                    qputenv("QT_QUICK_CONTROLS_STYLE_PATH", directory.toUtf8());
                    break;
                }
            }
            if (!qEnvironmentVariableIsEmpty("QT_QUICK_CONTROLS_STYLE_PATH"))
                break;
        }
    }
#endif
    m_applyTimer.setSingleShot(true);
    connect(&m_applyTimer, &QTimer::timeout, this, &Palette::enforce);
    const auto update = [this] { reload(); };
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, update);
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, update);
    const QString directory = QFileInfo(path()).absolutePath();
    if (QDir(directory).exists())
        m_watcher.addPath(directory); // Covers atomic rename, including new files.
    reload();
    if (qApp)
        qApp->installEventFilter(this);
}

QString Palette::path() const
{
    const QString override = qEnvironmentVariable("AVETHY_QT_THEME",
                                                 qEnvironmentVariable("QUICKSHELL_QT_THEME"));
    return override.isEmpty() ? QDir::homePath() + "/.config/avethy/palette.json" : override;
}

QString Palette::schemePath() const
{
    return m_data.value("kde_scheme").toString();
}

QColor Palette::color(const char *role) const
{
    QColor value(m_data.value("roles").toObject().value(QLatin1String(role)).toString());
    if (value.isValid())
        return value;
    // Only used before the first palette is generated, never as a hue substitute.
    return QColor(QString::fromLatin1(role).startsWith(QLatin1String("on_")) ? "#e2e2e2" : "#181818");
}

QColor Palette::glass() const
{
    QColor value = color("background");
    value.setAlphaF(m_data.value("mode").toString() == "light" ? .94 : .88);
    return value;
}

QColor Palette::floating() const
{
    QColor value = color("surface_container_high");
    value.setAlphaF(m_data.value("mode").toString() == "light" ? .97 : .94);
    return value;
}

QPalette Palette::palette() const
{
    QPalette value;
    const QJsonObject groups = m_data.value("palette").toObject();
    for (const auto group : {QPalette::Active, QPalette::Inactive, QPalette::Disabled}) {
        const QString name = group == QPalette::Active ? "Active"
            : group == QPalette::Inactive ? "Inactive" : "Disabled";
        const QJsonArray colors = groups.value(name).toArray();
        for (int role = 0; role < colors.size() && role < QPalette::NColorRoles; ++role) {
            if (role == QPalette::NoRole)
                continue;
            const QColor color(colors[role].toString());
            if (color.isValid())
                value.setColor(group, static_cast<QPalette::ColorRole>(role), color);
        }
    }
    return value;
}

void Palette::reload()
{
    QFile file(path());
    if (!file.open(QIODevice::ReadOnly))
        return;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    const QJsonObject data = document.object();
    if (data.value("roles").toObject().isEmpty() || data.value("palette").toObject().isEmpty())
        return; // Keep the complete previous palette on invalid/truncated writes.
    if (!m_watcher.files().contains(path()))
        m_watcher.addPath(path());
    if (m_data == data)
        return;
    m_data = data;
    // KColorSchemeManager checks this property during its constructor. Set it
    // synchronously, before KDE can select its non-Plasma Breeze fallback.
    if (qApp)
        qApp->setProperty("KDE_COLOR_SCHEME_PATH", schemePath());
    m_applyTimer.start(0);
    emit changed();
}

void Palette::enforce()
{
    if (m_applying || m_data.isEmpty())
        return;
    m_applying = true;
    if (auto app = qobject_cast<QApplication *>(QCoreApplication::instance())) {
        if (app->style()->objectName().compare("avethy", Qt::CaseInsensitive) != 0) {
            if (QStyle *style = QStyleFactory::create("Avethy")) {
                app->setStyle(style);
                // Qt can wrap the native style in QStyleSheetStyle. Mark the
                // wrapper too so it does not cause an endless re-polish loop.
                app->style()->setObjectName("avethy");
            }
        }
        if (app->palette() != palette())
            app->setPalette(palette());
        // QWidget palettes can have explicit resolve masks, independently of
        // the application palette. Reconcile those overrides as well.
        for (QWidget *widget : QApplication::allWidgets()) {
            QPalette desired = palette();
            desired.setCurrentColorGroup(widget->palette().currentColorGroup());
            if (widget->palette() != desired)
                widget->setPalette(desired);
            widget->update();
        }
        // Dolphin resets its nested graphics viewport during palette changes.
        // Apply this after all palette callbacks have run, keeping one window
        // tint underneath empty and populated file views.
        for (QWidget *widget : QApplication::allWidgets()) {
            if (widget->inherits("KItemListContainerViewport")) {
                if (auto view = qobject_cast<QGraphicsView *>(widget)) {
                    view->setBackgroundBrush(Qt::NoBrush);
                    view->viewport()->setAutoFillBackground(false);
                    view->viewport()->setAttribute(Qt::WA_OpaquePaintEvent, false);
                }
            }
        }
    } else if (auto app = qobject_cast<QGuiApplication *>(QCoreApplication::instance())) {
        if (app->palette() != palette())
            app->setPalette(palette());
    }
    if (qApp)
        qApp->setProperty("KDE_COLOR_SCHEME_PATH", schemePath());
    m_applying = false;
}

bool Palette::eventFilter(QObject *object, QEvent *event)
{
    if (event->type() == QEvent::Paint && !m_data.isEmpty()) {
        if (auto widget = qobject_cast<QWidget *>(object)) {
            if (widget->isWindow() && widget->testAttribute(Qt::WA_TranslucentBackground)
                && !widget->inherits("QMenu") && !widget->inherits("QTipLabel")) {
                // WA_TranslucentBackground suppresses QWidget's default window
                // fill. Paint the one tinted layer in the paint event instead.
                QPainter painter(widget);
                painter.setCompositionMode(QPainter::CompositionMode_Source);
                painter.fillRect(widget->rect(), widget->windowType() == Qt::Popup ? floating() : glass());
            }
        }
    }
    if (!m_applying && (event->type() == QEvent::ApplicationPaletteChange
                       || event->type() == QEvent::PaletteChange
                       || event->type() == QEvent::StyleChange))
        m_applyTimer.start(0);
    return QObject::eventFilter(object, event);
}
}
