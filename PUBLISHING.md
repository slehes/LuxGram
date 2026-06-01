# Publishing Guide

## Repository Structure

| Repo | URL | Branch | Content |
|------|-----|--------|---------|
| **Public** | `github.com/LuxGram/LuxGram-iOS` | `main` | Clean code, no secrets |
| **Private** | `github.com/LuxGram/LuxGram-iOS-Private` | `main` | Full code with keys, codesigning |

## Local Setup

```bash
cd /Users/leeksov/Desktop/LuxGram-iOS-public

# Remotes:
#   origin  → Public repo (LuxGram/LuxGram-iOS)
#   private → Private repo (LuxGram/LuxGram-iOS-Private)

# Branches:
#   main    → public code (no secrets)
#   private → full code (with secrets)
```

## Daily Workflow

### 1. Работа ведётся в ветке `private`

```bash
git checkout private
# ... делаешь изменения ...
git add -A
git commit -m "Description of changes"
```

### 2. Пуш в приватный репо

```bash
git push private private:main
```

### 3. Публикация в публичный репо

```bash
# Переключиться на public ветку
git checkout main

# Слить изменения из private
git merge private --no-commit

# Очистить секреты перед коммитом
./scripts/strip-secrets.sh

# Проверить что секретов нет
./scripts/check-secrets.sh

# Закоммитить и запушить
git add -A
git commit -m "Description of changes"
git push origin main
```

## Файлы с секретами (автоматически очищаются strip-secrets.sh)

| Файл | Что содержит | Публичная замена |
|------|-------------|-----------------|
| `LuxGram/SGConfig/Sources/File.swift` | AES/HMAC ключи, API URL | `nil` значения |
| `build-system/ipa-build-configuration.json` | API ID, Hash, Team ID | `YOUR_*` placeholder |
| `build-system/glegram-appstore-configuration.json` | То же | `YOUR_*` placeholder |
| `build-system/real-codesigning/` | Сертификаты, профили | Пустые папки с README |

## Скрипты

### strip-secrets.sh — Удаление секретов перед публикацией

Запускать ТОЛЬКО в ветке `main` перед коммитом в публичный репо.

### check-secrets.sh — Проверка отсутствия секретов

Запускать после strip-secrets.sh для верификации. Если находит секреты — НЕ пушить.

## Правила

1. **НИКОГДА** не пушить ветку `private` в `origin` (публичный репо)
2. **ВСЕГДА** запускать `strip-secrets.sh` перед пушем в публичный репо
3. **ВСЕГДА** проверять `check-secrets.sh` перед пушем
4. Новые секреты добавлять ТОЛЬКО в ветку `private`
5. При добавлении нового секретного файла — обновить `strip-secrets.sh`
