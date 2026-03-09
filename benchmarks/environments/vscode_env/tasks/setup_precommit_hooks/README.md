# Setup Pre-Commit Hooks Task

**Difficulty**: 🟡 Medium  
**Skills**: Git automation, Python tooling, configuration management, quality assurance  
**Duration**: 300 seconds  
**Steps**: ~40

## Objective

Configure pre-commit hooks for a Python project to automatically enforce code quality standards before each commit. This prevents bad code from being committed and reduces code review overhead.

## Scenario

You're on a development team that has been wasting time in code review on mechanical issues like:
- Inconsistent formatting (tabs vs spaces)
- Debug print() statements in production code
- Accidentally committed large files
- Nearly leaked secrets (hardcoded API keys)

Your team lead wants you to set up pre-commit hooks using the `pre-commit` framework to catch these issues before commits succeed.

## Expected Configuration

The `.pre-commit-config.yaml` should include hooks for:
1. **Black** - Python code formatter (line length 88)
2. **Flake8** - Python linter for style issues
3. **detect-secrets** - Catch accidentally committed secrets
4. **check-added-large-files** - Prevent files over 5MB

## Workflow

1. Install the `pre-commit` package (pip install)
2. Create `.pre-commit-config.yaml` in repository root
3. Configure the four required hooks
4. Run `pre-commit install` to activate hooks
5. Test hooks with `pre-commit run --all-files`
6. Fix any issues found by hooks
7. Add pre-commit to requirements file
8. Commit the configuration

## Verification

Checks for:
1. `.pre-commit-config.yaml` exists and is valid YAML
2. All four required hooks are configured
3. Git hooks installed in `.git/hooks/pre-commit`
4. `pre-commit` dependency documented in requirements file
5. Configuration committed to repository
6. Evidence hooks were tested (git history or formatted code)

**Pass Threshold**: 100% (all checks must pass for full credit), 50% for partial setup