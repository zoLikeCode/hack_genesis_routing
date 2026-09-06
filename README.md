# Маршрутизация выплат

Программа выбирает платёжного партнёра (провайдера) для каждой выплаты. Сначала она отсекает тех, кому заявку **нельзя** отправить. Затем среди оставшихся выбирает наиболее подходящего по настроенным стратегиям. Если выбранный партнёр отказал, система пробует следующего. Если внешних партнёров не осталось, используется запасной провайдер `spacepayments`.

Подробнее о том, как устроен поток данных и архитектура: [docs/architecture.md](docs/architecture.md).  
Подробнее о том, как устроены метрики и стратегии: [docs/metrics_and_strategies.md](docs/metrics_and_strategies.md).

## Что входит в проект

| Часть                       | Зачем нужна                                                            |
| --------------------------- | ---------------------------------------------------------------------- |
| CLI `bin/route`             | Запускает маршрутизацию очереди выплат и пишет результат в JSON        |
| `config/routing_policy.yml` | Политика: стратегии, веса, профили провайдеров, fallback, status-check |
| `data/`                     | Входные файлы: провайдеры, история, очередь заявок, пример ответа      |
| `lib/routing/`              | Код маршрутизатора на Ruby                                             |
| `bin/setup`                 | Установка зависимостей                                                 |
| `bin/console`               | Интерактивная Ruby-консоль с загруженной библиотекой                   |
| `scripts/validate_10.rb`    | Проверка формата решений для публичной очереди из 10 заявок            |
| RSpec и RuboCop             | Тесты и проверка стиля кода                                            |
| `docs/`                     | Документация                                                           |

## Что нужно для запуска

- Ruby **4.0 или новее** (см. `.ruby-version`)
- Bundler

В CLI по умолчанию включён YJIT (`RUBY_YJIT_ENABLE=1` в `bin/route`).

## Установка

Из каталога проекта:

```bash
ruby bin/setup
```

Либо вручную:

```bash
bundle install
```

## Как запустить маршрутизацию

Показать все флаги:

```bash
ruby bin/route --help
```

### Обычный запуск (очередь из 10 заявок)

Так обрабатывается публичный пример `data/operations_queue_10.json`:

```bash
ruby bin/route
```

По умолчанию программа читает:

- провайдеров: `data/providers.json`
- очередь: `data/operations_queue_10.json`
- историю: `data/operations_history.csv`
- политику: `config/routing_policy.yml`

и записывает в текущую папку:

- `routing_decisions_test.json` — решение по каждой заявке
- `routing_report_test.json` — аналитика и рекомендации
- `routing_runtime_state.json` — снимок состояния после прогона (счётчики, резервы, status-check)

### Своя очередь

```bash
ruby bin/route --queue path/to/operations_queue_test.json
```

Другие пути можно задать так:

```bash
ruby bin/route ^
  --providers data/providers.json ^
  --queue data/operations_queue_10.json ^
  --history data/operations_history.csv ^
  --policy config/routing_policy.yml ^
  --decisions routing_decisions_test.json ^
  --report routing_report_test.json ^
  --runtime routing_runtime_state.json
```

В PowerShell удобнее одна строка или обратные кавычки `` ` `` вместо `^`.

### Параллельный режим

В `config/routing_policy.yml` сейчас стоит `concurrency.enabled: true`, поэтому обычный `ruby bin/route` уже обрабатывает ожидание ответов провайдеров параллельно. Правила выбора партнёра те же; подробности — в [docs/architecture.md](docs/architecture.md#параллельная-обработка).

Флаг принудительно включает тот же режим, даже если в YAML параллельность выключена:

```bash
ruby bin/route --concurrent
```

Чтобы идти по одной заявке с проверкой лимитов по её `created_at`:

```bash
ruby bin/route --no-concurrent --queue path/to/operations_queue_test.json
```

Это последовательная симуляция: интервалы между заявками учитываются в модельном времени,
без реального ожидания. Она не моделирует перекрытие времени обработки успешных выплат.
Флаг переопределяет `concurrency.enabled: true` без изменения YAML.
Для последовательного режима по умолчанию можно поставить `concurrency.enabled: false`.

### Подача группами по `created_at`

```bash
ruby bin/route --replay --queue path/to/operations_queue_test.json
```

В этом режиме одинаковые `created_at` поступают одной группой, короткие интервалы
сохраняются, а промежутки больше 30 секунд сокращаются до 30 секунд.
Новая группа поступает независимо от завершения предыдущих выплат.
Задержки ответов симулятора, RPM и проверки статуса используют общий масштаб времени:
100 модельных секунд за одну реальную. Режим требует `fiber_pool` и включает параллельную обработку.
Сокращение больших промежутков усиливает тестовую нагрузку относительно исходного расписания.
Исходные `created_at` в операциях остаются неизменными.

## Что получается на выходе

`routing_decisions_test.json` — массив решений. Для каждой заявки указаны выбранный провайдер, список попыток (`selected` / `skipped` с причиной) и смоделированный результат (`approved` / `rejected` / `expired`).

`routing_report_test.json` — сводка: фактические доли трафика, отклонения от цели, причины пропусков, загрузка дневных лимитов, метрики качества и рекомендации.

`routing_runtime_state.json` — технический снимок после прогона. Автоматически восстанавливать процесс после перезапуска программа не пытается: в кейсе нет реального API восстановления у провайдеров.

## Проверка результата

Проверить свои решения для публичной очереди из 10 заявок:

```bash
bundle exec rake validate[routing_decisions_test.json]
```

В PowerShell квадратные скобки нужно взять в кавычки:

```powershell
bundle exec rake "validate[routing_decisions_test.json]"
```

Или напрямую:

```bash
ruby scripts/validate_10.rb routing_decisions_test.json
```

Без аргумента `rake validate` проверяет `data/sample_routing_decisions.json`.

## Тесты и линтер

```bash
bundle exec rake          # RSpec + RuboCop
bundle exec rspec
bundle exec rubocop
bundle exec rubocop -A    # исправить то, что RuboCop умеет поправить сам
```
