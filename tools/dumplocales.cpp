#include <QCoreApplication>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QSet>

// Dumps every locale Qt can format, with native and English names, as the
// inventory backing the language picker. Built once into i18n/locales.json.
int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    QJsonArray out;
    QSet<QString> seen;
    const QLocale english(QLocale::English);

    auto add = [&](const QLocale& loc) {
        const QString name = loc.name();
        if (name.isEmpty() || name == "C" || name.startsWith("C@"))
            return;
        if (seen.contains(name))
            return;
        seen.insert(name);
        QJsonObject o;
        o["code"] = name;
        o["native"] = loc.nativeLanguageName();
        const QString en = english.languageToString(loc.language());
        o["english"] = (en == loc.nativeLanguageName()) ? QString() : en;
        o["territory"] = name.contains('_') ? name.section('_', 1) : QString();
        out.append(o);
    };

    for (const auto& loc : QLocale::matchingLocales(QLocale::AnyLanguage,
                                                    QLocale::AnyScript,
                                                    QLocale::AnyTerritory))
        add(loc);

    QFile f(argv[1]);
    if (!f.open(QIODevice::WriteOnly))
        return 1;
    f.write(QJsonDocument(out).toJson(QJsonDocument::Indented));
    return 0;
}
