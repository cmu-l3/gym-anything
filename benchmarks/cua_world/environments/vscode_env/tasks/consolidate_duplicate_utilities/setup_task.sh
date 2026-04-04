#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Consolidate Duplicate Utilities Task ==="

WORKSPACE_DIR="/home/ga/workspace/email_validator_app"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Initialize Git repository
sudo -u ga git init
sudo -u ga git config user.name "GA User"
sudo -u ga git config user.email "ga@localhost"

# Create directory structure
sudo -u ga mkdir -p src/components
sudo -u ga mkdir -p src/services
sudo -u ga mkdir -p src/utils

# File 1: components/RegistrationForm.js
cat > "$WORKSPACE_DIR/src/components/RegistrationForm.js" << 'EOF'
// Registration form component
function RegistrationForm() {
  function validateEmail(email) {
    const regex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return regex.test(email);
  }

  function handleSubmit(email, password) {
    if (!validateEmail(email)) {
      alert("Invalid email");
      return false;
    }
    console.log("Registration successful");
    return true;
  }

  return { handleSubmit };
}

module.exports = RegistrationForm;
EOF

# File 2: components/LoginForm.js (with BUG - missing return)
cat > "$WORKSPACE_DIR/src/components/LoginForm.js" << 'EOF'
// Login form component
function LoginForm() {
  function isValidEmail(email) {
    const regex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    regex.test(email); // BUG: Missing return statement!
  }

  function handleLogin(email, password) {
    if (!isValidEmail(email)) {
      alert("Invalid email");
      return false;
    }
    console.log("Login successful");
    return true;
  }

  return { handleLogin };
}

module.exports = LoginForm;
EOF

# File 3: services/UserService.js (another variant)
cat > "$WORKSPACE_DIR/src/services/UserService.js" << 'EOF'
// User service
class UserService {
  checkEmail(email) {
    const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailPattern.test(email);
  }

  async createUser(email, name) {
    if (!this.checkEmail(email)) {
      throw new Error("Invalid email format");
    }
    // ... create user logic
    return { id: 1, email, name };
  }

  async updateUserEmail(userId, newEmail) {
    if (!this.checkEmail(newEmail)) {
      throw new Error("Invalid email format");
    }
    // ... update logic
    return { userId, email: newEmail };
  }
}

module.exports = UserService;
EOF

# File 4: services/NewsletterService.js (MISSING validation)
cat > "$WORKSPACE_DIR/src/services/NewsletterService.js" << 'EOF'
// Newsletter service
class NewsletterService {
  async subscribe(email) {
    // TODO: Should validate email before subscribing!
    console.log("Subscribing email:", email);
    return { subscribed: true, email };
  }

  async unsubscribe(email) {
    // Also should validate here
    console.log("Unsubscribing email:", email);
    return { subscribed: false, email };
  }
}

module.exports = NewsletterService;
EOF

# Create package.json
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "email-validator-app",
  "version": "1.0.0",
  "description": "App with duplicate email validation logic that needs consolidation",
  "main": "index.js"
}
EOF

# Create README
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Email Validator App

A simple application that needs refactoring to consolidate duplicate email validation logic.

## Known Issues
- Email validation is duplicated across multiple files
- One implementation has a bug (LoginForm missing return statement)
- NewsletterService should validate emails but doesn't

## Task
Consolidate all email validation into src/utils/emailValidator.js
EOF

# Set ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Initial commit
cd "$WORKSPACE_DIR"
sudo -u ga git add .
sudo -u ga git commit -m "Initial project setup with duplicate validation logic"

# Open VSCode to this workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Consolidate Duplicate Utilities Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Use Find in Files (Ctrl+Shift+F) to search for duplicate email validation"
echo "  2. Create src/utils/emailValidator.js with shared validateEmail function"
echo "  3. Update all 4 files to import from shared module"
echo "  4. Fix the bug in LoginForm.js (missing return)"
echo "  5. Add validation to NewsletterService.js"
echo "  6. Commit your changes (Ctrl+Shift+G)"