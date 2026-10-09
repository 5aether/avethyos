#include "palette.h"
#include <QGenericPlugin>

class AvethyThemePlugin final : public QGenericPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QGenericPluginFactoryInterface" FILE "theme.json")
public:
    QObject *create(const QString &key, const QString &) override
    {
        if (key.compare("avethy-theme", Qt::CaseInsensitive) != 0
            && key.compare("quickshell-theme", Qt::CaseInsensitive) != 0)
            return nullptr;
        AvethyTheme::Palette::instance();
        // Qt owns the generic driver independently of application children.
        // The palette controller remains owned by the application itself.
        return new QObject;
    }
};
#include "themeplugin.moc"
