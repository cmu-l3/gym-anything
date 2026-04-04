#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Custom File Associations Task ==="

WORKSPACE_DIR="/home/ga/workspace/microservices-project"
VSCODE_USER_DIR="/home/ga/.config/Code/User"

# Create workspace directory structure
sudo -u ga mkdir -p "$WORKSPACE_DIR/service-a"
sudo -u ga mkdir -p "$WORKSPACE_DIR/service-b"
sudo -u ga mkdir -p "$WORKSPACE_DIR/shared/templates"

# Create sample .svcconfig files (YAML format)
cat > "$WORKSPACE_DIR/service-a/app.svcconfig" << 'EOF'
# Service A Configuration
service:
  name: user-authentication-service
  port: 8080
  environment: development
database:
  host: localhost
  port: 5432
  name: users_db
logging:
  level: debug
  format: json
EOF

cat > "$WORKSPACE_DIR/service-b/app.svcconfig" << 'EOF'
# Service B Configuration
service:
  name: payment-processing-service
  port: 8081
  environment: development
redis:
  host: localhost
  port: 6379
  db: 0
EOF

# Create sample .route files (JSON with comments)
cat > "$WORKSPACE_DIR/service-a/api.route" << 'EOF'
{
  // Authentication routes
  "routes": [
    {
      "path": "/api/auth/login",
      "method": "POST",
      "handler": "AuthController.login"
    },
    {
      "path": "/api/auth/logout",
      "method": "POST",
      "handler": "AuthController.logout"
    }
  ]
}
EOF

# Create sample .tpl.html files (Handlebars templates)
cat > "$WORKSPACE_DIR/shared/templates/email.tpl.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
  <title>{{emailTitle}}</title>
</head>
<body>
  <h1>Welcome {{userName}}</h1>
  <p>{{emailBody}}</p>
  {{#if showButton}}
  <button>{{buttonText}}</button>
  {{/if}}
</body>
</html>
EOF

cat > "$WORKSPACE_DIR/shared/templates/notification.tpl.html" << 'EOF'
<div class="notification">
  <h2>{{notificationTitle}}</h2>
  <p>{{notificationMessage}}</p>
  <span class="timestamp">{{timestamp}}</span>
</div>
EOF

# Create a README explaining the file types
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Microservices Project

## Custom File Types

This project uses several custom file extensions:

- `.svcconfig`: Service configuration files (YAML format)
- `.route`: API route definitions (JSON format, supports comments)
- `.tpl.html`: Handlebars HTML templates

Please configure your editor to recognize these file types for proper syntax highlighting.

## Configuration Instructions

Add these file associations to VSCode settings:
- `*.svcconfig` → `yaml`
- `*.route` → `jsonc`
- `*.tpl.html` → `html`
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Ensure settings.json exists but REMOVE any existing file associations
# (we want the user to add them fresh)
sudo -u ga mkdir -p "$VSCODE_USER_DIR"

# Backup existing settings if they have file associations
if [ -f "$VSCODE_USER_DIR/settings.json" ]; then
    # Check if file associations exist and remove them
    sudo -u ga python3 << 'PYTHON_SCRIPT'
import json
import sys

settings_path = "/home/ga/.config/Code/User/settings.json"
try:
    with open(settings_path, 'r') as f:
        settings = json.load(f)
    
    # Remove file associations if they exist
    if "files.associations" in settings:
        # Keep other associations but remove our target ones
        associations = settings["files.associations"]
        for pattern in ["*.svcconfig", "*.route", "*.tpl.html"]:
            associations.pop(pattern, None)
        
        # If associations is now empty, remove the key entirely
        if not associations:
            del settings["files.associations"]
        else:
            settings["files.associations"] = associations
    
    with open(settings_path, 'w') as f:
        json.dump(settings, f, indent=2)
    
    print("Settings cleaned")
except Exception as e:
    print(f"Error cleaning settings: {e}", file=sys.stderr)
    # Create basic settings if there was an error
    basic_settings = {
        "telemetry.telemetryLevel": "off",
        "update.mode": "none",
        "files.autoSave": "afterDelay",
        "editor.fontSize": 14
    }
    with open(settings_path, 'w') as f:
        json.dump(basic_settings, f, indent=2)
PYTHON_SCRIPT
else
    # Create basic settings without file associations
    cat > "$VSCODE_USER_DIR/settings.json" << 'EOF'
{
  "telemetry.telemetryLevel": "off",
  "update.mode": "none",
  "files.autoSave": "afterDelay",
  "editor.fontSize": 14,
  "workbench.startupEditor": "none"
}
EOF
    sudo chown ga:ga "$VSCODE_USER_DIR/settings.json"
fi

# Open VSCode with workspace
echo "Opening VSCode with workspace..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open one sample file of each type to demonstrate the problem
sleep 2
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/service-a/app.svcconfig'" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/service-a/api.route'" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/shared/templates/email.tpl.html'" 2>/dev/null || true

sleep 2

echo "=== Configure Custom File Associations Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open Settings (Ctrl+, or File → Preferences → Settings)"
echo "  2. Search for 'file associations'"
echo "  3. Add these mappings:"
echo "     - *.svcconfig → yaml"
echo "     - *.route → jsonc"
echo "     - *.tpl.html → html"
echo "  4. Save settings (Ctrl+S)"
echo ""
echo "Current workspace: $WORKSPACE_DIR"
echo "Settings location: $VSCODE_USER_DIR/settings.json"