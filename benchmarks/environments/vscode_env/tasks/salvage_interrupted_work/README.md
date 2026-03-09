# Salvage Interrupted Work Task

**Difficulty**: 🟡 Medium  
**Skills**: Git operations, workspace management, selective staging, branching  
**Duration**: 300 seconds  
**Steps**: ~40

## Objective

Clean up a workspace with mixed uncommitted changes from two different features by properly separating, committing, and organizing them using Git branching and selective staging.

## Scenario

You were working on implementing JWT authentication when you got pulled into fixing an urgent production bug. You fixed the bug but forgot to commit it separately. Now your workspace has:
- **Bug fix changes** (completed): null safety checks in `users.js`, `products.js`, `logger.js`
- **Authentication feature** (incomplete): partial JWT implementation in `auth.js`, `middleware/auth.js`, `jwt.js`, `auth.test.js`

All changes are currently uncommitted on the `main` branch.

## Expected Workflow

1. **Open Source Control** (Ctrl+Shift+G) to view all changes
2. **Identify which files belong to each feature**:
   - Bug fix: `src/routes/users.js`, `src/routes/products.js`, `src/utils/logger.js`
   - Auth feature: `src/routes/auth.js`, `src/middleware/auth.js`, `src/utils/jwt.js`, `tests/auth.test.js`
3. **Commit bug fix to main**:
   - Stage ONLY the three bug fix files
   - Commit with message: "Fix: Add null safety checks to prevent crashes"
4. **Preserve incomplete auth work**:
   - Create and switch to branch: `feature/jwt-authentication`
   - Stage the four auth-related files
   - Commit with message: "WIP: JWT authentication implementation (incomplete)"
5. **Return to clean state**:
   - Switch back to `main` branch
   - Verify workspace is clean

## Verification

Checks for:
1. Currently on `main` branch
2. Workspace has no uncommitted changes
3. Branch `feature/jwt-authentication` exists
4. Bug fix commit on `main` with correct files
5. Auth WIP commit on feature branch with correct files

**Pass Threshold**: 75% (score ≥ 0.75)