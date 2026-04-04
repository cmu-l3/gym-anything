# Update Breaking Dependency Task

**Difficulty**: 🟡 Medium  
**Skills**: Dependency management, npm, code migration, refactoring, documentation reading  
**Duration**: 240 seconds  
**Steps**: ~30

## Objective

Update the `axios` library from version 0.27.2 to 1.6.0+ to address a security vulnerability (CVE-2024-XXXXX), and migrate code to handle breaking changes in the error handling API.

## Scenario

Your team's payment API uses `axios@0.27.2`, which has a critical security vulnerability. You need to:
1. Update the dependency to axios 1.6.0 or later
2. Fix breaking changes in error handling code
3. Ensure all files are migrated to the new API

## Expected Workflow

1. Open the workspace in VSCode (`/home/ga/workspace/api-project`)
2. Read `MIGRATION_GUIDE.md` to understand the breaking changes
3. Update `package.json` to use `axios: "^1.6.0"`
4. Run `npm install` in the integrated terminal to install the new version
5. Update error handling in `lib/payment-client.js`:
   - Replace `error.request` checks with `error.code === 'ERR_NETWORK'`
6. Update error handling in `middleware/api-client.js`:
   - Replace `error.request` checks with `error.code === 'ERR_NETWORK'`
7. Save all files

## Key Changes Required

**Old pattern (axios 0.x):**