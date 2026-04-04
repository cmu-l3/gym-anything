# Sanitize Hardcoded Secrets Task

**Difficulty**: 🟡 Medium  
**Skills**: Search, security awareness, environment variables, Git, refactoring  
**Duration**: 300 seconds  
**Steps**: ~100

## Objective

Remove hardcoded production secrets (API keys, passwords, credentials) from Python source files and migrate them to environment configuration before committing to Git.

## Scenario

You've been rapidly prototyping a payment processing feature and hardcoded real Stripe API keys, database passwords, and AWS credentials directly in the code. You're about to commit to GitHub and realize you're about to leak production secrets!

## Expected Workflow

1. **Find hardcoded secrets** using VSCode's search (Ctrl+Shift+F):
   - Search for patterns like: `sk_live_`, `AKIA`, `PASSWORD`, `SECRET`
   - Identify all files with secrets

2. **Create `.env` file** in workspace root with all secrets: