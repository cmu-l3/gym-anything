# Consolidate Duplicate Utilities Task

**Difficulty**: 🟡 Medium  
**Skills**: Code refactoring, deduplication, module extraction, cross-file editing, Git  
**Duration**: 600 seconds  
**Steps**: ~100

## Objective

Consolidate duplicate email validation logic scattered across multiple JavaScript files into a single shared utility module. This simulates a common real-world scenario where code review feedback identifies technical debt from copy-pasted code.

## Scenario

You're working on a web application and a teammate points out: *"Hey, we're validating email addresses in like 4 different places with slightly different regex patterns. Can you consolidate that?"*

The codebase has email validation duplicated across:
- `src/components/RegistrationForm.js` - has `validateEmail()` function
- `src/components/LoginForm.js` - has `isValidEmail()` function (with a BUG: missing return statement)
- `src/services/UserService.js` - has `checkEmail()` method
- `src/services/NewsletterService.js` - MISSING validation entirely (should be added)

## Expected Workflow

1. **Find duplicates**: Use Find in Files (Ctrl+Shift+F) to locate all email validation code
2. **Create shared module**: Create `src/utils/emailValidator.js`
3. **Implement shared function**: Write ONE canonical `validateEmail` function with proper export
4. **Add documentation**: Include a comment explaining what the regex does
5. **Update all files**: Replace inline validation with imports from the shared module
6. **Fix the bug**: LoginForm.js has a missing `return` statement - fix it when consolidating
7. **Add missing validation**: NewsletterService.js should validate emails but doesn't
8. **Test imports**: Ensure require/import statements work correctly
9. **Commit changes**: Create a git commit describing the consolidation

## Verification

Checks for:
1. Shared `emailValidator.js` module exists in `src/utils/`
2. Module exports a validation function
3. Module contains email regex pattern
4. Module has documentation comment
5. All 4 files import from the shared module
6. Duplicate inline validation logic removed
7. Git commit with relevant message exists
8. LoginForm bug is fixed

**Pass Threshold**: 70/100 points