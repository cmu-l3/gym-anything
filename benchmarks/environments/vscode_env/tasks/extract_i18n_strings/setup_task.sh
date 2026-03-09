#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Extract i18n Strings Task ==="

WORKSPACE_DIR="/home/ga/workspace/dashboard-app"
TASK_ASSETS="/workspace/tasks/extract_i18n_strings/assets"

# Create workspace structure
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/components"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/locales"

# Copy React component files with hardcoded strings
echo "Creating React components with hardcoded strings..."

cat > "$WORKSPACE_DIR/src/components/Header.jsx" << 'EOF'
import React from 'react';

function Header() {
  return (
    <header className="app-header">
      <h1>Company Dashboard</h1>
      <nav>
        <a href="/home">Home</a>
        <a href="/analytics">Analytics</a>
        <a href="/settings">Settings</a>
        <a href="/help">Help Center</a>
      </nav>
    </header>
  );
}

export default Header;
EOF

cat > "$WORKSPACE_DIR/src/components/LoginForm.jsx" << 'EOF'
import React, { useState } from 'react';

function LoginForm() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');

  const handleSubmit = (e) => {
    e.preventDefault();
    console.log('Form submitted');
    
    if (!email || !password) {
      alert('Please fill in all fields');
      return;
    }
    
    // API call would go here
    alert('Login successful!');
  };

  return (
    <div className="login-form">
      <h2>Sign In to Your Account</h2>
      <form onSubmit={handleSubmit}>
        <div className="form-group">
          <label htmlFor="email">Email Address</label>
          <input 
            id="email"
            type="email" 
            placeholder="Enter your email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />
        </div>
        <div className="form-group">
          <label htmlFor="password">Password</label>
          <input 
            id="password"
            type="password" 
            placeholder="Enter your password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
        </div>
        <button type="submit" className="btn-primary">
          Login
        </button>
        <a href="/forgot-password" className="forgot-link">
          Forgot your password?
        </a>
      </form>
    </div>
  );
}

export default LoginForm;
EOF

cat > "$WORKSPACE_DIR/src/components/Dashboard.jsx" << 'EOF'
import React from 'react';

function Dashboard({ userName }) {
  return (
    <div className="dashboard">
      <h1>Welcome back, {userName}!</h1>
      <p>Here's an overview of your account activity</p>
      
      <div className="stats-grid">
        <div className="stat-card">
          <h3>Total Users</h3>
          <p className="stat-value">1,234</p>
        </div>
        <div className="stat-card">
          <h3>Active Sessions</h3>
          <p className="stat-value">89</p>
        </div>
        <div className="stat-card">
          <h3>Revenue This Month</h3>
          <p className="stat-value">$45,678</p>
        </div>
      </div>
      
      <button className="refresh-btn">Refresh Data</button>
    </div>
  );
}

export default Dashboard;
EOF

cat > "$WORKSPACE_DIR/src/App.jsx" << 'EOF'
import React from 'react';
import Header from './components/Header';
import LoginForm from './components/LoginForm';
import Dashboard from './components/Dashboard';

function App() {
  return (
    <div className="app">
      <Header />
      <main>
        <Dashboard userName="John" />
      </main>
    </div>
  );
}

export default App;
EOF

# Create package.json
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "dashboard-app",
  "version": "1.0.0",
  "description": "Dashboard application ready for i18n",
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-i18next": "^12.0.0",
    "i18next": "^22.0.0"
  },
  "scripts": {
    "start": "react-scripts start"
  }
}
EOF

# Create README with instructions
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Dashboard App - i18n Extraction Task

## Goal
Extract hardcoded English strings and set up internationalization.

## Files to work with:
- src/components/Header.jsx
- src/components/LoginForm.jsx  
- src/components/Dashboard.jsx

## What to create:
1. src/locales/en.json - Translation file with all user-facing strings
2. src/i18nConfig.js - i18n setup and configuration

## What to modify:
Update all 3 components to use useTranslation hook and t() function.

## Strings to extract:
✅ Button labels, headings, form labels
✅ Navigation items  
✅ Placeholder text
✅ Alert/error messages shown to users
❌ console.log messages
❌ className values
❌ Variable names

Good luck!
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode to workspace
echo "Opening VSCode to dashboard-app workspace..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' --reuse-window" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 3
focus_vscode_window

# Open the first component file to get started
sleep 2
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/src/components/Header.jsx'" || true
sleep 1

echo "=== Extract i18n Strings Task Setup Complete ==="
echo "📁 Workspace: $WORKSPACE_DIR"
echo "📝 Components with hardcoded strings:"
echo "   - src/components/Header.jsx"
echo "   - src/components/LoginForm.jsx"
echo "   - src/components/Dashboard.jsx"
echo ""
echo "✅ Tasks:"
echo "   1. Create src/locales/en.json with translations"
echo "   2. Create src/i18nConfig.js with i18n setup"
echo "   3. Update all 3 components to use i18n"