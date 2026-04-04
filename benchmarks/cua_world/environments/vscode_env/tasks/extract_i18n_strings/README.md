# Extract i18n Strings Task

**Difficulty**: 🟡 Medium  
**Skills**: Multi-file refactoring, JSON creation, React/JavaScript, code analysis  
**Duration**: 360 seconds (6 minutes)  
**Steps**: ~50

## Objective

Prepare a React dashboard application for internationalization by extracting hardcoded English strings into a translation file and updating components to use the i18n system.

## Scenario

Your startup is expanding to Japan, Germany, and Brazil! The React codebase has English text hardcoded throughout components. You need to extract user-facing strings into a translation file and replace them with i18n function calls.

## Expected Workflow

1. Review the 3 React components with hardcoded strings:
   - `src/components/Header.jsx`
   - `src/components/LoginForm.jsx`
   - `src/components/Dashboard.jsx`

2. Create translation file `src/locales/en.json` with organized keys:
   - Use nested structure (e.g., `header.title`, `login.submit_button`)
   - Extract ALL user-facing strings (buttons, labels, headings, messages)
   - DO NOT extract: console.logs, classNames, API endpoints

3. Create i18n configuration file `src/i18nConfig.js`:
   - Import i18next and react-i18next
   - Import the translation file
   - Initialize with proper configuration

4. Update each component to use i18n:
   - Import `useTranslation` from 'react-i18next'
   - Call `const { t } = useTranslation()` in component
   - Replace hardcoded strings with `{t('translation.key')}`
   - For strings with variables, use interpolation: `{t('key', { name: userName })}`

## Verification

Checks for:
1. Translation file exists with valid JSON (20 points)
2. Translation file has good structure with 15+ keys (25 points)
3. i18nConfig.js exists with proper setup (15 points)
4. All 3 components updated to use i18n (40 points)

**Pass Threshold**: 70% (70/100 points)

## Tips

- Use Find in Files (Ctrl+Shift+F) to search for patterns like `>Text<` to find hardcoded strings
- Keep translation keys semantic: `login.submit_button` not `string_1`
- Remember: "John" in Dashboard is a variable (userName prop), not a translatable string
- Console.log messages are NOT user-facing - don't translate them