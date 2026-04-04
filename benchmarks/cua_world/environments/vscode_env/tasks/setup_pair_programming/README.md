# Setup Pair Programming Task

**Difficulty**: 🟡 Medium  
**Skills**: VSCode settings configuration, workspace preparation, documentation  
**Duration**: 300 seconds  
**Steps**: ~50

## Objective

Configure VSCode for a remote pair programming session by adjusting visibility settings and documenting the setup.

## Scenario

You're a senior developer about to pair program with a junior teammate remotely in 5 minutes. They'll be watching your screen while you debug code together. You need to prepare VSCode for better visibility during screen sharing.

## Expected Workflow

1. Open the project workspace at `/home/ga/workspace/pair_session`
2. Open VSCode Settings (Ctrl+, or File → Preferences → Settings)
3. Increase font size to 18 or larger for screen share readability
4. Enable whitespace rendering (set to "all", "boundary", or "trailing")
5. Ensure line numbers are visible
6. Create a file `session_notes.txt` in the workspace documenting:
   - Your name/role as session lead
   - Today's date
   - What settings you changed
   - A note that the workspace is ready for collaborative debugging

## Verification

Checks for:
1. Font size is 18 or larger
2. Whitespace rendering is enabled (not "none")
3. Line numbers are visible (not "off")
4. `session_notes.txt` exists in workspace
5. Session notes contain date, settings mentions, and readiness confirmation

**Pass Threshold**: 85% (all 5 criteria must pass for full score)