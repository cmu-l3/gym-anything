# VSCode Dependency Conflict Resolution Task (`resolve_dependency_conflict@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Dependency management, error interpretation, terminal usage, file editing  
**Duration**: 180 seconds  
**Steps**: ~30

## Objective

Diagnose and resolve a Node.js dependency version conflict that prevents the application from running. The agent must read terminal error messages, identify conflicting package requirements, and update package.json to resolve the incompatibility.

## Scenario

You've just pulled changes from a teammate who updated some dependencies. Now when you try to run `npm install`, you encounter a peer dependency conflict error. The application won't start until this is resolved - a blocking issue that needs immediate attention.

## Expected Workflow

1. Read the terminal error message showing the dependency conflict
2. Identify which packages have incompatible requirements
3. Open package.json (Ctrl+P → type "package.json")
4. Update the conflicting package version to resolve the conflict
5. Save the file (Ctrl+S)
6. The export script will attempt to run `npm install` to verify resolution

## Initial State

- VSCode opens with a Node.js project
- Terminal shows failed `npm install` with ERESOLVE peer dependency error
- Error indicates: `react-dom@18.2.0` requires `react@^18.0.0` but found `react@17.0.2`
- The conflict is between React versions

## Solution

Update `package.json` to change `"react": "^17.0.2"` to `"react": "^18.0.0"` or newer, then save. This resolves the peer dependency conflict.

## Verification

Checks for:
1. **Configuration Modified**: package.json has been edited (20 points)
2. **Valid JSON Syntax**: Modified file parses correctly (20 points)
3. **Installation Succeeds**: npm install completes without errors (30 points)
4. **No Conflict Errors**: No ERESOLVE or peer dependency errors in output (25 points)
5. **Application Runnable**: App can start without module resolution errors (5 bonus points)

**Pass Threshold**: 75% (requires successful resolution and clean installation)

## Common Pitfalls

- Breaking JSON syntax (missing comma, quote)
- Updating wrong package (updating react-dom instead of react)
- Using non-existent version number
- Not saving the file after editing
- Modifying package-lock.json instead of package.json

## Tips

- Read the error message carefully - it tells you exactly what the conflict is
- The error shows: `Found: react@17.0.2` and `Requires: react@^18.0.0`
- Solution: Update the version that is "Found" to match what is "Requires"
- Use Ctrl+P for quick file navigation
- Semantic versioning: `^18.0.0` means ">=18.0.0 <19.0.0"