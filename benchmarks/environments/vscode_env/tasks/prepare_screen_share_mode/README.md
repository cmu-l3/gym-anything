# VSCode Screen Share Preparation Task (`prepare_screen_share_mode@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Settings management, UI configuration, workspace cleanup  
**Duration**: 120 seconds  
**Steps**: ~30

## Objective

Prepare VSCode for professional screen sharing by adjusting font sizes, zoom level, theme, and UI configuration to optimize readability for remote viewers.

## Scenario

You've been coding with personal development settings optimized for your 4K monitor. A client demo starts in 2 minutes and you need to screen share. Your VSCode currently has:
- Tiny fonts (11px editor, 12px terminal)
- Default zoom (100%)
- Dark theme
- Minimap enabled (takes space)
- Mixed work and personal files open

## Expected Workflow

1. Close personal/sensitive files (keep work files)
2. Open Settings (Ctrl+,) or edit settings.json directly
3. Increase editor font to 18-20px
4. Increase terminal font to 16-18px  
5. Set zoom level to 150%+ (View → Appearance → Zoom In, or settings)
6. Change theme to light/presentation theme (Ctrl+K Ctrl+T)
7. Disable minimap in settings
8. Verify workspace is clean and readable

## Verification

Checks for:
1. Editor font size: 18-22px (readable for viewers)
2. Terminal font size: 16-20px
3. Zoom level: ≥130% (1.3)
4. Theme changed to light or high-contrast
5. Minimap disabled
6. Work files still present in workspace

**Pass Threshold**: 71% (5/7 criteria)

## Tips

- Use Command Palette (Ctrl+Shift+P) for quick access
- Settings can be changed via UI (Ctrl+,) or by editing settings.json directly
- Zoom: View → Appearance → Zoom In (or Ctrl+=)
- Theme: File → Preferences → Color Theme (or Ctrl+K Ctrl+T)