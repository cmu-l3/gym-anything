# Investigate Failing Test Task

**Difficulty**: 🟡 Medium  
**Skills**: Testing, Test Explorer, pytest, VSCode configuration  
**Duration**: 300 seconds  
**Steps**: ~30

## Objective

Your colleague pushed changes and the CI pipeline is now failing. You need to use VSCode's integrated Test Explorer to run pytest tests locally and identify what's failing. The project already has test files, but VSCode's testing features are not yet configured.

## Scenario

It's Monday morning, standup is in 30 minutes, and your team lead is asking about the failing build. You've pulled the latest code for a payment processing module. You need to quickly understand what test is broken by using VSCode's built-in testing capabilities (not just running pytest in terminal).

## Expected Workflow

1. Open the workspace in VSCode (may already be open)
2. Discover VSCode's Testing features (beaker icon in Activity Bar, or Command Palette)
3. Configure pytest as the test framework (enable in settings)
4. Wait for test discovery to complete
5. Run tests via Test Explorer UI
6. Identify the failing test(s)

## Project Structure
