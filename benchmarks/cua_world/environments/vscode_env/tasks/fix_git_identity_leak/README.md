# Fix Git Identity Leak Task

**Difficulty**: 🟡 Medium  
**Skills**: Git configuration, commit amendment, conditional config, identity management  
**Duration**: 300 seconds  
**Steps**: ~30

## Objective

Fix a privacy leak where a personal project commit was made with a work email address, and set up automatic git identity isolation for work vs personal projects.

## Scenario

You maintain both work and personal projects on the same machine. You just noticed your latest commit to your personal open-source project was accidentally made with your work email address (`dev@megacorp.com`). This is a privacy leak - you need to fix the commit and prevent this from happening again.

## Expected Workflow

### Part 1: Fix the Commit
1. Navigate to `/home/ga/workspace/personal/oss-library`
2. Open integrated terminal in VSCode
3. Amend the most recent commit to use personal identity:
   - Name: `Personal Dev`
   - Email: `personal.dev@example.com`
4. Use: `git commit --amend --author="Personal Dev <personal.dev@example.com>" --no-edit`

### Part 2: Set Up Conditional Git Config
1. Edit `~/.gitconfig` to add conditional includes: