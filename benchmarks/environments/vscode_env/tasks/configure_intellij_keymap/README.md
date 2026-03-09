# Configure IntelliJ Keymap Task

**Difficulty**: 🟡 Medium  
**Skills**: Keybindings, Extensions, Workflow customization, Editor migration  
**Duration**: 180 seconds  
**Steps**: ~20

## Objective

Configure VSCode to use IntelliJ IDEA-compatible keyboard shortcuts for core navigation commands. This simulates a developer migrating from IntelliJ/PyCharm to VSCode who wants to maintain their muscle memory.

## Context

Maria is a senior developer transitioning from IntelliJ IDEA to VSCode. She has 6 years of muscle memory for IntelliJ shortcuts and is losing productivity hitting the wrong keys. She needs VSCode configured with IntelliJ-compatible shortcuts for her most-used navigation commands.

## Two Valid Approaches

### Approach 1: Install Extension (Easier)
1. Open Extensions view (Ctrl+Shift+X)
2. Search for "IntelliJ IDEA Keybindings"
3. Install the extension by K--Kato or similar
4. Wait for installation to complete

### Approach 2: Manual Configuration (More Control)
1. Open Command Palette (Ctrl+Shift+P)
2. Type "Preferences: Open Keyboard Shortcuts (JSON)"
3. Add keybinding entries for each shortcut
4. Save the file

## Required Shortcuts

The following IntelliJ shortcuts must be mapped:

| IntelliJ Shortcut | VSCode Command | Purpose |
|-------------------|----------------|---------|
| `Ctrl+B` | Go to Definition | Jump to function/class definition |
| `Ctrl+Alt+B` | Go to Implementation | Jump to implementation |
| `Ctrl+N` | Go to Symbol | Search for symbols in workspace |
| `Ctrl+Shift+N` | Quick Open | Open file by name |
| `Ctrl+E` | Recent Files | Show recently opened files |

## Verification

Checks for:
1. IntelliJ keymap extension installed (automatic full credit)
2. OR manual keybindings.json configuration with all 5 shortcuts mapped

**Pass Threshold**: All 5 shortcuts configured (100%)