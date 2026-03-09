#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Diagnose Editor Slowdown Task ==="

WORKSPACE_DIR="/home/ga/workspace/perf_project"
VSCODE_USER_DIR="/home/ga/.config/Code/User"
EXTENSIONS_DIR="/home/ga/.vscode/extensions"

# Clean up any existing workspace
sudo -u ga rm -rf "$WORKSPACE_DIR" 2>/dev/null || true
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create workspace directory structure
cd "$WORKSPACE_DIR"
sudo -u ga mkdir -p src/{components,services,utils,models}
sudo -u ga mkdir -p tests
sudo -u ga mkdir -p dist
sudo -u ga mkdir -p node_modules/{package1,package2,package3}

echo "Creating project files..."

# Create numerous dummy files to simulate a real project
for i in {1..50}; do
  echo "export const value$i = $i;" | sudo -u ga tee "src/utils/util$i.ts" > /dev/null
done

for i in {1..30}; do
  echo "export class Component$i {}" | sudo -u ga tee "src/components/Component$i.tsx" > /dev/null
done

for i in {1..20}; do
  echo "def function_$i(): pass" | sudo -u ga tee "src/services/service$i.py" > /dev/null
done

# Create package.json
cat | sudo -u ga tee "$WORKSPACE_DIR/package.json" > /dev/null << 'EOF'
{
  "name": "perf-project",
  "version": "1.0.0",
  "scripts": {
    "build": "tsc",
    "test": "jest"
  },
  "dependencies": {
    "react": "^18.0.0",
    "typescript": "^5.0.0"
  }
}
EOF

# Create tsconfig.json
cat | sudo -u ga tee "$WORKSPACE_DIR/tsconfig.json" > /dev/null << 'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "outDir": "./dist",
    "strict": true
  },
  "include": ["src/**/*"]
}
EOF

# Initialize Git repo
cd "$WORKSPACE_DIR"
sudo -u ga git init
sudo -u ga git config user.name "Test User"
sudo -u ga git config user.email "test@example.com"
sudo -u ga git add .
sudo -u ga git commit -m "Initial commit" 2>/dev/null || true

# Create workspace .vscode directory
sudo -u ga mkdir -p "$WORKSPACE_DIR/.vscode"

# Create minimal workspace settings (issues are at user level)
cat | sudo -u ga tee "$WORKSPACE_DIR/.vscode/settings.json" > /dev/null << 'EOF'
{
  "editor.formatOnSave": true
}
EOF

# Create informational document about current setup
cat | sudo -u ga tee "$WORKSPACE_DIR/INITIAL_SETUP.md" > /dev/null << 'EOF'
# Initial VSCode Configuration - Performance Issues

## Current Extension Configuration

The following extensions are currently ENABLED and may be causing performance issues:

### Problematic Extensions:

1. **Bracket Pair Colorizer** (coenraads.bracket-pair-colorizer)
   - STATUS: DEPRECATED 
   - ISSUE: Conflicts with native VSCode bracket matching (available since VSCode 1.60)
   - RECOMMENDATION: Remove/disable this extension

2. **GitLens** (eamodio.gitlens)
   - STATUS: All features enabled
   - ISSUES:
     - Blame annotations on every line (expensive Git operations)
     - CodeLens enabled (adds visual clutter and processing)
     - Expensive hover features on annotations
   - RECOMMENDATION: Disable expensive features or remove entirely

3. **TODO Highlight** (wayou.vscode-todo-highlight)
   - STATUS: Scanning entire workspace
   - ISSUE: Scanning binary files in node_modules directory
   - RECOMMENDATION: Disable or configure to exclude node_modules

### Other Extensions (Generally OK):

4. **ESLint** (dbaeumer.vscode-eslint) - Necessary but could be optimized
5. **Prettier** (esbenp.prettier-vscode) - Generally fine
6. **Auto Rename Tag** (formulahendry.auto-rename-tag) - Minimal impact
7. **Path Intellisense** (christian-kohler.path-intellisense) - Minimal impact
8. **Peacock** (johnpapa.vscode-peacock) - Cosmetic, minimal impact

## Current Performance Issues

### File Watching Problems:
- File watchers monitoring ALL files including node_modules/ (thousands of files)
- No exclusion patterns configured
- Git directory being watched unnecessarily
- Dist/build output directory being watched

### GitLens Overhead:
- `gitlens.currentLine.enabled: true` - showing blame on every line
- `gitlens.codeLens.enabled: true` - code lens on every function
- `gitlens.hovers.currentLine.over: annotation` - expensive hover computation
- `gitlens.blame.highlight.enabled: true` - highlighting blame constantly

### Search Overhead:
- No search exclusions configured
- Searching through node_modules and dist directories

## Recommended Fixes

1. **Remove Bracket Pair Colorizer** (deprecated, use native feature)
2. **Optimize or remove GitLens** (biggest performance impact)
3. **Configure files.watcherExclude** to exclude:
   - **/node_modules/**
   - **/dist/**
   - **/.git/**
4. **Configure search.exclude** to exclude node_modules
5. **Document your changes** in PERFORMANCE_NOTES.md

## How to Fix

- Open Extensions view: Ctrl+Shift+X
- Open Settings: Ctrl+, (or File > Preferences > Settings)
- Create PERFORMANCE_NOTES.md documenting your changes
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Configure user-level settings with performance problems
echo "Configuring problematic user settings..."
sudo -u ga mkdir -p "$VSCODE_USER_DIR"

cat | sudo -u ga tee "$VSCODE_USER_DIR/settings.json" > /dev/null << 'EOF'
{
  "telemetry.telemetryLevel": "off",
  "update.mode": "none",
  "extensions.autoUpdate": false,
  "editor.fontSize": 14,
  "editor.tabSize": 4,
  "workbench.colorTheme": "Default Dark+",
  "git.autofetch": true,
  "gitlens.currentLine.enabled": true,
  "gitlens.hovers.enabled": true,
  "gitlens.hovers.currentLine.over": "annotation",
  "gitlens.codeLens.enabled": true,
  "gitlens.blame.highlight.enabled": true,
  "todo-tree.general.tags": ["TODO", "FIXME", "NOTE", "BUG"],
  "todo-tree.tree.scanMode": "workspace"
}
EOF

# Create extension directories to simulate installed extensions
echo "Simulating installed extensions..."
sudo -u ga mkdir -p "$EXTENSIONS_DIR"

# Create dummy extension folders (these signal extensions are "installed")
sudo -u ga mkdir -p "$EXTENSIONS_DIR/coenraads.bracket-pair-colorizer-1.0.61"
sudo -u ga mkdir -p "$EXTENSIONS_DIR/eamodio.gitlens-13.5.0"
sudo -u ga mkdir -p "$EXTENSIONS_DIR/wayou.vscode-todo-highlight-1.0.5"
sudo -u ga mkdir -p "$EXTENSIONS_DIR/dbaeumer.vscode-eslint-2.4.2"
sudo -u ga mkdir -p "$EXTENSIONS_DIR/esbenp.prettier-vscode-10.1.0"
sudo -u ga mkdir -p "$EXTENSIONS_DIR/formulahendry.auto-rename-tag-0.1.10"
sudo -u ga mkdir -p "$EXTENSIONS_DIR/christian-kohler.path-intellisense-2.8.4"
sudo -u ga mkdir -p "$EXTENSIONS_DIR/johnpapa.vscode-peacock-4.2.2"

# Create package.json files inside extensions to make them look real
for ext_dir in "$EXTENSIONS_DIR"/*/; do
  if [ -d "$ext_dir" ]; then
    ext_name=$(basename "$ext_dir" | cut -d'-' -f1-2)
    echo "{\"name\": \"$ext_name\", \"version\": \"1.0.0\"}" | sudo -u ga tee "$ext_dir/package.json" > /dev/null
  fi
done

sudo chown -R ga:ga "$EXTENSIONS_DIR"

echo "Opening VSCode with workspace..."
# Open VSCode with the workspace and the informational document
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/INITIAL_SETUP.md'" &
wait_for_vscode 25
wait_for_window "Visual Studio Code" 35

# Click center to focus desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 640 400 click 1" || true
sleep 2

focus_vscode_window
sleep 1

echo "=== Diagnose Editor Slowdown Task Setup Complete ==="
echo ""
echo "📊 Current State:"
echo "  - Workspace: $WORKSPACE_DIR"
echo "  - Extensions: 8 installed (3 problematic)"
echo "  - Performance issues: File watchers, GitLens overhead, deprecated extensions"
echo ""
echo "📝 Task Instructions:"
echo "  1. Read INITIAL_SETUP.md to understand current configuration"
echo "  2. Remove/disable Bracket Pair Colorizer (deprecated)"
echo "  3. Optimize or remove GitLens extension"
echo "  4. Configure performance settings (files.watcherExclude, search.exclude)"
echo "  5. Create PERFORMANCE_NOTES.md documenting your changes"
echo ""
echo "💡 Hints:"
echo "  - Use Ctrl+Shift+X for Extensions view"
echo "  - Use Ctrl+, for Settings"
echo "  - Settings can be in workspace (.vscode/settings.json) or user settings"
echo "  - Document changes in PERFORMANCE_NOTES.md in workspace root"