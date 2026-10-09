#pragma once
#include <QProxyStyle>

class AvethyStyle final : public QProxyStyle {
public:
    AvethyStyle();
    QPalette standardPalette() const override;
    void polish(QPalette &palette) override;
    void polish(QApplication *app) override;
    void polish(QWidget *widget) override;
    void unpolish(QWidget *widget) override;
    void drawPrimitive(PrimitiveElement element, const QStyleOption *option,
                       QPainter *painter, const QWidget *widget = nullptr) const override;
    void drawControl(ControlElement element, const QStyleOption *option,
                     QPainter *painter, const QWidget *widget = nullptr) const override;
    void drawComplexControl(ComplexControl control, const QStyleOptionComplex *option,
                            QPainter *painter, const QWidget *widget = nullptr) const override;
    int pixelMetric(PixelMetric metric, const QStyleOption *option = nullptr,
                    const QWidget *widget = nullptr) const override;
    int styleHint(StyleHint hint, const QStyleOption *option = nullptr,
                  const QWidget *widget = nullptr, QStyleHintReturn *returnData = nullptr) const override;
    QSize sizeFromContents(ContentsType type, const QStyleOption *option,
                           const QSize &size, const QWidget *widget = nullptr) const override;
};
