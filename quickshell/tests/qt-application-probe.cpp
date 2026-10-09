// Test-only generic plugin: inspect a real Qt application on a private bus.
// This library is never copied into the installed desktop theme.
#include <QApplication>
#include <QDir>
#include <QFile>
#include <QGenericPlugin>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPixmap>
#include <QStyle>
#include <QTimer>
#include <QWidget>

class ApplicationProbe final : public QGenericPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QGenericPluginFactoryInterface" FILE "qt-application-probe.json")
public:
    QObject *create(const QString &key, const QString &) override
    {
        if (key != "quickshell-test-probe") return nullptr;
        auto driver = new QObject;
        QTimer::singleShot(1800, driver, [] {
            auto app = qobject_cast<QApplication *>(QCoreApplication::instance());
            const QString output = qEnvironmentVariable("QUICKSHELL_THEME_CHECK_DIR");
            if (!app || output.isEmpty()) return;
            QDir().mkpath(output);
            QJsonObject report {
                {"style", app->style()->objectName()},
                {"highlight", app->palette().color(QPalette::Highlight).name()},
                {"kde_scheme", app->property("KDE_COLOR_SCHEME_PATH").toString()}
            };
            QJsonArray windows;
            for (QWidget *window : QApplication::topLevelWidgets()) {
                if (!window->isVisible() || window->windowType() != Qt::Window) continue;
                const QString name = QString::number(windows.size());
                const QImage image = window->grab().toImage();
                image.save(output + "/window-" + name + ".png");
                QJsonArray layers;
                for (QWidget *widget : window->findChildren<QWidget *>()) {
                    const QString type = widget->metaObject()->className();
                    if (!widget->isVisible() || (!type.contains("View") && !type.contains("Dolphin")
                        && !type.contains("ItemList") && !type.contains("Panel"))) continue;
                    const QPoint position = widget->mapTo(window, QPoint());
                    layers.append(QJsonObject {
                        {"class", type}, {"name", widget->objectName()},
                        {"auto_fill", widget->autoFillBackground()},
                        {"x", position.x()}, {"y", position.y()},
                        {"width", widget->width()}, {"height", widget->height()}
                    });
                }
                windows.append(QJsonObject {
                    {"class", QString(window->metaObject()->className())},
                    {"translucent", window->testAttribute(Qt::WA_TranslucentBackground)},
                    {"layers", layers}
                });
            }
            report["windows"] = windows;
            QFile file(output + "/report.json");
            if (file.open(QIODevice::WriteOnly)) file.write(QJsonDocument(report).toJson());
            app->quit();
        });
        return driver;
    }
};
#include "qt-application-probe.moc"
