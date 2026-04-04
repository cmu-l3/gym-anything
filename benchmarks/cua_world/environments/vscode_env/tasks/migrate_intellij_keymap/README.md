# Migrate IntelliJ Keymap Task

**Difficulty**: 🟢 Easy  
**Skills**: Configuration management, JSON editing, keybindings customization  
**Duration**: 180 seconds  
**Steps**: ~20

## Objective

Configure VSCode keybindings to replicate essential IntelliJ IDEA shortcuts, enabling smooth IDE migration for developers switching from IntelliJ/PyCharm.

## Context

A Java developer who has used IntelliJ IDEA for 5 years is joining a startup team that standardizes on VSCode. They need their most-used shortcuts to work immediately to maintain productivity during the transition.

## Required Keybindings

Configure these five IntelliJ-style shortcuts:

1. **Reformat Code**: `Ctrl+Alt+L` → Format Document
2. **Go to Declaration**: `Ctrl+B` → Go to Definition
3. **Find Usages**: `Alt+F7` → Find All References
4. **Optimize Imports**: `Ctrl+Alt+O` → Organize Imports
5. **Extract Method**: `Ctrl+Alt+M` → Refactor Menu

## Expected Workflow

**Method 1: Keyboard Shortcuts UI**
1. Press `Ctrl+K Ctrl+S` to open Keyboard Shortcuts
2. Search for "Format Document", click the + icon, press `Ctrl+Alt+L`, Enter
3. Repeat for other commands
4. Close the Keyboard Shortcuts panel

**Method 2: Edit keybindings.json directly**
1. Press `Ctrl+Shift+P` for Command Palette
2. Type "Preferences: Open Keyboard Shortcuts (JSON)"
3. Add the five keybindings in JSON format
4. Save the file (Ctrl+S)

## Expected JSON Format
