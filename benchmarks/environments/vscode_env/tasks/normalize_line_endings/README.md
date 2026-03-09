# Normalize Line Endings Task

**Difficulty**: 🟡 Medium  
**Skills**: Cross-platform development, Git configuration, VSCode settings, Line ending management  
**Duration**: 360 seconds  
**Steps**: ~50

## Objective

Fix a repository cloned from Windows developers where all files have CRLF line endings, causing Git to show false modifications on Linux. Configure the workspace to use LF endings, convert existing files, and set up `.gitattributes` to prevent future issues.

## Scenario

You've just cloned the `payment-service` repository to your Linux machine. The repository was developed primarily on Windows with CRLF line endings. Git shows dozens of files as "modified" even though you haven't changed anything. The shell script `scripts/deploy.sh` won't execute because it has Windows line endings.

## Expected Workflow

1. Recognize the line ending problem (Git shows all files modified)
2. Configure VSCode workspace to use LF endings (`.vscode/settings.json`)
3. Convert all text files from CRLF to LF (multiple methods possible)
4. Create `.gitattributes` to enforce LF endings for the team
5. Verify Git no longer shows false modifications

## Verification

Checks for:
1. VSCode workspace configured with `files.eol: "lf"`
2. Text files converted to LF endings (`.py`, `.js`, `.sh`, `.md`, `.json`)
3. Binary file (`logo.png`) not modified
4. `.gitattributes` file created with proper rules
5. Git status shows minimal changes (only config files)

**Pass Threshold**: 70% (2.8/4.0 criteria points)