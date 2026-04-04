# Internationalize Strings Task

**Difficulty**: 🟡 Medium  
**Skills**: Code refactoring, string extraction, i18n patterns, JSON creation, multi-file editing  
**Duration**: 540 seconds  
**Steps**: ~50

## Objective

Prepare a small JavaScript application for internationalization by extracting hardcoded user-facing strings into a translation file and refactoring the code to use an i18n function. This simulates a common real-world scenario when expanding applications to international markets.

## Scenario

You've inherited a small user authentication module that has English text hardcoded throughout. Your task is to extract all **user-facing strings** (error messages, UI labels, success messages) into a translation file while leaving **debug/logging strings** unchanged.

## Expected Workflow

1. **Examine the code** (`app.js`) to identify user-facing vs. debug strings
2. **Create translation file structure**:
   - Create directory: `i18n/`
   - Create file: `i18n/en.json`
3. **Extract strings to translation file**:
   - Identify user-facing strings (error messages, UI text, success messages)
   - Create semantic keys (e.g., `"error.emptyCredentials"`, `"button.submit"`)
   - Add entries to `en.json` as `{"key": "value"}` pairs
4. **Refactor source code**:
   - Add i18n import at top: `const { t } = require('./i18n');`
   - Replace hardcoded strings with: `t('key.name')`
   - Keep console.log debug messages unchanged
5. **Save all files** (Ctrl+S)

## User-Facing vs. Debug Strings

✅ **EXTRACT** (user-facing):
- Error messages: `"Please enter both username and password"`
- Success messages: `"Welcome back! Your login was successful."`
- UI labels: `"Submit"`, `"Cancel"`, `"User Profile"`
- Descriptions: `"Update your personal information below"`

❌ **KEEP** (debug/internal):
- Console.log messages: `"DEBUG: Attempting login for user:"`
- Technical constants: `"GET"`, `"POST"`, `"/api/users"`
- Code comments and variable names

## Expected Structure

**i18n/en.json:**