# Configure Custom File Associations Task

**Difficulty**: 🟡 Medium  
**Skills**: Workspace configuration, file associations, settings management  
**Duration**: 180 seconds  
**Steps**: ~20

## Objective

Configure VSCode to automatically recognize custom file extensions with proper syntax highlighting. The workspace contains three custom file types that currently show as plain text:

- `.svcconfig` files (service configuration in YAML format)
- `.route` files (API route definitions in JSON format)
- `.tpl.html` files (Handlebars HTML templates)

## Expected Workflow

1. Open VSCode Settings (Ctrl+,) or File → Preferences → Settings
2. Search for "file associations" in the settings search bar
3. Click "Edit in settings.json" or navigate to Text Editor → Files → Associations
4. Add file associations:
   - `*.svcconfig` → `yaml`
   - `*.route` → `jsonc`
   - `*.tpl.html` → `html`
5. Save settings (Ctrl+S)
6. Reopen files to verify syntax highlighting

**Alternative**: Directly edit `~/.config/Code/User/settings.json` and add: