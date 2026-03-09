# VSCode Colorblind Accessibility Configuration Task (`configure_colorblind_accessibility@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Accessibility, settings customization, theme management, color theory  
**Duration**: 300 seconds (5 minutes)  
**Steps**: ~40

## Objective

Configure VSCode for colorblind accessibility (deuteranopia - red-green colorblindness) by installing appropriate themes, customizing terminal colors, git diff colors, and error indicators to use distinguishable color schemes.

## Context

You are a developer with deuteranopia (red-green colorblindness) starting a new job. VSCode's default red/green color scheme makes it impossible to distinguish between errors/warnings, git additions/deletions, and terminal success/error messages. You need to configure VSCode for accessibility before tomorrow's sprint planning.

## Expected Workflow

1. **Install Colorblind-Friendly Theme** (Optional but recommended)
   - Open Command Palette (Ctrl+Shift+P)
   - Search for "Extensions: Install Extensions"
   - Search for "colorblind", "accessible", or "a11y" themes
   - Install a suitable extension

2. **Open Settings (JSON)**
   - Ctrl+Shift+P → "Preferences: Open Settings (JSON)"
   - Or Ctrl+, then click {} icon in top right

3. **Configure Terminal Colors**
   - Add `workbench.colorCustomizations` object
   - Modify ANSI terminal colors to avoid red/green:
     - Use blue/cyan for success indicators
     - Use orange/yellow for errors
     - Example: `"terminal.ansiGreen": "#00DDDD"` (cyan)
     - Example: `"terminal.ansiRed": "#FF8800"` (orange)

4. **Configure Git Diff Colors**
   - In same `workbench.colorCustomizations` object:
     - Set `diffEditor.insertedTextBackground` to blue-tinted (not green)
     - Set `diffEditor.removedTextBackground` to orange/yellow-tinted (not red)
     - Example: `"diffEditor.insertedTextBackground": "#0044AA44"`
     - Example: `"diffEditor.removedTextBackground": "#FF880044"`

5. **Configure Error Indicators**
   - Customize error colors to not rely solely on red:
     - `"editorError.foreground": "#FF8800"` (orange)
     - `"editorError.border": "#FF8800"`
   - Optional: Enable line highlighting for better context

6. **Save Settings** (Ctrl+S)

## Verification Criteria

The verifier checks 6 criteria (100 points total):

1. **✓ Colorblind Theme Extension Installed** (15 points)
   - Extension with keywords: colorblind, a11y, accessible, blinds
   
2. **✓ Theme Activated** (10 points)
   - Accessible theme selected OR custom color overrides present

3. **✓ Terminal Colors Customized** (25 points)
   - At least 3 ANSI colors modified
   - Colors avoid pure red (#FF0000) and pure green (#00FF00)
   - 8 points per properly configured color

4. **✓ Git Diff Colors Customized** (25 points)
   - Both insertion and removal backgrounds configured
   - Colors use blue/yellow instead of green/red
   - 12.5 points per diff color

5. **✓ Error Indicator Customization** (15 points)
   - Error colors or borders customized
   - Colors avoid pure red hue

6. **✓ Configuration Persistence** (10 points)
   - Settings saved to settings.json
   - Valid JSON format

**Pass Threshold**: 70 points (requires at least 4-5 criteria met)

## Test Files Provided

- `test_file_with_errors.py` - Python file with syntax errors for testing error highlighting
- `test_repo/` - Git repository with uncommitted changes for testing diff colors
- Terminal test commands provided in workspace

## Tips

- Search for "Daltonize" or "Colorblind" in extension marketplace
- Use online color contrast checkers for WCAG compliance
- Blue vs. Yellow provides best distinction for deuteranopia
- Avoid relying solely on color - use shape/position/intensity too
- Check WCAG AA standards: 3:1 contrast for large text, 4.5:1 for normal text

## Resources

- VSCode Color Theme docs: https://code.visualstudio.com/api/references/theme-color
- WCAG Color Contrast: https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html
- Colorblind simulation tools: coblis.com, color-blindness.com