# VSCode Environment (`vscode_env`)

A comprehensive Visual Studio Code environment for `gym-anything`, designed for training agents on code editing, debugging, version control, refactoring, and IDE workflow tasks.

## Overview

This environment provides a complete VSCode setup with:
- **VSCode stable** (latest from Microsoft repository)
- **Pre-installed language runtimes**: Python 3.10+, Node.js 20.x, Java 17
- **Popular extensions**: Python, ESLint, Prettier, GitLens, Debugger for Chrome
- **Comprehensive verification utilities** for settings, extensions, Git, and file inspection
- **8 progressive tasks** from basic navigation to advanced refactoring
- **VNC access** for visual observation and debugging
- **Full GUI automation** support via `xdotool` and `wmctrl`

## Features

### Core Capabilities

1. **Code Editing**
   - IntelliSense autocomplete and suggestions
   - Syntax highlighting for 50+ languages
   - Multi-cursor editing
   - Code folding and minimap
   - Integrated terminal

2. **Debugging**
   - Breakpoint debugging for Node.js, Python, Java, C++
   - Variable inspection and watch expressions
   - Call stack navigation
   - Debug console and REPL

3. **Version Control (Git)**
   - Visual diff and merge tools
   - Stage, commit, push/pull operations
   - Branch management
   - Merge conflict resolution
   - GitLens extension for advanced Git features

4. **Code Navigation**
   - Go to Definition / Peek Definition
   - Find All References
   - Symbol search across workspace
   - Breadcrumb navigation
   - Outline view

5. **Refactoring**
   - Rename symbol across files
   - Extract function/variable
   - Organize imports
   - Code actions and quick fixes

6. **Extensions & Customization**
   - Command Palette for extension installation
   - Settings and keybindings customization
   - Workspace-specific configurations
   - Extension marketplace access

## Directory Structure

```
vscode_env/
├── env.json                          # Environment specification
├── README.md                         # This file
├── scripts/
│   ├── install_vscode.sh            # VSCode installation
│   ├── setup_vscode.sh              # VSCode configuration
│   └── task_utils.sh                # Shared task utilities
├── config/
│   ├── settings.json                # Default VSCode settings
│   └── keybindings.json             # Default keybindings
├── utils/
│   ├── __init__.py
│   └── vscode_verification_utils.py # Verification utilities
└── tasks/                            # Task definitions
    ├── README.md                     # Tasks overview
    ├── install_extension/            # Easy: Install extension via Command Palette
    ├── python_autocomplete/          # Easy: Write Python with autocomplete
    ├── navigate_definition/          # Easy: Go to Definition navigation
    ├── multi_cursor_edit/            # Easy: Multi-cursor editing
    ├── git_commit/                   # Medium: Stage and commit via Git UI
    ├── find_replace/                 # Medium: Find/replace across files
    ├── debug_javascript/             # Medium: Debug Node.js with breakpoints
    └── refactor_rename/              # Hard: Rename symbol across files
```

## Usage

### Quick Start

```python
import gym_anything as ga

# Load the VSCode environment
env = ga.from_config("examples/vscode_env")

# Reset the environment
obs = env.reset(seed=42)

# Environment is ready with VSCode launched
# VNC viewer accessible on port 5953
```

### Running Tasks

```bash
# Run a specific task
python -m gym_anything.cli run examples/vscode_env --task install_extension

# Validate task configuration
python -m gym_anything.cli validate examples/vscode_env --task install_extension

# Run all tasks sequentially
python -m gym_anything.cli run examples/vscode_env --all-tasks
```

### Creating Custom Tasks

Tasks should be placed in the `tasks/` directory. Each task needs:

1. **`task.json`**: Task specification
2. **`setup_task.sh`**: Pre-task setup script
3. **`export_result.sh`**: Post-task export script
4. **`verifier.py`**: Verification logic
5. **`assets/`** (optional): Sample code files, projects, templates

Example task structure:

```json
{
  "id": "my_custom_task@1",
  "version": "1.0",
  "env_id": "vscode_env@0.1",
  "description": "Perform a specific VSCode operation",
  "init": {
    "timeout_sec": 180,
    "max_steps": 50,
    "reward_type": "sparse"
  },
  "hooks": {
    "pre_task": "/workspace/tasks/my_custom_task/setup_task.sh",
    "post_task": "/workspace/tasks/my_custom_task/export_result.sh"
  },
  "success": {
    "spec": {
      "program": "verifier.py::verify_task"
    }
  }
}
```

## Task Overview

### 🟢 Easy Tasks

1. **Install Extension** (`install_extension`)
   - Use Command Palette (Ctrl+Shift+P) to install an extension
   - Verify extension appears in extensions list
   - **Skills**: Command Palette, extension management

2. **Python Autocomplete** (`python_autocomplete`)
   - Write a Python function using IntelliSense autocomplete
   - Verify function definition is correct
   - **Skills**: Code editing, IntelliSense, Python

3. **Navigate Definition** (`navigate_definition`)
   - Use Go to Definition (F12) to navigate to function definition
   - Verify cursor moved to correct file and line
   - **Skills**: Code navigation, keyboard shortcuts

4. **Multi-Cursor Edit** (`multi_cursor_edit`)
   - Use multi-cursor editing (Alt+Click or Ctrl+Alt+Down) to edit multiple lines
   - Verify all lines were modified correctly
   - **Skills**: Multi-cursor editing, text manipulation

### 🟡 Medium Tasks

5. **Git Commit** (`git_commit`)
   - Stage changes and commit via integrated Git interface
   - Verify commit was created with correct message
   - **Skills**: Git integration, version control

6. **Find and Replace** (`find_replace`)
   - Find and replace text across multiple files in workspace
   - Verify replacements were made correctly
   - **Skills**: Search, find/replace, workspace operations

7. **Debug JavaScript** (`debug_javascript`)
   - Set breakpoint and debug a Node.js application
   - Verify debug configuration was created and used
   - **Skills**: Debugging, breakpoints, Node.js

### 🔴 Hard Tasks

8. **Refactor Rename** (`refactor_rename`)
   - Rename a symbol across all files using refactoring tools
   - Verify symbol was renamed in all locations
   - **Skills**: Refactoring, code intelligence, multi-file editing

## User Accounts

The environment includes one pre-configured user account:

- **`ga`** (primary user)
  - Full sudo access with no password
  - Groups: sudo, audio, video, input, docker
  - Home: `/home/ga`
  - VNC display: `:1`
  - VSCode settings: `/home/ga/.config/Code/User/`

## Network Ports

- **5953**: VNC server (external access)

## File Locations

### VSCode Configuration
- **User settings**: `/home/ga/.config/Code/User/settings.json`
- **Keybindings**: `/home/ga/.config/Code/User/keybindings.json`
- **Extensions**: `/home/ga/.vscode/extensions/`
- **Workspace**: Task-specific (usually `/home/ga/workspace/`)

### Important Directories
- **User data**: `/home/ga/.config/Code/`
- **Extensions marketplace cache**: `/home/ga/.vscode/extensions/`
- **Workspace storage**: `/home/ga/.config/Code/User/workspaceStorage/`

### Task Files
- **Workspace**: `/home/ga/workspace/`
- **Task assets**: `/workspace/tasks/<task_id>/assets/`
- **Results**: Task-specific output locations

## Verification Utilities

The `utils/vscode_verification_utils.py` module provides helper functions:

```python
from vscode_verification_utils import *

# Parse VSCode settings
settings = parse_vscode_settings("/home/ga/.config/Code/User/settings.json")

# Check installed extensions
extensions = get_installed_extensions("/home/ga/.vscode/extensions")
has_python = check_extension_installed(extensions, "ms-python.python")

# Verify Git repository state
commits = get_git_commits("/home/ga/workspace/myproject")
latest_commit = commits[0] if commits else None

# Check file content
content = read_file_content("/home/ga/workspace/main.py")
has_function = "def my_function" in content

# Verify debug configuration
launch_config = parse_launch_json("/home/ga/workspace/.vscode/launch.json")
has_node_config = any(c.get('type') == 'node' for c in launch_config.get('configurations', []))
```

## GUI Automation

The environment includes `xdotool` and `wmctrl` for GUI automation:

```bash
# Focus VSCode window
wmctrl -a "Visual Studio Code"

# Open Command Palette
xdotool key ctrl+shift+p

# Type command
xdotool type "Extensions: Install Extensions"

# Take screenshot
import -window root screenshot.png
```

## VSCode CLI

VSCode provides a command-line interface:

```bash
# List installed extensions
code --list-extensions

# Install extension
code --install-extension ms-python.python

# Open workspace
code /home/ga/workspace

# Compare files
code --diff file1.txt file2.txt
```

## Logs

- **VSCode**: Check Output panel (View → Output)
- **Extensions**: `/home/ga/.config/Code/logs/`
- **Setup**: `/tmp/vscode_setup.log`

## Debugging

### Enable VNC Viewer
Connect to `localhost:5953` with password `password` to see the desktop.

### Check VSCode Status
```bash
# Inside container
ps aux | grep code
ls -la /home/ga/.config/Code/

# List extensions
code --list-extensions

# Check settings
cat /home/ga/.config/Code/User/settings.json
```

### Verify Language Servers
```bash
# Python language server
ps aux | grep pylance

# TypeScript language server
ps aux | grep tsserver
```

## Advanced Configuration

### Custom Settings

Modify `config/settings.json` to set default preferences:

```json
{
  "editor.fontSize": 14,
  "editor.tabSize": 4,
  "files.autoSave": "afterDelay",
  "git.autofetch": true,
  "python.linting.enabled": true
}
```

### Custom Keybindings

Modify `config/keybindings.json` for custom shortcuts:

```json
[
  {
    "key": "ctrl+shift+b",
    "command": "workbench.action.tasks.build"
  }
]
