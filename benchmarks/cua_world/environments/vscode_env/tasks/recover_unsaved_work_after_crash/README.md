# VSCode Crash Recovery Task (`recover_unsaved_work_after_crash@1`)

**Difficulty**: 🟡 Medium  
**Skills**: VSCode Hot Exit, crash recovery, workspace restoration  
**Duration**: 180 seconds  
**Steps**: ~20

## Overview

This task tests an agent's ability to recover work after an ungraceful VSCode termination. The agent must understand VSCode's "Hot Exit" feature, which automatically preserves unsaved file contents and workspace state even when the application crashes.

## Objective

Recover unsaved work after a simulated VSCode crash and verify all changes were preserved.

## Scenario

You were working on a critical bug fix across three Python files when your laptop battery suddenly died—instant shutdown. When you restart, you need to verify VSCode's automatic crash recovery (Hot Exit) preserved your unsaved work.

**Modified files (unsaved at crash):**
- `routes.py` - Added new `get_data()` API endpoint function
- `validation.py` - Added new `validate_email()` validation function
- `test_validation.py` - Added new `test_email_validation()` test method

## Expected Workflow

1. **Reopen VSCode** - Launch VSCode or wait for it to auto-restart
2. **Observe Recovery** - VSCode should automatically restore the workspace with unsaved changes
3. **Verify Changes** - Check that files show as modified (dirty markers - dots in tabs)
4. **Confirm Content** - Verify the three files contain the expected new functions
5. **Save All** - Press `Ctrl+K S` (or File → Save All) to persist the recovered work

## Verification Criteria

The verifier checks that all recovered changes were saved:

1. ✅ **routes.py** contains `get_data()` function that returns JSON data
2. ✅ **validation.py** contains `validate_email()` function with regex validation
3. ✅ **test_validation.py** contains `test_email_validation()` test method
4. ✅ **Implementation correctness** - Functions have proper return statements and logic

**Pass Threshold**: 75% (3/4 criteria must pass)

## VSCode Hot Exit Feature

**What is Hot Exit?**
- Automatic feature that preserves unsaved changes even when VSCode crashes
- Saves workspace state: open files, tabs, cursor positions, unsaved content
- Enabled by default with `"files.hotExit": "onExit"` setting
- Backups stored in `~/.config/Code/Backups/` (Linux)

**When It Activates:**
- Application crashes (e.g., kill -9)
- System shutdown without saving
- Battery death
- Force quit

**What Gets Preserved:**
- Unsaved file modifications
- Untitled files (never saved)
- Workspace folder/file layout
- Tab order and states
- Cursor positions

## Skills Tested

- **Crash Recovery Awareness**: Understanding VSCode's safety mechanisms
- **Hot Exit Knowledge**: Knowing that VSCode auto-preserves unsaved work
- **Workspace Restoration**: Recognizing when automatic recovery occurred
- **Dirty File Detection**: Identifying unsaved changes (visual markers)
- **Save Operations**: Using Save All commands properly

## Common Issues

❌ **Agent doesn't reopen VSCode** - May not realize it needs to launch the application  
❌ **Opens different workspace** - Opens wrong folder, old workspace not restored  
❌ **Doesn't recognize recovery** - May not notice the dirty file indicators  
❌ **Forgets to save** - Recovery worked but files not saved to disk  
❌ **Saves wrong content** - Modifies files instead of preserving recovered content  

## Tips

💡 VSCode usually auto-restarts and restores workspace after a crash  
💡 Look for dots/circles in file tabs - indicates unsaved changes  
💡 Use `Ctrl+K S` for "Save All" to quickly save multiple files  
💡 Hot Exit works even for brand-new files never saved before  
💡 The feature is enabled by default - no configuration needed  

## Learning Outcomes

After completing this task, agents should understand:

1. VSCode Hot Exit automatically preserves unsaved work
2. Recovery happens transparently on application restart  
3. Backups persist even through crashes and force quits
4. Workspace state includes more than just file contents
5. The `files.hotExit` setting controls this behavior

## Related VSCode Features

- **Auto Save**: `files.autoSave` - prevents unsaved changes entirely
- **Workspace Storage**: Where VSCode persists session state
- **Recent Files**: File → Open Recent for manual workspace reopening
- **Backup Directory**: `~/.config/Code/Backups/` contains Hot Exit backups

## Expected Execution Time

- **Novice agent**: 40-60 seconds (exploring, verifying recovery)
- **Experienced agent**: 15-25 seconds (reopen, verify, save)
- **Human expert**: 5-10 seconds (trust Hot Exit, quick check, save)

## Success Indicators

✅ VSCode reopens with previous workspace  
✅ Three files are open in tabs with unsaved indicators  
✅ File contents match expected modifications  
✅ All files saved successfully (no data loss)  

---

This task builds confidence in VSCode's reliability and teaches agents about crash recovery mechanisms—critical knowledge for real-world development where interruptions are inevitable.