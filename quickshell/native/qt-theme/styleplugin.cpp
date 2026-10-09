#include "style.h"
#include <QStylePlugin>

class AvethyStylePlugin final : public QStylePlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QStyleFactoryInterface" FILE "style.json")
public:
    QStyle *create(const QString &key) override
    {
        return key.compare("Avethy", Qt::CaseInsensitive) == 0 ? new AvethyStyle : nullptr;
    }
};
#include "styleplugin.moc"
