# Resolve Circular Imports Task

**Difficulty**: 🟡 Medium  
**Skills**: Dependency analysis, code refactoring, module imports, debugging  
**Duration**: 300 seconds  
**Steps**: ~40

## Objective

Identify and resolve circular import dependencies in a Node.js project. The application crashes on startup due to a circular dependency chain between three modules. You must break the cycle by refactoring the code structure.

## Scenario

You just refactored a monolithic `utils.js` file into separate modules. Now the application crashes with `TypeError: Cannot read property of undefined`. Git blame shows you made the last changes. Your teammate is blocked and standup is in 30 minutes.

## Initial State

Three interconnected files:
- `validation.js` - imports from `formatting.js`
- `formatting.js` - imports from `database.js`
- `database.js` - imports from `validation.js` ← Creates cycle!

## Expected Solution Strategies

### Option A: Extract Shared Constants
Move the shared `errorPrefix` constant to `constants.js` and have both `formatting.js` and `database.js` import from there.

### Option B: Lazy Imports
Use `require()` inside function bodies instead of at module top level for non-critical dependencies.

### Option C: Dependency Inversion
Pass dependencies as function parameters instead of importing them directly.

## Expected Workflow

1. Open project in VSCode
2. Attempt to understand the error (optional: run `node index.js` in terminal)
3. Use "Find in Files" or navigate through imports to discover the cycle
4. Identify the problematic dependency
5. Refactor code to break the cycle (choose one strategy)
6. Verify the application can load successfully

## Verification

Checks for:
1. ✅ No circular dependencies exist (via import analysis)
2. ✅ All required files still exist
3. ✅ A valid fix strategy was applied
4. ✅ Application can load without crashing

**Pass Threshold**: 75% (3/4 criteria)

## Tips

- Use Ctrl+Click on imports to navigate between files
- Use Ctrl+Shift+F to search for import statements
- The integrated terminal (Ctrl+`) can help test changes with `node index.js`
- Look for the simplest solution first: shared constants