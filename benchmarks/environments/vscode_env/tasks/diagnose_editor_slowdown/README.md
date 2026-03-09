# Diagnose Editor Slowdown Task

**Difficulty**: 🟡 Medium  
**Skills**: Performance troubleshooting, extension management, settings configuration, diagnostic reasoning  
**Duration**: 480 seconds  
**Steps**: ~40

## Objective

Diagnose and fix VSCode performance issues by identifying problematic extensions and configuring performance-related settings. This task simulates the common real-world scenario where an editor becomes sluggish over time due to accumulated extensions and poor configuration.

## Scenario

You've been using VSCode for several months on a growing project. You've installed numerous extensions, and recently the editor has become frustratingly slow:
- Autocomplete suggestions take 3-5 seconds
- File switching is sluggish
- UI feels unresponsive with occasional typing lag
- High CPU usage even when idle

You have a pair programming session tomorrow and need to fix the performance issues tonight.

## Starting State

- Medium-sized TypeScript/Python project (~150 files)
- 8 extensions installed, including performance hogs:
  - **Bracket Pair Colorizer** (deprecated - native feature exists)
  - **GitLens** (all features enabled - memory intensive)
  - **TODO Highlight** (scanning entire workspace constantly)
  - ESLint, Prettier, and others
- File watchers monitoring everything including `node_modules/`
- No exclusion patterns configured
- GitLens showing blame annotations on every line

## Expected Actions

1. **Investigate current configuration** - identify what's causing slowdown
2. **Remove deprecated extensions** - Bracket Pair Colorizer has native replacement
3. **Optimize heavy extensions** - disable expensive GitLens features or remove it
4. **Configure performance settings**:
   - Exclude `node_modules/`, `dist/`, `.git/` from file watchers
   - Add search exclusion patterns
   - Reduce file watching overhead
5. **Document changes** in `PERFORMANCE_NOTES.md` explaining what you fixed

## Verification Criteria

✅ **Extension Cleanup** (25%):
- Bracket Pair Colorizer removed/disabled (required)
- At least one heavy extension (GitLens/TODO Highlight) optimized

✅ **Performance Settings** (25%):
- `files.watcherExclude` configured for node_modules, dist, .git
- `search.exclude` configured for node_modules
- `files.exclude` configured appropriately

✅ **GitLens Optimization** (25%):
- Either completely removed, OR
- Expensive features disabled (currentLine, codeLens, expensive hovers)

✅ **Documentation** (25%):
- `PERFORMANCE_NOTES.md` created in workspace root
- Contains at least 3 bullet points
- Mentions "extension" and "performance"
- At least 80 characters of content

## Tips

- Check `INITIAL_SETUP.md` in the workspace for current configuration details
- Use Extensions view (Ctrl+Shift+X) to manage extensions
- Settings can be configured in workspace (.vscode/settings.json) or user settings
- Look for settings with "exclude", "watch", "gitLens" in Settings UI (Ctrl+,)
- The native bracket matching feature makes Bracket Pair Colorizer redundant

## Pass Threshold

75% (3 out of 4 criteria must pass)