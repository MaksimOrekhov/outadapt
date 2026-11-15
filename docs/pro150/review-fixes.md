# PR #9 — исправления по ревью 15.11.2026

Ответ на [ревью владельца](https://github.com/MaksimOrekhov/outadapt/pull/9#issuecomment-6898605061). Исходная версия: `68d7b87`.

## Прокрутка «Роя»

Панель запоминает объект текущего TDGame через WeakRef. При новом объекте (restart, успешная загрузка, другой fixture) прокрутка сразу сбрасывается и подтверждается после раскладки контейнеров. При обновлении действий в том же забеге сохраняется прежняя позиция; revision token не позволяет более старому deferred callback переписать новую позицию. Закрытие/повторное открытие того же забега и неудачная загрузка сохраняют контекст. Сохранения, sim и игровые правила не менялись.

| Размер | До ревью | Исправленный пустой Рой | Настоящий restart / load |
|---|---|---|---|
| 960×540 | [середина списка](../../screenshots/pro150/review/before/empty-swarm-960x540.png) | [«Пока нет данных» сверху](../../screenshots/pro150/after/empty-swarm-960x540.png) | [restart](../../screenshots/pro150/review/after/restart-swarm-960x540.png), [load](../../screenshots/pro150/review/after/loaded-swarm-960x540.png) |
| 1280×720 | [до](../../screenshots/pro150/review/before/empty-swarm-1280x720.png) | [после](../../screenshots/pro150/after/empty-swarm-1280x720.png) | [restart](../../screenshots/pro150/review/after/restart-swarm-1280x720.png), [load](../../screenshots/pro150/review/after/loaded-swarm-1280x720.png) |

## Советы на узком экране

Advice popover размещается в безопасной области справа от дока с зазором 12px и ниже HUD. Ширина/высота по-прежнему ограничены viewport. Меню сохраняет собственную привязку к кнопке HUD. При изменении размера окна или высоты HUD пересчитывается раскладка открытого popup без скрытия и повторного открытия. Выбор контрбашни закрывает совет и показывает результат в свободном инспекторе.

| Размер | До ревью | После |
|---|---|---|
| 960×540 | [закрывает инспектор](../../screenshots/pro150/review/before/advice-960x540.png) | [инспектор и действия открыты](../../screenshots/pro150/after/advice-960x540.png) |
| 1280×720 | [до](../../screenshots/pro150/review/before/advice-1280x720.png) | [после](../../screenshots/pro150/after/advice-1280x720.png) |

Все PNG сняты из Godot. Четыре исходных кадра сохранены из HEAD 68d7b87 без редактирования. Основная after-серия обновлена для advice/empty-swarm на всех четырёх разрешениях; остальные сцены не переснимались. Capture fixture скрывает перенесённые от стартового кадра pointer tooltips, чтобы снимок empty-state соответствовал отсутствию наведённой клетки.

## Регрессионные проверки

Новый `tests/ui_context_check.gd` включён в общий CI (15 checks). До исправления основные сценарии дали **16 FAIL**, после исправления и расширения набора — **0 failures**.

На 960×540 и 1280×720 проверяются:

- сохранение прокрутки при двух быстрых перестроениях и реальных callback покупки вакцины/приманки;
- restart при открытой панели, restart при скрытой панели с последующим открытием, успешная загрузка и смена TDGame: scroll=0 и весь empty-state caption внутри scroll viewport;
- неудачная загрузка и закрытие/повторное открытие того же контекста: прежняя позиция;
- открытие советов A и мышью, Esc, внешний клик, выбор контрбашни мышью и закрытие popup;
- обновление содержимого открытых советов и уменьшение окна до 960×540: popup внутри окна, ниже HUD, без пересечения с доком.

Клавиатура/мышь проходят через `Window.push_input`, не через `pressed.emit`. Скрипт выполнен и headless, и на реальном renderer с сохранением PNG. `visual_slice_check.gd` дополнительно проверяет свободный инспектор при advice и нулевой scroll для empty-swarm на всех четырёх размерах.

```powershell
$g = 'D:\Godot\Godot_v4.7.2-stable_win64_console.exe'
& $g --headless --path godot --script res://tests/ui_context_check.gd
& $g --path godot --script res://tests/ui_context_check.gd -- --out=E:/Outadapt/screenshots/pro150/review/after
& $g --path godot --script res://tests/visual_slice_check.gd -- --states=advice,empty-swarm --out=E:/Outadapt/screenshots/pro150/after
```

Локально Windows: **15/15 PASS**, renderer context/layout captures: **0 failures**. Актуальный Linux/Windows результат относится к [последнему HEAD PR #9](https://github.com/MaksimOrekhov/outadapt/pull/9/checks).

## Визуальная приёмка

Это два конкретных UI-исправления поверх существующего редизайна. Художественное качество всей графики игры относительно коммерческих референсов не объявляется утверждённым. Модели башен/врагов и основная часть декора не перерисовывались; отдельный [приоритетный art-pass](art-audit.md) остаётся предложением для следующего этапа. PRO-150 остаётся **In Review** до визуальной приёмки владельцем. Merge не выполнять.
