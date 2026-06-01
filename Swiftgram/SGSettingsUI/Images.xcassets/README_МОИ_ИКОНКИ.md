# Куда класть свои иконки (LuxGram)

Замените файлы в этих папках своими картинками — приложение подхватит их автоматически.

## Шапка экрана LuxGram

| Папка | Файл | Назначение |
|-------|------|------------|
| `LuxGramSettings.imageset/` | **LuxGramSettings.png** | Большая иконка в шапке экрана LuxGram |

Рекомендуемый размер: около 80×80 pt (или 240×240 px для @3x).

---

## Вкладки раздела «Функции»

| Папка | Файл | Назначение |
|-------|------|------------|
| `LuxGramTabAppearance.imageset/` | **LuxGramTabAppearance.png** | Иконка «Оформление» |
| `LuxGramTabSecurity.imageset/` | **LuxGramTabSecurity.png** | Иконка «Приватность» |
| `LuxGramTabPlugins.imageset/` | **LuxGramTabPlugins.png** | Иконка «Твики» |
| `LuxGramTabOther.imageset/` | **LuxGramTabOther.png** | Иконка «Другие функции» |

Рекомендуемый размер для иконок в списке: 24×24 pt (72×72 px для @3x). Формат: PNG (можно и PDF в одной шкале).

---

## Другие ресурсы

- `LuxGramVerifiedBadge.imageset/` — значок верификации (Galochka.png).
- `glePlugins/1.imageset/` — иконка по умолчанию для плагинов без своей иконки.
- `SwiftgramSettings.imageset/`, `SwiftgramPro.imageset/` — иконки пунктов меню настроек.

После замены файлов пересоберите приложение (Bazel).
