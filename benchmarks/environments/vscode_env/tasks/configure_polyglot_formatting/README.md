# VSCode Multi-Language Formatter Configuration Task (`configure_polyglot_formatting@1`)

**Difficulty**: 🟡 Medium  
**Skills**: VSCode settings, language-specific configuration, formatter setup  
**Duration**: 180 seconds  
**Steps**: ~20

## Objective

Configure language-specific formatters in VSCode for a multi-language project containing Python, JavaScript, and JSON files. Each language must use its appropriate formatter.

## Context

You're working on a full-stack project with Python backend, JavaScript frontend, and JSON configuration files. The team uses Black for Python and Prettier for JavaScript/JSON. You need to configure VSCode so each file type formats correctly.

## Expected Workflow

1. Open the workspace (opens automatically)
2. Notice the poorly formatted files (main.py, app.js, config.json)
3. Open VSCode settings (Ctrl+, or File → Preferences → Settings)
4. Click "Open Settings (JSON)" icon (top-right corner)
5. Add language-specific formatter configurations:
   - For Python: `ms-python.black-formatter` or `ms-python.python`
   - For JavaScript: `esbenp.prettier-vscode`
   - For JSON: `esbenp.prettier-vscode`
6. Save settings.json

## Required Configuration Format
