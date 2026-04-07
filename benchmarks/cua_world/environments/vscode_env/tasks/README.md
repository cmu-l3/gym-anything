# VSCode Tasks Suite - Complete Training Environment

## Overview

This comprehensive VSCode tasks suite provides a complete training environment for multimodal agents to learn code editing, debugging, version control, and IDE workflow skills. The suite consists of **8 carefully designed tasks** that progressively build from basic operations to advanced refactoring techniques, covering all essential VSCode workflows used in professional software development.

## Tasks Overview

| Task | Difficulty | Skills Tested | Primary Tools | Duration |
|------|------------|---------------|---------------|----------|
| [**Install Extension**](install_extension/) | 🟢 Easy | Command Palette, extension management | Command Palette, Extensions view | ~10 steps |
| [**Python Autocomplete**](python_autocomplete/) | 🟢 Easy | Code editing, IntelliSense | Editor, IntelliSense | ~15 steps |
| [**Navigate Definition**](navigate_definition/) | 🟢 Easy | Code navigation, keyboard shortcuts | Go to Definition (F12) | ~10 steps |
| [**Multi-Cursor Edit**](multi_cursor_edit/) | 🟢 Easy | Text editing, multi-cursor | Multi-cursor editing | ~15 steps |
| [**Git Commit**](git_commit/) | 🟡 Medium | Version control, Git UI | Source Control panel | ~20 steps |
| [**Find Replace**](find_replace/) | 🟡 Medium | Search, workspace operations | Find in Files | ~20 steps |
| [**Debug JavaScript**](debug_javascript/) | 🟡 Medium | Debugging, breakpoints | Debug panel, launch.json | ~25 steps |
| [**Refactor Rename**](refactor_rename/) | 🔴 Hard | Refactoring, code intelligence | Rename Symbol (F2) | ~20 steps |

## Skill Progression Matrix

### 🎯 **Interaction Skills Covered**
- **Keyboard Shortcuts**: Command Palette (Ctrl+Shift+P), Go to Definition (F12), Rename (F2), Find in Files (Ctrl+Shift+F)
- **Mouse Navigation**: File explorer, sidebar panels, context menus
- **Text Editing**: IntelliSense autocomplete, multi-cursor editing, find/replace
- **Panel Management**: Source Control, Debug, Extensions, Terminal, Output
- **Dialog Interaction**: Settings, preferences, extension marketplace

### 🛠️ **VSCode Knowledge Domains**
- **Core Editor**: IntelliSense, syntax highlighting, code folding, minimap
- **Navigation**: Go to Definition, Find References, Symbol Search, breadcrumbs
- **Refactoring**: Rename Symbol, Extract Function, Organize Imports
- **Debugging**: Breakpoints, watch expressions, call stack, debug console
- **Version Control**: Git staging, commits, diffs, branch management
- **Extensions**: Marketplace search, installation, configuration
- **Workspace**: Multi-file projects, settings, launch configurations

### 🎨 **Domain-Specific Skills**
- **Python Development**: IntelliSense, linting, formatting, debugging
- **JavaScript/Node.js**: Debugging, npm integration, TypeScript
- **Git Workflows**: Staging, committing, viewing history, conflict resolution
- **Code Quality**: Linting, formatting, refactoring, code actions

## Task Difficulty Progression

### 🟢 **Beginner Level (Easy)**

**Install Extension** - *Extension Management*
- **Skill Focus**: Command Palette usage, extension marketplace
- **Key Learning**: Keyboard shortcuts, dialog navigation, extension installation
- **Interaction Pattern**: Open Command Palette → Search extensions → Install

**Python Autocomplete** - *Code Editing with IntelliSense*
- **Skill Focus**: Code editing, autocomplete acceptance, IntelliSense
- **Key Learning**: Typing with suggestions, Tab/Enter for completion
- **Interaction Pattern**: Open file → Type code → Accept suggestions → Save

**Navigate Definition** - *Code Navigation*
- **Skill Focus**: Function navigation, keyboard shortcuts
- **Key Learning**: F12 shortcut, cursor positioning, file switching
- **Interaction Pattern**: Position cursor → Press F12 → Verify navigation

**Multi-Cursor Edit** - *Text Manipulation*
- **Skill Focus**: Multi-cursor editing, simultaneous text changes
- **Key Learning**: Alt+Click or Ctrl+Alt+Down for cursors, synchronized editing
- **Interaction Pattern**: Add cursors → Type changes → Verify all lines modified

### 🟡 **Intermediate Level (Medium)**

**Git Commit** - *Version Control*
- **Skill Focus**: Git staging, commit messages, Source Control panel
- **Key Learning**: Stage changes, write commit message, commit operation
- **Interaction Pattern**: Open Source Control → Stage → Commit with message

**Find Replace** - *Workspace Search*
- **Skill Focus**: Multi-file search and replace, workspace operations
- **Key Learning**: Ctrl+Shift+F, search patterns, replace operations
- **Interaction Pattern**: Open Find → Search → Replace across files

**Debug JavaScript** - *Debugging*
- **Skill Focus**: Breakpoint setting, debug configuration, Node.js debugging
- **Key Learning**: launch.json creation, breakpoint management, debug panel
- **Interaction Pattern**: Set breakpoint → Create debug config → Start debugging

### 🔴 **Advanced Level (Hard)**

**Refactor Rename** - *Code Intelligence*
- **Skill Focus**: Symbol renaming, refactoring, code intelligence
- **Key Learning**: F2 shortcut, rename across files, reference updates
- **Interaction Pattern**: Select symbol → Press F2 → Enter new name → Verify changes

## Verification Strategy

### 🔍 **Multi-Modal Verification System**

**Configuration File Analysis**
- **Settings Verification**: Parse `settings.json` for configuration changes
- **Launch Config**: Check `launch.json` for debug configurations
- **Workspace Files**: Verify `.vscode/` folder contents
- **Extension Manifest**: Check extensions directory for installed extensions

**File System Inspection**
- **File Content**: Read and verify file contents for code changes
- **File Existence**: Check for created or modified files
- **Directory Structure**: Verify workspace organization
- **Git Repository**: Check commit history and status

**Git Repository Analysis**
- **Commit History**: Parse `git log` for commit messages and metadata
- **Repository Status**: Check `git status` for staged/unstaged changes
- **Diff Analysis**: Verify file changes in commits
- **Branch State**: Check current branch and remote tracking

**Code Analysis**
- **Syntax Verification**: Check code syntax and structure
- **Symbol Detection**: Verify function/variable names and references
- **Import Analysis**: Check import statements and dependencies
- **Pattern Matching**: Use regex for code pattern detection

### 📊 **Scoring and Feedback System**
- **4-Criteria Evaluation**: Each task evaluates 4 key aspects for comprehensive assessment
- **Percentage Scoring**: 0-100% scores with detailed breakdown and feedback
- **Pass Threshold**: 75% minimum (3/4 criteria) ensures quality standards
- **Granular Feedback**: Specific feedback on each criterion with actionable insights

## Technical Architecture

### 🏗️ **File Structure**
```
tasks/
├── README.md                          # This overview
├── install_extension/                 # Extension management
├── python_autocomplete/               # IntelliSense code editing
├── navigate_definition/               # Code navigation
├── multi_cursor_edit/                 # Multi-cursor editing
├── git_commit/                        # Version control
├── find_replace/                      # Search and replace
├── debug_javascript/                  # Debugging
└── refactor_rename/                   # Refactoring
```

### ⚙️ **Shared Infrastructure**
**`task_utils.sh`** - Bash utilities for task setup:
- Window management (wait, focus)
- Process monitoring (VSCode, language servers)
- File operations (wait for file updates)
- xdotool wrappers for safe automation

**`vscode_verification_utils.py`** - Python verification utilities:
- Settings and configuration parsing
- Extension detection and verification
- Git repository inspection
- File content analysis

### 🐳 **Container Integration**
- **Base Environment**: `ubuntu-gnome-systemd_highres` with full desktop
- **VSCode Installation**: Latest stable from Microsoft repository
- **Language Runtimes**: Python 3.10+, Node.js 20.x, Java 17
- **VNC Access**: Port 5953 for visual observation
- **Automated Workflows**: Setup, execution, and export scripts

## Usage Guide

### 🚀 **Running Individual Tasks**
```bash
# Run specific task
python -m gym_anything.cli run examples/vscode_env --task install_extension

# Validate task configuration
python -m gym_anything.cli validate examples/vscode_env --task install_extension
```

### 🔄 **Training Sequences**
**Beginner Sequence**: `install_extension` → `python_autocomplete` → `navigate_definition` → `multi_cursor_edit`  
**Intermediate Sequence**: `git_commit` → `find_replace` → `debug_javascript`  
**Advanced Challenge**: `refactor_rename` (requires all previous skills)  
**Complete Mastery**: All 8 tasks in random order

### 📺 **VNC Debugging**
```bash
# Connect via VNC: vnc://localhost:5953
# Password: password
```

## Training Objectives

### 🎯 **Primary Learning Goals**
1. **IDE Mastery**: Proficient use of VSCode features and shortcuts
2. **Code Editing**: Efficient code writing with IntelliSense and multi-cursor
3. **Navigation**: Quick code navigation and symbol lookup
4. **Debugging**: Effective debugging with breakpoints and inspection
5. **Version Control**: Git workflow integration in IDE
6. **Refactoring**: Safe code refactoring with automated reference updates

### 📈 **Skill Development Trajectory**
- **Stage 1**: Basic navigation and editing (Easy tasks)
- **Stage 2**: Version control and search operations (Medium tasks)
- **Stage 3**: Debugging and complex workflows (Medium tasks)
- **Stage 4**: Advanced refactoring and code intelligence (Hard tasks)

### 🏆 **Mastery Indicators**
- **Consistent 90%+ scores** across all tasks
- **Efficient workflow execution** within time limits
- **Proper use of keyboard shortcuts** over mouse clicks
- **Understanding of IDE features** and when to use them

## Extensions and Customization

### 🔧 **Task Modification**
- Adjust timeout and step limits in `task.json`
- Modify verification criteria in `verifier.py`
- Change task difficulty by adding complexity

### 🎨 **New Task Development**
- Use existing tasks as templates
- Leverage `task_utils.sh` and verification utilities
- Follow established patterns for setup and export
- Document thoroughly in task README

---

## Quick Start

```bash
# 1. Validate all tasks
python -m gym_anything.cli validate examples/vscode_env

# 2. Run beginner sequence
python -m gym_anything.cli run examples/vscode_env --task install_extension
python -m gym_anything.cli run examples/vscode_env --task python_autocomplete
python -m gym_anything.cli run examples/vscode_env --task navigate_definition
python -m gym_anything.cli run examples/vscode_env --task multi_cursor_edit

# 3. Progress to intermediate
python -m gym_anything.cli run examples/vscode_env --task git_commit
python -m gym_anything.cli run examples/vscode_env --task find_replace
python -m gym_anything.cli run examples/vscode_env --task debug_javascript

# 4. Master advanced techniques
python -m gym_anything.cli run examples/vscode_env --task refactor_rename
```

This comprehensive VSCode training suite provides everything needed for world-class multimodal agent development in software development workflows! 🚀
