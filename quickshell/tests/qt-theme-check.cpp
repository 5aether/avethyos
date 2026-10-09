#include <QApplication>
#include <QCheckBox>
#include <QComboBox>
#include <QDialog>
#include <QEventLoop>
#include <QFile>
#include <QHBoxLayout>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLabel>
#include <QLineEdit>
#include <QListWidget>
#include <QMainWindow>
#include <QMenu>
#include <QPainter>
#include <QProgressBar>
#include <QPushButton>
#include <QSaveFile>
#include <QSlider>
#include <QStyle>
#include <QStyleOption>
#include <QTemporaryDir>
#include <QTimer>
#include <QToolBar>
#include <QVBoxLayout>
#include <cstdio>

static void require(bool condition, const char *message)
{
    if (!condition) { std::fprintf(stderr, "FAIL: %s\n", message); std::exit(1); }
}
static void settle(int duration = 100)
{
    QEventLoop loop;
    QTimer::singleShot(duration, &loop, &QEventLoop::quit);
    loop.exec();
}
static void save(const QString &path, const QJsonObject &data)
{
    QSaveFile file(path);
    require(file.open(QIODevice::WriteOnly), "open fixture");
    file.write(QJsonDocument(data).toJson());
    require(file.commit(), "atomic fixture write");
}
int main(int argc, char **argv)
{
    QFile input(qEnvironmentVariable("AVETHY_QT_THEME"));
    require(input.open(QIODevice::ReadOnly), "AVETHY_QT_THEME points to a generated palette");
    QJsonObject data = QJsonDocument::fromJson(input.readAll()).object();
    QTemporaryDir fixture;
    const QString file = fixture.path()+"/palette.json";
    save(file, data);
    qputenv("AVETHY_QT_THEME", file.toUtf8());
    QApplication app(argc, argv);
    require(app.style()->objectName() == "avethy", "native Avethy style loaded");
    require(app.property("KDE_COLOR_SCHEME_PATH").toString() == data.value("kde_scheme").toString(),
            "KDE color scheme path available during app startup");
    settle();
    QColor primary(data.value("roles").toObject().value("primary").toString());
    QColor onPrimary(data.value("roles").toObject().value("on_primary").toString());
    require(app.palette().color(QPalette::Highlight) == primary, "application highlight equals shared primary");
    require(app.palette().color(QPalette::Inactive, QPalette::Highlight) == primary, "inactive selection retains primary");
#if QT_VERSION >= QT_VERSION_CHECK(6, 6, 0)
    require(app.palette().color(QPalette::Accent) == primary, "Qt Accent equals shared primary");
#endif
    QStyleOptionButton button;
    button.rect = QRect(0, 0, 120, 36);
    button.state = QStyle::State_Enabled | QStyle::State_On;
    button.palette = app.palette();
    QImage image(120, 36, QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    {
        QPainter painter(&image);
        app.style()->drawPrimitive(QStyle::PE_PanelButtonCommand, &button, &painter);
    }
    require(image.pixelColor(60, 18) == primary, "checked button fill matches GTK primary exactly");
    QStyleOptionViewItem item;
    item.rect = button.rect;
    item.state = QStyle::State_Enabled | QStyle::State_Selected;
    item.palette = app.palette();
    image.fill(Qt::transparent);
    {
        QPainter painter(&image);
        app.style()->drawPrimitive(QStyle::PE_PanelItemViewItem, &item, &painter);
    }
    require(image.pixelColor(60, 18) == primary, "selected file/sidebar item fill matches GTK primary");
    QMainWindow window;
    window.setWindowTitle("Quickshell Qt theme");
    window.resize(840, 520);
    auto toolbar = window.addToolBar("Navigation");
    toolbar->addAction("Home");
    toolbar->addAction("Recent");
    auto body = new QWidget;
    auto layout = new QHBoxLayout(body);
    auto sidebar = new QListWidget;
    sidebar->addItems({"Home", "Recent", "Starred", "Downloads"});
    sidebar->setCurrentRow(0);
    sidebar->setFixedWidth(180);
    layout->addWidget(sidebar);
    auto pane = new QVBoxLayout;
    pane->setSpacing(16);
    auto title = new QLabel("Wallpaper colors shared by Qt, KDE and GTK");
    pane->addWidget(title);
    pane->addWidget(new QLineEdit("A minimal native Qt theme"));
    auto combo = new QComboBox;
    combo->addItems({"Wallpaper palette", "Light appearance", "Dark appearance"});
    pane->addWidget(combo);
    auto check = new QCheckBox("Use the same accent everywhere");
    check->setChecked(true);
    pane->addWidget(check);
    auto slider = new QSlider(Qt::Horizontal);
    slider->setValue(65);
    pane->addWidget(slider);
    auto progress = new QProgressBar;
    progress->setValue(65);
    pane->addWidget(progress);
    auto actions = new QHBoxLayout;
    actions->addWidget(new QPushButton("Cancel"));
    auto apply = new QPushButton("Apply");
    apply->setDefault(true);
    actions->addWidget(apply);
    pane->addLayout(actions);
    pane->addStretch();
    layout->addLayout(pane);
    window.setCentralWidget(body);
    window.show();
    settle();
    require(window.testAttribute(Qt::WA_TranslucentBackground), "native window enables background translucency");
    const QString screenshot = qEnvironmentVariable("QUICKSHELL_THEME_SCREENSHOT");
    const QImage rendered = window.grab().toImage();
    const int alpha = rendered.pixelColor(rendered.width()-30, rendered.height()-30).alpha();
    require(qAbs(alpha - (data.value("mode").toString() == "light" ? 240 : 225)) <= 1,
            "window paints exactly one GTK-matching translucent tint");
    if (!screenshot.isEmpty()) rendered.save(screenshot);
    // Exercise the real popup paint path, including its frame and blank areas.
    QMenu menu(&window);
    auto open = menu.addAction("Open\tCtrl+O");
    auto pin = menu.addAction("Pin");
    pin->setCheckable(true);
    pin->setChecked(true);
    menu.addSeparator();
    menu.addMenu("More")->addAction("Properties");
    menu.addAction("Unavailable")->setEnabled(false);
    menu.popup(window.mapToGlobal(QPoint(260, 80)));
    settle();
    const QImage popup = menu.grab().toImage();
    if (!screenshot.isEmpty()) popup.save(screenshot + ".menu.png");
    const QColor menuPixel = popup.pixelColor(popup.width()/2, 3);
    const QColor menuSurface(data.value("roles").toObject().value("surface_container_high").toString());
    const int menuAlpha = data.value("mode").toString() == "light" ? 247 : 240;
    require(qAbs(menuPixel.alpha()-menuAlpha) <= 1, "menu paints one translucent palette layer");
    require(qAbs(menuPixel.red()-menuSurface.red()) <= 1
            && qAbs(menuPixel.green()-menuSurface.green()) <= 1
            && qAbs(menuPixel.blue()-menuSurface.blue()) <= 1, "menu background matches shared palette surface");
    require(popup.pixelColor(0, 0).alpha() == 0, "menu rounded corners stay transparent");
    menu.setActiveAction(open);
    settle();
    const QRect selectedRect = menu.actionGeometry(open);
    const QImage selectedMenu = menu.grab().toImage();
    require(selectedMenu.pixelColor(selectedRect.center()) == primary,
            "context menu pointer/keyboard selection uses shared primary");
    menu.close();
    // An app changing its style and palette must not silently detach from the
    // shell's theme. Exercise both the global and per-widget override paths.
    app.setStyle("Fusion");
    QPalette wrong = app.palette();
    wrong.setColor(QPalette::Highlight, Qt::red);
    app.setPalette(wrong);
    apply->setPalette(wrong);
    settle();
    require(app.style()->objectName() == "avethy", "application style override reconciled");
    require(app.palette().color(QPalette::Highlight) == primary, "application palette override reconciled");
    require(apply->palette().color(QPalette::Highlight) == primary, "widget palette override reconciled");
    // Atomic wallpaper palette replacement reloads already-open applications.
    auto roles = data.value("roles").toObject();
    roles["primary"] = "#f09dc8";
    data["roles"] = roles;
    auto groups = data.value("palette").toObject();
    for (const QString &name : {QStringLiteral("Active"), QStringLiteral("Inactive")}) {
        auto colors = groups.value(name).toArray();
        colors[12] = "#fff09dc8";
        if (colors.size() > 21) colors[21] = "#fff09dc8";
        groups[name] = colors;
    }
    data["palette"] = groups;
    save(file, data);
    settle(250);
    require(app.palette().color(QPalette::Highlight) == QColor("#f09dc8"), "live atomic wallpaper palette reload");
    require(apply->palette().color(QPalette::Highlight) == QColor("#f09dc8"), "live widget palette reload");
    std::printf("PASS: Qt %s native style, GTK accent, KDE path, translucent windows/menus, menu selection, live palette reload\n", qVersion());
    std::fflush(stdout);
    return 0;
}
