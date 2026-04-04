# Exclude Heavy Directories Task

**Difficulty**: 🟡 Medium  
**Skills**: Workspace configuration, performance optimization, glob patterns, settings.json editing  
**Duration**: 300 seconds  
**Steps**: ~50

## Objective

Configure VSCode workspace settings to exclude heavy directories from file watching, search indexing, and the Explorer view to dramatically improve editor performance.

## Context

You've cloned a large monorepo on your laptop. VSCode has become painfully slow—file explorer is unresponsive, search hangs, and your CPU fan is spinning loudly. The problem is VSCode is trying to index massive directories that should be excluded:

- `node_modules/` (45,000+ npm dependency files)
- `build/` (10GB+ generated build outputs)
- `.venv/` (Python virtual environment)
- `vendor/` (Go vendor dependencies)
- `logs/` (large log files)

Your senior teammate suggests: *"Configure VSCode to exclude those directories from watching and search, or the editor will be unusable."*

## Expected Workflow

1. Open the monorepo workspace (already open in VSCode)
2. Create or open `.vscode/settings.json` in the workspace root
3. Add exclusion patterns for three settings:
   - `files.watcherExclude` - stops file system watching (reduces CPU/IO)
   - `search.exclude` - removes from search results (faster search)
   - `files.exclude` - hides from Explorer sidebar (cleaner UI)
4. For each setting, exclude all five directories using glob patterns
5. Save the file and verify VSCode picks up the changes

## Required Directories to Exclude

All five directories must be excluded from all three settings:
- `node_modules`
- `build`
- `.venv`
- `vendor`
- `logs`

## Glob Pattern Examples

Use patterns like:
- `**/node_modules/**`
- `**/build/**`
- `**/.venv/**`
- `**/vendor/**`
- `**/logs/**`

## Verification

Checks for:
1. `.vscode/settings.json` exists in workspace root
2. Valid JSON format
3. `files.watcherExclude` configured with all 5 directories
4. `search.exclude` configured with all 5 directories
5. `files.exclude` configured with all 5 directories

**Pass Threshold**: All 5 criteria must pass (100%)