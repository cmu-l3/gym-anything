# Migrate CommonJS to ES Modules Task

**Difficulty**: 🟡 Medium  
**Skills**: JavaScript module systems, find/replace, configuration, refactoring  
**Duration**: 180 seconds  
**Steps**: ~60

## Objective

Migrate a Node.js authentication utility library from CommonJS (`require`/`module.exports`) to ES Modules (`import`/`export`) syntax. This simulates a real-world technical debt modernization task that thousands of Node.js projects face.

## Scenario

You're working on modernizing a Node.js backend service. The team wants to migrate from CommonJS to ES Modules for better tree-shaking and to align with modern JavaScript standards. You've been assigned to migrate the authentication module as a proof-of-concept.

## Initial State

The project at `/home/ga/workspace/auth-service/` contains:
- `src/auth.js` - Main authentication logic (uses CommonJS)
- `src/utils/hash.js` - Password hashing utilities (uses CommonJS)
- `src/config.js` - Configuration loader (uses CommonJS)
- `test/auth.test.js` - Basic tests (uses CommonJS)
- `package.json` - Standard CommonJS configuration
- `config.json` - Configuration data

## Expected Workflow

1. **Update package.json**:
   - Add `"type": "module"` to enable ES Modules

2. **Convert all require() statements** to import:
   - `const x = require('y')` → `import x from 'y'`
   - `const { a, b } = require('y')` → `import { a, b } from 'y'`
   - Add `node:` prefix for built-in modules (e.g., `import crypto from 'node:crypto'`)

3. **Convert all exports**:
   - `module.exports = X` → `export default X`
   - `module.exports = { a, b }` → `export { a, b }`

4. **Handle JSON imports**:
   - Use `import config from './config.json' assert { type: 'json' }` OR
   - Use `fs.readFileSync` with `import.meta.url`

5. **Fix CommonJS globals** (if present):
   - Replace `__dirname` with `fileURLToPath(new URL('.', import.meta.url))`

6. **Save all files** (Ctrl+S in each)

## Verification

Checks for:
1. `package.json` contains `"type": "module"`
2. No `require()` calls in source files (excluding comments)
3. All files use `import` statements
4. No `module.exports` or `exports.` assignments
5. Config file properly handles JSON loading

**Pass Threshold**: All 4 source files converted correctly + package.json configured

## Tips

- Use Find and Replace (Ctrl+H) across files for efficiency
- Remember to handle both named and default exports
- Don't forget to save each file after editing
- Check test files too—they also need migration