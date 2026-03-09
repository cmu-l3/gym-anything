# Modernize Callback Pattern Task

**Difficulty**: 🟡 Medium  
**Skills**: Code refactoring, async programming, paradigm migration, multi-file editing  
**Duration**: 300 seconds  
**Steps**: ~100

## Objective

Convert a legacy Node.js module from error-first callback pattern to modern Promise/async-await pattern while preserving all functionality and error handling.

## Scenario

You're working on a legacy Node.js codebase that uses old-style error-first callbacks (callback hell). The team has decided to modernize to Promises/async-await for better readability and maintainability. Your task is to refactor the `file_processor.js` module and its tests.

## Expected Workflow

1. Open `/home/ga/workspace/callback_migration/file_processor.js`
2. Review the callback-based code structure
3. Convert each function to use `async/await` and Promises:
   - Replace `callback` parameters with return statements
   - Convert `function(err, result)` patterns to `async function`
   - Use `await` for asynchronous operations
   - Replace callback error handling with `try/catch` or `.catch()`
4. Update test file to use async/await
5. Verify syntax is valid

## Verification

Checks for:
1. No callback patterns remain (`function(err,`, `callback(`)
2. Async/await patterns present (`async`, `await`, minimum counts)
3. Error handling preserved (`try/catch`, `.catch()`)
4. Test file updated with async syntax
5. Code is syntactically valid

**Pass Threshold**: 80% (4/5 criteria)