# VSCode Environment Variables Configuration Task (`setup_env_variables@1`)

**Difficulty**: 🟡 Medium  
**Skills**: File creation, environment configuration, JSON editing, security practices  
**Duration**: 120 seconds  
**Steps**: ~50

## Objective

Configure a Node.js application with environment variables by creating a `.env` file and updating VSCode's launch configuration to load it. This tests the agent's ability to set up development environments with proper secret management.

## Scenario

You've cloned a Node.js application (`app.js`) that requires database credentials and API keys to run. The repository doesn't include these secrets (for security reasons), so you must create a local `.env` file and configure VSCode's debugger to load these variables.

## Expected Workflow

1. **Create `.env` file** in workspace root with required variables
2. **Edit `.vscode/launch.json`** to add envFile property
3. **Verify `.gitignore`** includes `.env` (already configured)
4. **Save all files**

## Required Environment Variables

Create `/home/ga/workspace/env_task/.env` with: