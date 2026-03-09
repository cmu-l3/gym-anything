# VSCode Unsaved Work Recovery Task

**Difficulty**: 🟡 Medium  
**Skills**: File recovery, system knowledge, VSCode internals, file operations  
**Duration**: 180 seconds  
**Steps**: ~25

## Objective

Recover three unsaved files from VSCode's backup directory after a simulated crash. This tests understanding of VSCode's internal backup mechanisms and file system navigation skills.

## Scenario

You were working on an urgent bug fix with multiple files open when your computer suddenly crashed. After restarting VSCode, some unsaved changes are missing from the editor. You need to manually recover them from VSCode's backup directory.

## Expected Workflow

1. Read the recovery instructions at `/home/ga/workspace/bugfix-project/RECOVERY_INSTRUCTIONS.md`
2. Navigate to VSCode's backup directory: `/home/ga/.config/Code/Backups/`
3. Find the workspace backup folder (cryptic hash-based name)
4. Locate three backup files with `.bak` extensions:
   - `authentication.py.[random-id].bak`
   - `user_settings.json.[random-id].bak`
   - `URGENT_NOTES.md.[random-id].bak`
5. Copy and restore them to correct locations:
   - → `src/authentication.py`
   - → `config/user_settings.json`
   - → `docs/URGENT_NOTES.md`
6. Verify content is correct

## Files to Recover

1. **authentication.py** - Contains bcrypt password hashing implementation
2. **user_settings.json** - Contains updated API timeout configuration
3. **URGENT_NOTES.md** - Contains root cause analysis of authentication bug

## Verification

Checks for:
1. All three files exist in correct workspace locations
2. `authentication.py` contains `import bcrypt` and `bcrypt.hashpw`
3. `user_settings.json` contains `"api_timeout": 30`
4. `URGENT_NOTES.md` contains "root cause: missing salt validation"
5. Files are readable and properly formatted

**Pass Threshold**: 100% (all files must be recovered correctly)