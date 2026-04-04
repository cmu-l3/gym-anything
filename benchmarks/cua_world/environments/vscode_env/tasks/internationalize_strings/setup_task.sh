#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Internationalize Strings Task ==="

WORKSPACE_DIR="/home/ga/workspace/i18n_task"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create sample application with hardcoded strings
cat > "$WORKSPACE_DIR/app.js" << 'EOF'
// User authentication module
// TODO: Extract user-facing strings to i18n/en.json and refactor to use t() function

function authenticate(username, password) {
    // Dummy authentication - always returns true for demo
    return username.length > 0 && password.length > 0;
}

function handleLogin(username, password) {
    if (!username || !password) {
        return { error: "Please enter both username and password" };
    }
    
    console.log("DEBUG: Attempting login for user:", username);
    
    if (authenticate(username, password)) {
        console.log("DEBUG: Authentication successful");
        return { success: "Welcome back! Your login was successful." };
    } else {
        console.log("DEBUG: Authentication failed");
        return { error: "Invalid credentials. Please try again." };
    }
}

function renderLoginUI() {
    const submitButton = "Submit";
    const cancelButton = "Cancel";
    const titleText = "User Profile";
    const descriptionText = "Update your personal information below";
    
    console.log("DEBUG: Rendering UI components");
    
    return {
        title: titleText,
        description: descriptionText,
        buttons: [submitButton, cancelButton]
    };
}

function validateInput(email) {
    if (!email || email.length === 0) {
        return { valid: false, error: "Email is required" };
    }
    
    console.log("DEBUG: Validating email format");
    
    if (!email.includes("@")) {
        return { valid: false, error: "Please enter a valid email address" };
    }
    
    console.log("DEBUG: Email validation passed");
    return { valid: true };
}

module.exports = { handleLogin, renderLoginUI, validateInput };
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/app.js'" &
wait_for_vscode 25
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Internationalize Strings Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Examine app.js to identify user-facing strings"
echo "  2. Create i18n/en.json translation file"
echo "  3. Extract user-facing strings with semantic keys"
echo "  4. Add i18n import to app.js"
echo "  5. Replace hardcoded strings with t() calls"
echo "  6. Keep console.log debug messages unchanged"
echo ""
echo "Workspace: $WORKSPACE_DIR"
echo "File to refactor: app.js"