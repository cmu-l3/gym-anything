# VSCode Workspace Recovery Task (`recover_corrupted_workspace@1`)

**Difficulty**: 🔴 Hard  
**Skills**: Troubleshooting, diagnostic tools, state management, systematic debugging  
**Duration**: 300 seconds  
**Steps**: ~60

## Objective

Diagnose and repair a corrupted VSCode workspace where extensions have failed to load, settings appear broken, and IntelliSense is not working. The workspace became corrupted after a simulated crash, leaving it in an inconsistent state.

## Scenario

You've just opened VSCode after a system crash, and things aren't working:
- Python extension shows "Failed to activate"
- Settings JSON has a syntax error
- IntelliSense doesn't trigger
- Extension Host shows errors in logs
- Workspace storage may be corrupted

Your goal: systematically diagnose the problem, fix it, and restore full functionality.

## Expected Workflow

1. **Recognize the Problem**: Notice extension errors, broken IntelliSense
2. **Check Diagnostics**: Open Developer tools, check logs
3. **Inspect Settings**: Find and fix settings.json syntax error
4. **Diagnose Extensions**: Disable all extensions, then selectively re-enable
5. **Clear Cache** (if needed): Remove corrupted workspace storage
6. **Verify Recovery**: Test that IntelliSense and extensions work
7. **Document**: Create RECOVERY_LOG.md explaining what was broken and how you fixed it

## Verification Criteria

The verifier checks:
- ✅ **Settings Valid** (25%): settings.json has no syntax errors
- ✅ **Extensions Working** (25%): Python extension loaded successfully
- ✅ **No Active Errors** (15%): No extension failures or persistent errors
- ✅ **IntelliSense Functional** (15%): Language features are working
- ✅ **Recovery Documented** (10%): RECOVERY_LOG.md exists with explanation
- ✅ **Systematic Approach** (10%): Evidence of diagnostic steps taken

**Pass Threshold**: 75% (restore core functionality + document process)

## Tips

- Use `Ctrl+Shift+P` → "Developer: Show Logs" to see error details
- Check Output panel → "Log (Extension Host)" for extension errors
- Settings JSON is at: `File → Preferences → Settings` → Click `{}` icon
- Disable extensions: `Ctrl+Shift+P` → "Extensions: Disable All Installed Extensions"
- Reload window: `Ctrl+Shift+P` → "Developer: Reload Window"

## Common Recovery Steps

1. **For Settings Errors**: Edit settings.json directly, fix JSON syntax
2. **For Extension Failures**: Disable all → Reload → Enable one-by-one
3. **For Cache Issues**: Close VSCode, delete workspace storage, reopen
4. **For Language Server Issues**: Restart extension host or reload window