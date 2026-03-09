# Setup DevContainer Onboarding Task

**Difficulty**: 🟡 Medium  
**Skills**: DevContainer configuration, workspace settings, developer experience design  
**Duration**: 300 seconds  
**Steps**: ~100

## Objective

Configure a comprehensive development container setup for team onboarding. Create a batteries-included workspace that auto-configures VSCode with extensions, settings, tasks, and documentation for new developers joining a Python/FastAPI team.

## Expected Workflow

1. Create `.devcontainer/` directory in workspace
2. Create `devcontainer.json` with:
   - Python 3.11 base image
   - PostgreSQL feature/service
   - Required extensions (Python, Black formatter, Pylint, GitLens)
   - Container settings for formatting and linting
   - Post-create command to install requirements
3. Create `.vscode/settings.json` with team standards
4. Create `.vscode/extensions.json` with recommendations
5. Create `.vscode/tasks.json` with common development tasks
6. Create `QUICKSTART.md` onboarding guide

## Scenario

Your startup is growing fast and new developers spend 3+ days configuring their environment. Create a devcontainer setup so new hires are productive on day 1.

## Verification

Checks for:
1. DevContainer config with Python 3.11, PostgreSQL, required extensions
2. Workspace settings configured (linting, formatting, format-on-save)
3. Extension recommendations present
4. Tasks defined (test, format, dev server)
5. Quickstart guide created with helpful content

**Pass Threshold**: 80% (at least 8/10+ sub-checks passed)