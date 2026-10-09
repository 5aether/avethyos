#pragma once
#include <QColor>
#include <QFileSystemWatcher>
#include <QJsonObject>
#include <QObject>
#include <QPalette>
#include <QTimer>

namespace AvethyTheme {
class Palette final : public QObject {
    Q_OBJECT
public:
    static Palette *instance();
    explicit Palette(QObject *parent = nullptr);
    QPalette palette() const;
    QColor color(const char *role) const;
    QColor glass() const;
    QColor floating() const;
    QString schemePath() const;
    QString path() const;
    void reload();
    void enforce();
signals:
    void changed();
protected:
    bool eventFilter(QObject *object, QEvent *event) override;
private:
    QJsonObject m_data;
    QFileSystemWatcher m_watcher;
    QTimer m_applyTimer;
    bool m_applying = false;
};
}
