# Third-party notices / Лицензии третьих сторон

Outadapt использует материалы ниже. Этот файл — черновик для итоговых credits игры и страницы Steam; статус каждого пункта и нерешённые вопросы — в [docs/asset-license-audit.md](docs/asset-license-audit.md).

> **Статус: черновик аудита от 15.11.2026. Раздел «Иконки» и музыка требуют доработки до релиза (см. аудит).**

## Движок

- **Godot Engine 4.7.2** — MIT License, © Juan Linietsky, Ariel Manzur and contributors; © Godot Engine contributors. Полный текст лицензии и список сторонних компонентов движка (FreeType, ICU, libogg/libvorbis, miniaudio и др.) доступны через `Engine.get_license_text()` и `Engine.get_license_info()` и должны быть показаны в экране credits/licenses готовой игры. https://godotengine.org/license

## Графика (CC0 1.0 — атрибуция не обязательна, указываем из уважения)

- **Spire** (пакеты Enemy Pack 1–2, Tower Pack 1–4, Builder Pack, Tileset 1, Pixel Magic Effects) — Foozle (www.foozle.io), заказано у Baldur. CC0 1.0. Текст: `godot/assets/spire/LICENSE_Spire_CC0.txt`; Readme каждого пакета лежит в `assets_src/spire/x/`. В игре используются снаряды, попадания, эффекты и часть тайлов (`godot/assets/spire/`), часть перекрашена скриптом `tools/import_spire.py`.
- **Tower Defense (top-down) Pack** — Kenney Vleugels (www.kenney.nl). CC0 1.0. В сборку не входит (лежит только в `assets_src/kenney_td/`).

## Звук (CC0 1.0)

- **Эффекты:** наборы Kenney (kenney.nl) — Impact Sounds, RPG Audio, Sci-Fi Sounds, Digital Audio, Interface Sounds; получены из портов `Boyquotes/kenney-*-for-godot` и `Calinou/kenney-interface-sounds` на GitHub.
- **Музыка:** «Shakkar» — zesona (Chris Murphy), https://opengameart.org/content/shakkar; «Exploration» из набора «Medieval» — RandomMind, https://opengameart.org/content/medieval-exploration. Заявлено как CC0 (**не подтверждено первоисточником, см. аудит**).

## Иконки интерфейса (CC BY 3.0 — атрибуция ОБЯЗАТЕЛЬНА)

Векторные иконки в `godot/scripts/ui/icon_data.gd` взяты с **game-icons.net** (лицензия CC BY 3.0, https://creativecommons.org/licenses/by/3.0/). Форма кредита по правилам сайта: «Icons made by {автор}. Available on https://game-icons.net».

**TODO до релиза:** сопоставить каждую иконку с её автором (Lorc, Delapouite и др.) и перечислить авторов поимённо; список иконок и статус — в аудите. Иконки, нарисованные самостоятельно (`tower-net`, `tower-tesla`, `gene-split`, `gene-ward`, `gene-plated`), атрибуции не требуют, если подтвердится авторство.

## Изображения, созданные нейросетью

Часть игровой графики создана генеративной моделью по запросам автора проекта: модели башен, модели врагов, поверхности биомов, декор, портал, замки, рамки и иконки HUD, фон главного меню. Перечень и план раскрытия в Steam — в [аудите](docs/asset-license-audit.md). Сторонней атрибуции не требуется, но использование должно соответствовать условиям сервиса, через который изображения созданы (**сервис и версию условий подтвердить**).

## Шрифты

Собственные шрифты в игру не вшиты: интерфейс использует системные шрифты (`SystemFont`: Segoe UI, Inter, Roboto, Arial). Лицензий на шрифты в сборке нет; см. риск в аудите.
