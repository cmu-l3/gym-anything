# Generate Release Changelog Task

**Difficulty**: 🟡 Medium  
**Skills**: Git history navigation, Source Control, text extraction, Markdown formatting  
**Duration**: 300 seconds  
**Steps**: ~80

## Objective

Generate a human-readable `CHANGELOG.md` file documenting changes between git tag `v2.0.0` and the current HEAD. This simulates the common Friday afternoon task of preparing release notes before deployment.

## Scenario

It's Friday at 4 PM. Your team is deploying v2.1.0 on Monday, and your product manager needs release notes for the announcement email. You have a git repository with 20+ commits since the last release (`v2.0.0`), including features, bug fixes, chores, and some noise commits (WIP, merge commits).

## Expected Workflow

1. Open the repository in VSCode (`/home/ga/workspace/sample-project`)
2. Navigate git history (using Source Control view, GitLens, or integrated terminal)
3. View commits between `v2.0.0` and `HEAD`
4. Categorize commits into:
   - **Features** (new functionality)
   - **Bug Fixes** (corrections)
   - **Chores** (dependencies, refactoring)
   - **Breaking Changes** (incompatible changes)
5. Filter out noise (merge commits, "wip", typo fixes)
6. Create `CHANGELOG.md` in repository root
7. Format using Markdown with proper sections
8. Save the file

## Expected Output Format
