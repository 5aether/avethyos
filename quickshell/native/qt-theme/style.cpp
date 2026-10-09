#include "style.h"
#include "palette.h"
#include <QAbstractItemView>
#include <QApplication>
#include <QDialog>
#include <QGraphicsView>
#include <QMenu>
#include <QPainter>
#include <QPainterPath>
#include <QProgressBar>
#include <QStyleOption>
#include <QToolBar>
#include <QWidget>

using AvethyTheme::Palette;
namespace {
QColor translucent(QColor color, qreal opacity) { color.setAlphaF(opacity); return color; }
QColor foreground(const QStyleOption *option, bool selected = false)
{
    return Palette::instance()->palette().color(
        option->state & QStyle::State_Enabled ? QPalette::Active : QPalette::Disabled,
        selected ? QPalette::HighlightedText : QPalette::WindowText);
}
void rounded(QPainter *painter, QRectF rect, QColor fill, QColor stroke = {}, qreal radius = 8)
{
    painter->setRenderHint(QPainter::Antialiasing);
    painter->setPen(stroke.isValid() ? QPen(stroke, 1) : QPen(Qt::NoPen));
    painter->setBrush(fill);
    painter->drawRoundedRect(rect.adjusted(.5, .5, -.5, -.5), radius, radius);
}
void chevron(QPainter *painter, QPointF center, QColor color, Qt::ArrowType direction)
{
    painter->save();
    painter->setRenderHint(QPainter::Antialiasing);
    painter->translate(center);
    painter->rotate(direction == Qt::UpArrow ? 180 : direction == Qt::LeftArrow ? 90
                     : direction == Qt::RightArrow ? -90 : 0);
    painter->setPen(QPen(color, 1.6, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
    painter->setBrush(Qt::NoBrush);
    QPainterPath path;
    path.moveTo(-3, -1.5); path.lineTo(0, 1.5); path.lineTo(3, -1.5);
    painter->drawPath(path);
    painter->restore();
}
bool accentButton(const QStyleOption *option)
{
    const auto button = qstyleoption_cast<const QStyleOptionButton *>(option);
    return option->state & QStyle::State_On || (button && button->features & QStyleOptionButton::DefaultButton);
}
}

AvethyStyle::AvethyStyle() : QProxyStyle("Fusion") { setObjectName("avethy"); }
QPalette AvethyStyle::standardPalette() const { return Palette::instance()->palette(); }
void AvethyStyle::polish(QPalette &palette) { palette = standardPalette(); }
void AvethyStyle::polish(QApplication *app)
{
    QProxyStyle::polish(app);
    app->setProperty("KDE_COLOR_SCHEME_PATH", Palette::instance()->schemePath());
}
void AvethyStyle::polish(QWidget *widget)
{
    QProxyStyle::polish(widget);
    widget->setAttribute(Qt::WA_Hover);
    if (widget->isWindow()) {
        // Translucency affects only the painted background; text/icons stay opaque.
        // Native surfaces must receive this attribute before their first show.
        widget->setAttribute(Qt::WA_TranslucentBackground);
        widget->setAttribute(Qt::WA_StyledBackground, !widget->inherits("QMenu"));
        widget->setAutoFillBackground(false);
    }
    if (auto view = qobject_cast<QAbstractItemView *>(widget))
        view->viewport()->setAutoFillBackground(false);
    if (widget->inherits("KItemListContainer") || widget->inherits("DolphinView")) {
        widget->setAutoFillBackground(false);
        if (auto area = qobject_cast<QAbstractScrollArea *>(widget))
            area->viewport()->setAutoFillBackground(false);
    }
    if (widget->inherits("KItemListContainerViewport")) {
        auto view = qobject_cast<QGraphicsView *>(widget);
        if (view) {
            view->setBackgroundBrush(Qt::NoBrush);
            view->viewport()->setAutoFillBackground(false);
            view->viewport()->setAttribute(Qt::WA_OpaquePaintEvent, false);
        }
    }
}
void AvethyStyle::unpolish(QWidget *widget) { QProxyStyle::unpolish(widget); }

void AvethyStyle::drawPrimitive(PrimitiveElement element, const QStyleOption *option,
                                    QPainter *painter, const QWidget *widget) const
{
    auto theme = Palette::instance();
    painter->save();
    const bool enabled = option->state & State_Enabled;
    const bool hovered = enabled && option->state & State_MouseOver;
    const bool checked = option->state & (State_On | State_NoChange);
    const QColor border = translucent(theme->color("outline"), .24);
    const QRectF rect = option->rect;
    switch (element) {
    case PE_Widget:
        if (widget && widget->isWindow()) {
            rounded(painter, rect, qobject_cast<const QMenu *>(widget) ? theme->floating() : theme->glass(), {},
                    qobject_cast<const QMenu *>(widget) ? 12 : 0);
            break;
        }
        painter->restore(); QProxyStyle::drawPrimitive(element, option, painter, widget); return;
    case PE_PanelButtonCommand: {
        const bool accent = accentButton(option);
        const auto button = qstyleoption_cast<const QStyleOptionButton *>(option);
        if (!accent && button && button->features & QStyleOptionButton::Flat) {
            if (hovered || option->state & State_Sunken)
                rounded(painter, rect, translucent(theme->color("on_surface"), .08));
            break;
        }
        QColor fill = accent ? theme->palette().color(enabled ? QPalette::Active : QPalette::Disabled, QPalette::Highlight)
            : theme->color(hovered ? "surface_container_highest" : "surface_container_high");
        if (!accent && option->state & State_Sunken)
            fill = theme->color("surface_container_highest");
        rounded(painter, rect, fill, accent ? QColor() : border);
        break;
    }
    case PE_PanelButtonTool:
        if (checked)
            rounded(painter, rect, theme->palette().color(enabled ? QPalette::Active : QPalette::Disabled, QPalette::Highlight));
        else if (hovered || option->state & State_Sunken)
            rounded(painter, rect, translucent(theme->color("on_surface"), .08));
        break;
    case PE_PanelLineEdit:
        rounded(painter, rect, theme->color("surface_container_low"),
                option->state & State_HasFocus ? theme->color("primary") : border);
        break;
    case PE_FrameLineEdit:
        rounded(painter, rect, Qt::transparent, option->state & State_HasFocus ? theme->color("primary") : border);
        break;
    case PE_FrameFocusRect:
        rounded(painter, rect.adjusted(1, 1, -1, -1), Qt::transparent,
                translucent(theme->color("primary"), .7), 6);
        break;
    case PE_PanelMenu:
        rounded(painter, rect, theme->floating(), {}, 12);
        break;
    case PE_FrameMenu:
        rounded(painter, rect, Qt::transparent, border, 12);
        break;
    case PE_PanelTipLabel:
        rounded(painter, rect, theme->floating(), border, 8);
        break;
    case PE_PanelToolBar:
        painter->fillRect(rect, translucent(theme->color("surface_container"), .45));
        break;
    case PE_IndicatorToolBarSeparator: case PE_IndicatorToolBarHandle:
    case PE_FrameButtonBevel: case PE_FrameButtonTool:
        break;
    case PE_FrameGroupBox: case PE_FrameDockWidget: case PE_FrameTabWidget:
        rounded(painter, rect, Qt::transparent, border, 8);
        break;
    case PE_PanelItemViewItem: {
        const auto item = qstyleoption_cast<const QStyleOptionViewItem *>(option);
        if (option->state & State_Selected)
            rounded(painter, rect, theme->color("primary"), {}, 7);
        else if (hovered)
            rounded(painter, rect, translucent(theme->color("on_surface"), .08), {}, 7);
        else if (item && item->features & QStyleOptionViewItem::Alternate)
            painter->fillRect(rect, translucent(theme->color("surface_container"), .35));
        break;
    }
    case PE_IndicatorCheckBox: case PE_IndicatorRadioButton: {
        const QRectF box = QRectF(rect.center().x()-8.5, rect.center().y()-8.5, 17, 17);
        const QColor fill = checked ? theme->palette().color(enabled ? QPalette::Active : QPalette::Disabled, QPalette::Highlight)
            : theme->color(hovered ? "surface_container_highest" : "surface_container_low");
        rounded(painter, box, fill, checked ? QColor() : border, element == PE_IndicatorRadioButton ? 8.5 : 5);
        if (checked) {
            painter->setPen(QPen(theme->color("on_primary"), 2, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
            if (element == PE_IndicatorRadioButton) {
                painter->setBrush(theme->color("on_primary"));
                painter->setPen(Qt::NoPen);
                painter->drawEllipse(box.center(), 3.2, 3.2);
            } else if (option->state & State_NoChange) {
                painter->drawLine(box.center() + QPointF(-4, 0), box.center() + QPointF(4, 0));
            } else {
                QPainterPath tick;
                tick.moveTo(box.center()+QPointF(-4, 0)); tick.lineTo(box.center()+QPointF(-1, 3));
                tick.lineTo(box.center()+QPointF(4, -3)); painter->drawPath(tick);
            }
        }
        break;
    }
    case PE_IndicatorArrowDown: case PE_IndicatorArrowUp:
    case PE_IndicatorArrowLeft: case PE_IndicatorArrowRight:
        chevron(painter, rect.center(), foreground(option), element == PE_IndicatorArrowUp ? Qt::UpArrow
                : element == PE_IndicatorArrowLeft ? Qt::LeftArrow
                : element == PE_IndicatorArrowRight ? Qt::RightArrow : Qt::DownArrow);
        break;
    default:
        painter->restore(); QProxyStyle::drawPrimitive(element, option, painter, widget); return;
    }
    painter->restore();
}

void AvethyStyle::drawControl(ControlElement element, const QStyleOption *option,
                                  QPainter *painter, const QWidget *widget) const
{
    auto theme = Palette::instance();
    if (element == CE_MenuEmptyArea)
        return; // The popup panel already paints the complete palette surface.
    if (element == CE_PushButtonLabel) {
        if (auto button = qstyleoption_cast<const QStyleOptionButton *>(option)) {
            QStyleOptionButton value(*button);
            value.palette = standardPalette();
            if (accentButton(option))
                for (auto group : {QPalette::Active, QPalette::Inactive, QPalette::Disabled})
                    value.palette.setColor(group, QPalette::ButtonText, value.palette.color(group, QPalette::HighlightedText));
            QProxyStyle::drawControl(element, &value, painter, widget);
            return;
        }
    }
    if (element == CE_ToolButtonLabel) {
        if (auto button = qstyleoption_cast<const QStyleOptionToolButton *>(option)) {
            QStyleOptionToolButton value(*button);
            value.palette = standardPalette();
            if (value.state & State_On)
                value.palette.setColor(QPalette::ButtonText, theme->color("on_primary"));
            QProxyStyle::drawControl(element, &value, painter, widget);
            return;
        }
    }
    if (element == CE_HeaderSection) {
        painter->fillRect(option->rect, translucent(theme->color("surface_container"), .45));
        return;
    }
    if (element == CE_TabBarTabShape) {
        painter->save();
        const bool selected = option->state & State_Selected;
        rounded(painter, option->rect.adjusted(2, 2, -2, -2),
                translucent(theme->color("on_surface"), selected ? .08 : option->state & State_MouseOver ? .05 : 0), {}, 8);
        if (selected) {
            painter->setPen(QPen(theme->color("primary"), 2, Qt::SolidLine, Qt::RoundCap));
            painter->drawLine(option->rect.bottomLeft()+QPoint(12, -2), option->rect.bottomRight()+QPoint(-12, -2));
        }
        painter->restore();
        return;
    }
    if (element == CE_ProgressBarGroove || element == CE_ProgressBarContents) {
        const auto progress = qstyleoption_cast<const QStyleOptionProgressBar *>(option);
        if (progress) {
            const auto bar = qobject_cast<const QProgressBar *>(widget);
            const bool horizontal = bar ? bar->orientation() == Qt::Horizontal : option->state & State_Horizontal;
            QRectF rect = option->rect;
            if (horizontal) { rect.setY(progress->textVisible ? rect.bottom()-3 : rect.center().y()-2); rect.setHeight(4); }
            else { rect.setX(rect.center().x()-2); rect.setWidth(4); }
            painter->save();
            if (element == CE_ProgressBarGroove)
                rounded(painter, rect, translucent(theme->color("outline_variant"), .5), {}, 2);
            else {
                qreal fraction = progress->maximum > progress->minimum
                    ? qBound(0., double(progress->progress-progress->minimum)/(progress->maximum-progress->minimum), 1.) : .35;
                if (horizontal) {
                    const qreal extent = rect.width()*fraction;
                    if (progress->invertedAppearance ^ (option->direction == Qt::RightToLeft))
                        rect.setLeft(rect.right()-extent);
                    else rect.setWidth(extent);
                } else { rect.setTop(rect.bottom()-rect.height()*fraction); }
                rounded(painter, rect, theme->color("primary"), {}, 2);
            }
            painter->restore();
            return;
        }
    }
    if (element == CE_ProgressBarLabel) {
        if (auto progress = qstyleoption_cast<const QStyleOptionProgressBar *>(option)) {
            painter->save();
            painter->setPen(foreground(option));
            painter->drawText(option->rect.adjusted(0, 0, 0, -5), Qt::AlignCenter, progress->text);
            painter->restore();
            return;
        }
    }
    if (element == CE_MenuItem) {
        if (auto item = qstyleoption_cast<const QStyleOptionMenuItem *>(option)) {
            painter->save();
            QRect rect = item->rect.adjusted(5, 2, -5, -2);
            if (item->menuItemType == QStyleOptionMenuItem::Separator) {
                painter->setPen(translucent(theme->color("outline"), .24));
                painter->drawLine(rect.left()+8, rect.center().y(), rect.right()-8, rect.center().y());
            } else {
                const bool selected = item->state & State_Enabled && item->state & State_Selected;
                if (selected)
                    rounded(painter, rect, theme->color("primary"), {}, 8);
                QColor textColor = selected ? theme->color("on_primary") : theme->color("on_surface");
                if (!(item->state & State_Enabled)) {
                    const QColor surface = theme->color("surface_container_high");
                    textColor = QColor(qRound(textColor.red()*.55 + surface.red()*.45),
                                       qRound(textColor.green()*.55 + surface.green()*.45),
                                       qRound(textColor.blue()*.55 + surface.blue()*.45));
                }
                painter->setPen(textColor);
                const int leading = qMax(22, item->maxIconWidth+8);
                const QRect iconRect(rect.left()+6, rect.center().y()-8, 16, 16);
                if (!item->icon.isNull())
                    item->icon.paint(painter, visualRect(item->direction, rect, iconRect), Qt::AlignCenter,
                                     !(item->state & State_Enabled) ? QIcon::Disabled : selected ? QIcon::Selected : QIcon::Normal);
                else if (item->checked) {
                    painter->setPen(QPen(selected ? theme->color("on_primary") : theme->color("primary"), 2,
                                        Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
                    QPainterPath tick;
                    const QPointF center = visualRect(item->direction, rect, iconRect).center();
                    tick.moveTo(center+QPointF(-4, 0)); tick.lineTo(center+QPointF(-1, 3));
                    tick.lineTo(center+QPointF(4, -3)); painter->drawPath(tick);
                }
                QRect label = rect.adjusted(leading+8, 0, -20, 0);
                const QString text = item->text.section('\t', 0, 0);
                painter->setPen(textColor);
                painter->drawText(visualRect(item->direction, rect, label), Qt::AlignVCenter | Qt::TextShowMnemonic, text);
                if (item->text.contains('\t')) {
                    painter->setPen(translucent(textColor, .65));
                    painter->drawText(label, Qt::AlignVCenter | Qt::AlignRight, item->text.section('\t', 1));
                }
                if (item->menuItemType == QStyleOptionMenuItem::SubMenu)
                    chevron(painter, visualRect(item->direction, rect, QRect(rect.right()-15, rect.center().y()-6, 12, 12)).center(),
                            textColor, item->direction == Qt::RightToLeft ? Qt::LeftArrow : Qt::RightArrow);
            }
            painter->restore();
            return;
        }
    }
    QProxyStyle::drawControl(element, option, painter, widget);
}

void AvethyStyle::drawComplexControl(ComplexControl control, const QStyleOptionComplex *option,
                                         QPainter *painter, const QWidget *widget) const
{
    auto theme = Palette::instance();
    if (control == CC_ComboBox || control == CC_SpinBox) {
        painter->save();
        rounded(painter, option->rect, theme->color(control == CC_SpinBox ? "surface_container_low" : "surface_container_high"),
                option->state & State_HasFocus ? theme->color("primary") : translucent(theme->color("outline"), .24));
        if (control == CC_ComboBox)
            chevron(painter, subControlRect(control, option, SC_ComboBoxArrow, widget).center(), foreground(option), Qt::DownArrow);
        else {
            chevron(painter, subControlRect(control, option, SC_SpinBoxUp, widget).center(), foreground(option), Qt::UpArrow);
            chevron(painter, subControlRect(control, option, SC_SpinBoxDown, widget).center(), foreground(option), Qt::DownArrow);
        }
        painter->restore();
        return;
    }
    if (control == CC_Slider) {
        if (auto slider = qstyleoption_cast<const QStyleOptionSlider *>(option)) {
            QRectF groove = subControlRect(control, option, SC_SliderGroove, widget);
            const QRectF handle = subControlRect(control, option, SC_SliderHandle, widget);
            const bool horizontal = slider->orientation == Qt::Horizontal;
            if (horizontal) { groove.setY(handle.center().y()-2); groove.setHeight(4); }
            else { groove.setX(handle.center().x()-2); groove.setWidth(4); }
            painter->save();
            rounded(painter, groove, translucent(theme->color("outline_variant"), .6), {}, 2);
            QRectF filled = groove;
            if (horizontal) {
                if (slider->upsideDown) filled.setLeft(handle.center().x());
                else filled.setRight(handle.center().x());
            } else {
                if (slider->upsideDown) filled.setTop(handle.center().y());
                else filled.setBottom(handle.center().y());
            }
            rounded(painter, filled, theme->color("primary"), {}, 2);
            painter->setPen(Qt::NoPen);
            painter->setBrush(theme->palette().color(option->state & State_Enabled ? QPalette::Active : QPalette::Disabled, QPalette::Highlight));
            painter->drawEllipse(handle.center(), 7, 7);
            painter->restore();
            return;
        }
    }
    if (control == CC_ScrollBar) {
        painter->save();
        QRectF handle = subControlRect(control, option, SC_ScrollBarSlider, widget);
        auto slider = qstyleoption_cast<const QStyleOptionSlider *>(option);
        if (slider && slider->orientation == Qt::Horizontal) handle.adjust(0, 2, 0, -2);
        else handle.adjust(2, 0, -2, 0);
        rounded(painter, handle, translucent(theme->color("on_surface"), option->state & State_MouseOver ? .45 : .28), {}, 4);
        painter->restore();
        return;
    }
    QProxyStyle::drawComplexControl(control, option, painter, widget);
}

int AvethyStyle::pixelMetric(PixelMetric metric, const QStyleOption *option, const QWidget *widget) const
{
    switch (metric) {
    case PM_DefaultFrameWidth: return 1;
    case PM_ButtonMargin: return 10;
    case PM_MenuPanelWidth: return 6;
    case PM_MenuHMargin: case PM_MenuVMargin: return 4;
    case PM_MenuBarPanelWidth: return 0;
    case PM_ToolBarFrameWidth: return 0;
    case PM_ToolBarItemMargin: return 2;
    case PM_ToolBarItemSpacing: return 4;
    case PM_ScrollBarExtent: return 10;
    case PM_ScrollBarSliderMin: return 28;
    case PM_SliderThickness: return 20;
    case PM_SliderLength: return 16;
    case PM_IndicatorWidth: case PM_IndicatorHeight:
    case PM_ExclusiveIndicatorWidth: case PM_ExclusiveIndicatorHeight: return 18;
    case PM_LayoutHorizontalSpacing: case PM_LayoutVerticalSpacing: return 8;
    default: return QProxyStyle::pixelMetric(metric, option, widget);
    }
}
int AvethyStyle::styleHint(StyleHint hint, const QStyleOption *option, const QWidget *widget, QStyleHintReturn *data) const
{
    switch (hint) {
    case SH_ItemView_ShowDecorationSelected: return true;
    case SH_Menu_MouseTracking: return true;
    case SH_Menu_AllowActiveAndDisabled: return false;
    case SH_ComboBox_Popup: return true;
    case SH_ScrollBar_Transient: return true;
    case SH_Widget_Animate: return true;
    case SH_Widget_Animation_Duration: return 120;
    case SH_UnderlineShortcut: return false;
    default: return QProxyStyle::styleHint(hint, option, widget, data);
    }
}
QSize AvethyStyle::sizeFromContents(ContentsType type, const QStyleOption *option, const QSize &size, const QWidget *widget) const
{
    QSize result = QProxyStyle::sizeFromContents(type, option, size, widget);
    if (type == CT_PushButton || type == CT_ComboBox || type == CT_LineEdit || type == CT_SpinBox)
        result.setHeight(qMax(result.height(), option ? option->fontMetrics.height()+16 : 32));
    if (type == CT_MenuItem) {
        const auto item = qstyleoption_cast<const QStyleOptionMenuItem *>(option);
        if (item && item->menuItemType != QStyleOptionMenuItem::Separator)
            result.setHeight(qMax(result.height(), option->fontMetrics.height()+12));
    }
    return result;
}
