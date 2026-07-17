# Lamo Agent Roadmap

## KV-Cache Budget Strategy for Agentic Loop

### Текущая ситуация
- Максимальный бюджет KV-cache: **~9000 токенов** (динамически через `os_proc_available_memory()`)
- System prompt: ~500-1000 токенов
- Memory context: ~200-500 токенов
- Tool definitions: ~500-1000 токенов
- Conversation history (последние 3-4 хода): ~1000-2000 токенов
- Резерв для ответа модели: 512 токенов (уже заложено в `ContextTracker.reservedForReply`)

### Проблема agentic loop
Каждый tool call round-trip добавляет в KV-cache:
- Tool call definition (~50-100 токенов)
- Tool result (потенциально 500-3000 токенов)
- Model intermediate response (~100-500 токенов)

5 итераций × ~2000 токенов = 10000 токенов → **KV-cache переполнен**.

### Решение: двухуровневый контекст + бюджет на итерацию

```
Всего: 9000 токенов
├── System overhead: 1500 (system prompt + memory + tool defs)
├── Conversation skeleton: 1500 (последние 2-3 хода пользователя)
├── Рабочий бюджет: 5500
│   ├── Budget per iteration: 1100 (5500 / 5)
│   │   ├── Model thinking: 400
│   │   ├── Tool call: 50
│   │   └── Tool result (truncated): 650
│   └── Scratchpad (аккумулируется): ~500 (сжатые итоги предыдущих шагов)
└── Резерв для финального ответа: 512
```

### Механика

1. **Token-aware truncation**: tool results обрезаются через реальный токенизатор
   (`ProviderManager.tokenizeCount`) до лимита `perIterationBudget / 2`.

2. **Scratchpad**: после каждого шага модель (или эвристика) добавляет 1-2 предложения
   в scratchpad — что найдено, что решено. Сырые результаты дропаются из контекста.

3. **Progressive summarization**: если scratchpad перерастает 800 токенов,
   самые старые записи сжимаются: «Steps 1-3: found weather (22°C rain),
   calendar (Sat free), hotels (X, Y available)».

4. **Hard stops**:
   - `iterationCount >= maxIterations` (5)
   - `tokensUsed >= workingBudget`
   - Модель дала финальный ответ (нет tool calls)
   - Пользователь нажал Stop

5. **Two-pass mode** (для сложных задач):
   - Pass 1: модель исследует с тулами, всё пишется в scratchpad
   - Pass 2: новый conversation (с system prompt + scratchpad + вопрос),
     модель синтезирует финальный ответ
   - Между пассами все tool interactions выброшены, остался только scratchpad

---

## Tool Implementation Plan

### 1. Calendar (`calendar_tool`)
**Фреймворк:** EventKit  
**Методы:**
- `list_events` — события на дату/диапазон с фильтрацией по календарям
- `create_event` — создать с тайтлом, локацией, заметками, датами, alarm
- `search_events` — текстовый поиск по событиям

**KV-cache impact:** низкий (результаты структурированы и компактны)

### 2. Contacts (`contacts_tool`)
**Фреймворк:** CNContactStore  
**Методы:**
- `search` — поиск по имени, телефону, email, организации
- `get_details` — полная карточка контакта

**KV-cache impact:** низкий

### 3. Notes (`notes_tool`)  
**Подход:** Встроенная файловая система заметок (Apple Notes не имеет публичного API).
Заметки хранятся в JSON-файле в documents directory приложения.  
**Методы:**
- `list` — список всех заметок
- `search` — полнотекстовый поиск
- `read` — прочитать заметку
- `create` — создать
- `append` — дополнить
- `delete` — удалить

**KV-cache impact:** средний (контент заметок может быть длинным — обрезаем до 1500 токенов)

### 4. Shortcuts (`shortcuts_tool`)
**Подход:** URL scheme `shortcuts://run-shortcut?name=...`  
**Методы:**
- `run` — запустить shortcut по имени
- `list` — список доступных shortcuts (через голосовой ввод или предварительный импорт)

**KV-cache impact:** низкий

### 5. Health (`health_tool`)
**Фреймворк:** HealthKit (read-only)  
**Методы:**
- `steps` — шаги за день/неделю/месяц
- `heart_rate` — средний пульс, min/max
- `sleep` — длительность сна
- `weight` — последние измерения веса
- `summary` — дневная сводка (шаги + калории + минуты активности)

**KV-cache impact:** низкий (цифры компактны)

### 6. Calendar Availability (`calendar_availability_tool`)
**Фреймворк:** EventKit (строится на calendar_tool)  
**Методы:**
- `find_slots` — найти свободные окна заданной длительности в диапазоне дат

**KV-cache impact:** низкий

### 7. Code Sandbox (`code_sandbox_tool`)
**Фреймворк:** JavaScriptCore (встроен в iOS, без сети)  
**Методы:**
- `run` — исполнить JS-код, вернуть stdout

**KV-cache impact:** средний (код + результат — обрезаем результат до 1000 токенов)

### 8. Planner (`planner_tool`)
**Подход:** Meta-tool. Модель возвращает JSON-план, который парсится и исполняется.
Это НЕ отдельный LiteRT-LM Tool, а логика в ChatViewModel.  
**Формат плана:**
```json
{
  "goal": "...",
  "steps": [
    {"tool": "calendar", "params": {...}, "reasoning": "..."},
    {"tool": "weather", "params": {...}, "reasoning": "..."}
  ]
}
```

**KV-cache impact:** план компактен (~200 токенов), исполняется в agentic loop.

### 9. Agentic Loop (`agentic_loop` — архитектурное изменение)
**Подход:** Не тул, а режим работы ChatViewModel + LiteRTLMProvider.
Включается:
- Автоматически когда planner создал план
- Ручной командой «реши задачу полностью»
- Когда модель запрашивает несколько тулов подряд

**KV-cache:** управляется через `AgenticLoopBudget` (см. стратегию выше).

---

## Implementation Order

1. **Foundation:** `AgenticLoopBudget.swift` + `AgenticLoopState.swift`
2. **Simple tools:** code_sandbox, contacts, health, shortcuts, notes
3. **Calendar tools:** calendar, calendar_availability
4. **Agentic changes:** ChatViewModel + LiteRTLMProvider
5. **Planner:** meta-tool logic
6. **UI + Settings:** ToolSettingsSection update, toggles
7. **System prompt:** update default system prompt for new tools
