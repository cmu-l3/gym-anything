# Diagnose Missing Search Results Task

**Difficulty**: 🟡 Medium  
**Skills**: VSCode search configuration, settings management, troubleshooting  
**Duration**: 240 seconds  
**Steps**: ~30

## Objective

Diagnose why a specific file (`config/payment-providers.json`) is excluded from VSCode workspace search results and fix the configuration so the file becomes searchable.

## Scenario

You're conducting a security audit to find all references to `LEGACY_STRIPE_KEY` in the codebase. When you use "Find in Files" (Ctrl+Shift+F), you find results in several files, but you KNOW there's another file—`config/payment-providers.json`—that contains this string. You can see the file in the Explorer and open it manually, but it doesn't appear in search results.

## Expected Workflow

1. Use Find in Files (Ctrl+Shift+F) to search for "LEGACY_STRIPE_KEY"
2. Notice that `config/payment-providers.json` is missing from results
3. Open workspace settings (`.vscode/settings.json`)
4. Identify that `"**/*.json": true` in `search.exclude` is causing the issue
5. Remove or refine the exclusion pattern
6. Save settings
7. Verify the file now appears in search results

## Verification

Checks for:
1. Workspace settings modified to remove/refine JSON exclusion
2. `node_modules` still excluded (good practice preserved)
3. Settings file is valid JSON
4. The problematic blanket exclusion is gone

**Pass Threshold**: 75% (3/4 criteria)