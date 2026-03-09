# Configure Conditional Git Identity Task

**Difficulty**: 🔴 Hard  
**Skills**: Git configuration, conditional includes, identity management, professional workflows  
**Duration**: 300 seconds  
**Steps**: ~30

## Objective

Configure Git to automatically use different commit identities (name/email) based on which directory you're working in. This is essential for developers who work on both personal open-source projects and company proprietary code in the same workspace.

## Scenario

You're a developer who works on:
- **Personal open-source projects** in `/home/ga/workspace/personal-projects/`
- **Company proprietary code** in `/home/ga/workspace/company-work/`

You need commits in each directory to use the appropriate email address automatically, without manually switching identities.

## Expected Configuration

### Directory Structure