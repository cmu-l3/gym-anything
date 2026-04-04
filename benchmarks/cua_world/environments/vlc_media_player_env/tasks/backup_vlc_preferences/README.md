# Backup VLC Preferences Task

**Difficulty**: 🟡 Medium  
**Skills**: Configuration management, file operations, backup workflows  
**Duration**: 120 seconds  
**Steps**: ~25

## Objective

Export VLC preferences to a portable backup file that can be restored on any machine, preserving personalized configuration.

## Task Description

**Scenario**: You've spent time customizing VLC with specific settings - custom hotkeys, audio filters, interface tweaks, and default directories. You're getting a new computer and need to preserve these settings.

The agent must:
1. Locate VLC's configuration directory (`~/.config/vlc/`)
2. Identify essential preference files (vlcrc, vlc-qt-interface.conf)
3. Create a backup by copying files to `~/Documents/vlc_backup/`
4. Preserve configuration structure

## Expected Results

- Backup directory created at `/home/ga/Documents/vlc_backup/`
- Essential files backed up:
  - `vlcrc` (main preferences)
  - `vlc-qt-interface.conf` (UI settings)
- Custom settings preserved in backup
- Files are readable and valid

## Verification Criteria

1. ✅ **Backup Exists**: Backup directory contains files
2. ✅ **Essential Files**: vlcrc and vlc-qt-interface.conf present
3. ✅ **Content Valid**: Backed-up vlcrc contains custom settings
4. ✅ **File Integrity**: Files are non-empty and readable

**Pass Threshold**: 75%

## Skills Tested

- Understanding hidden directories (`~/.config/`)
- File system navigation
- Copy operations with structure preservation
- Configuration file identification
- Backup workflow understanding

## Real-World Relevance

This is an extremely common pain point. Users need to:
- Migrate settings to new computers
- Backup before OS reinstall
- Share "power user" configurations
- Restore after VLC crashes/corruption
- Standardize settings across work/home machines

## How to Complete

**Method 1: File Manager (GUI)**
1. Open file manager
2. Navigate to Home folder
3. Show hidden files (Ctrl+H)
4. Go to `.config/vlc/`
5. Copy `vlcrc` and `vlc-qt-interface.conf`
6. Paste to `Documents/vlc_backup/`

**Method 2: Terminal (CLI)**