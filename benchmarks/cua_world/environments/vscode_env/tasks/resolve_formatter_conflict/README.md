# Resolve Formatter Conflict Task

**Difficulty**: 🟡 Medium  
**Skills**: NPM package management, tool configuration, JSON editing  
**Duration**: 300 seconds  
**Steps**: ~60

## Objective

Configure ESLint and Prettier to work together without rule conflicts by installing `eslint-config-prettier` and updating ESLint configuration to extend it.

## Scenario

A developer cloned a project where Prettier and ESLint have conflicting formatting rules. The team decided to use Prettier for formatting and ESLint for code quality checks. Your task is to integrate them properly.

## Expected Workflow

1. Navigate to workspace: `/home/ga/workspace/webapp`
2. Open integrated terminal (Ctrl+`)
3. Install `eslint-config-prettier`: `npm install --save-dev eslint-config-prettier`
4. Open `.eslintrc.json`
5. Add `"prettier"` to the `extends` array (must be last to override other configs)
6. Save the file (Ctrl+S)

## Initial Conflicts

**ESLint rules** (`.eslintrc.json`):
- `semi: ["error", "always"]` (requires semicolons)
- `max-len: ["error", { "code": 80 }]` (80 char limit)
- `comma-dangle: ["error", "never"]` (no trailing commas)

**Prettier rules** (`.prettierrc.json`):
- `semi: false` (no semicolons)
- `printWidth: 100` (100 char limit)
- `trailingComma: "es5"` (trailing commas)

## Solution

Install `eslint-config-prettier` which disables all ESLint formatting rules that conflict with Prettier, allowing Prettier to handle formatting while ESLint handles code quality.

## Verification

Checks for:
1. `eslint-config-prettier` in `package.json` devDependencies
2. `"prettier"` in `.eslintrc.json` extends array
3. Both files are valid JSON

**Pass Threshold**: 100% (all 3 criteria must pass)