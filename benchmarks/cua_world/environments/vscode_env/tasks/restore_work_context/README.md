# Restore Work Context Task

**Difficulty**: 🟡 Medium  
**Skills**: Workspace management, file navigation, context switching  
**Duration**: 240 seconds  
**Steps**: ~30

## Objective

Reopen a Flask authentication service workspace and restore your working context by opening the three files you were editing before an interruption.

## Scenario

You're a backend developer who was implementing a password reset feature last Friday. An urgent production incident interrupted your work, and you haven't touched this project since. It's Monday morning, and you need to restore your working state.

## Expected Files to Open

1. `app/routes/auth.py` - Password reset route implementation
2. `app/services/email_service.py` - Email sending logic for reset tokens
3. `app/models/user.py` - User model with password methods

## Expected Workflow

1. Open the workspace (File > Open Recent or File > Open Folder)
2. Navigate to project: `/home/ga/projects/user-auth-service`
3. Open each of the three target files as editor tabs
4. Verify all three files are visible in the tab bar

## Verification

Checks for:
1. Correct workspace is open
2. `auth.py` is open as a tab
3. `email_service.py` is open as a tab
4. `user.py` is open as a tab

**Pass Threshold**: 75% (workspace + 2/3 files)