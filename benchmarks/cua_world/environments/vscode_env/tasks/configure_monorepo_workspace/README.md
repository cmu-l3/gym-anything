# Configure Monorepo Workspace Task

**Difficulty**: 🟡 Medium  
**Skills**: Workspace configuration, TypeScript project references, monorepo setup, performance optimization  
**Duration**: 300 seconds  
**Steps**: ~40

## Objective

Configure VSCode workspace settings to properly support a TypeScript monorepo with multiple packages. The starting state has a Yarn workspaces monorepo with 4 packages (`ui-components`, `api-client`, `backend`, `shared-utils`) that have cross-package imports showing errors. Your goal is to configure VSCode so that TypeScript IntelliSense works correctly across package boundaries.

## Expected Workflow

1. **Create Workspace Settings** (`.vscode/settings.json`):
   - Configure TypeScript for multi-project workspace mode
   - Set search exclusions to avoid searching in all `node_modules` folders
   - Configure file watcher exclusions for performance
   - Enable TypeScript project diagnostics

2. **Configure TypeScript Project References**:
   - Create or modify root `tsconfig.json` with `references` array pointing to all packages
   - Ensure packages have `composite: true` in their tsconfig.json

3. **Performance Optimizations**:
   - Exclude `**/node_modules`, `**/dist`, `**/build` from search
   - Exclude same patterns from file watchers

## Verification

The verifier checks for:
1. ✅ `.vscode/settings.json` exists
2. ✅ TypeScript workspace mode configured (multi-project settings)
3. ✅ Search exclusions include node_modules
4. ✅ Watcher exclusions configured for performance
5. ✅ Root tsconfig.json has project references (2+ packages)
6. ✅ At least one package has `composite: true` enabled

**Pass Threshold**: 83% (5 out of 6 criteria)

## Example Configuration

### `.vscode/settings.json`: