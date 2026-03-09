# Prepare Release Notes Task

**Difficulty**: 🟡 Medium  
**Skills**: Git integration, commit history review, categorization, technical writing, Markdown  
**Duration**: 360 seconds  
**Steps**: ~40

## Objective

Review Git commit history since the v1.5.0 tag and compile structured release notes for v2.0 in a CHANGELOG.md file. This task simulates preparing release documentation by filtering user-facing changes from internal development commits.

## Scenario

Your team is releasing v2.0 tomorrow and the project manager needs release notes by end of day. The repository has ~12 commits since the v1.5.0 tag with a mix of features, bug fixes, breaking changes, and internal updates. You must review the commits, identify user-facing changes, and create a well-structured CHANGELOG.

## Expected Workflow

1. Open Source Control panel (Ctrl+Shift+G) or use GitLens/Git Graph extension
2. Review commit history since tag v1.5.0
3. Identify user-facing changes:
   - ✅ New features
   - ✅ Bug fixes  
   - ✅ Breaking changes
   - ❌ Internal refactors
   - ❌ Test updates
   - ❌ Dependency bumps
4. Create `/home/ga/workspace/webapp/CHANGELOG.md`
5. Organize changes into sections: Features, Bug Fixes, Breaking Changes
6. Save the file

## Expected CHANGELOG Structure
