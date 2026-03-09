#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Create React Snippet Task ==="

# Create workspace directory for React project
WORKSPACE_DIR="/home/ga/workspace/react-app"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/components"

# Ensure VSCode user config directory exists
sudo -u ga mkdir -p /home/ga/.config/Code/User

# Remove any existing React snippets to ensure clean slate
sudo -u ga rm -f /home/ga/.config/Code/User/snippets/javascriptreact.json
sudo -u ga rm -f /home/ga/.config/Code/User/snippets/typescriptreact.json
sudo -u ga rm -f /home/ga/.config/Code/User/snippets/javascript.json
sudo -u ga rm -f /home/ga/.config/Code/User/snippets/typescript.json

# Create package.json for the React project
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "react-app",
  "version": "1.0.0",
  "description": "Sample React application for testing snippets",
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "typescript": "^5.0.0",
    "@types/react": "^18.2.0",
    "@types/react-dom": "^18.2.0"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build"
  }
}
EOF

# Create a sample existing React component for context
cat > "$WORKSPACE_DIR/src/App.tsx" << 'EOF'
import React from 'react';

function App() {
  return (
    <div className="App">
      <h1>React Snippet Test App</h1>
      <p>Create your custom snippet to speed up component creation!</p>
      <p>Try creating a new component file and using 'rfc' to test your snippet.</p>
    </div>
  );
}

export default App;
EOF

# Create an empty file where user could test the snippet
cat > "$WORKSPACE_DIR/src/components/NewComponent.tsx" << 'EOF'
// Test your snippet here:
// 1. Type 'rfc' and press Tab or Enter
// 2. Your snippet should expand into a full component template
// 3. Use Tab to navigate through placeholders

EOF

# Create tsconfig.json for TypeScript support
cat > "$WORKSPACE_DIR/tsconfig.json" << 'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "jsx": "react-jsx",
    "module": "ESNext",
    "moduleResolution": "node",
    "esModuleInterop": true,
    "skipLibCheck": true,
    "strict": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true
  },
  "include": ["src"]
}
EOF

# Create README with instructions
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# React Snippet Creation Task

## Your Task

Create a VSCode user snippet that generates React functional components.

## Steps

1. Press `Ctrl+Shift+P` to open Command Palette
2. Search for "Snippets: Configure User Snippets"
3. Select "typescriptreact.json" (or "javascriptreact.json")
4. Create a snippet with:
   - **Prefix**: `rfc`
   - **Description**: "React Functional Component with TypeScript and hooks"
   - **Body**: Component template with interface, useState, JSX return, export

## Required Elements in Snippet Body

Your snippet should generate code with these elements:
- TypeScript interface for props (e.g., `interface ComponentNameProps { propName: string; }`)
- Functional component using React.FC (e.g., `const ComponentName: React.FC<...> = ({ propName }) => {`)
- At least one useState hook (e.g., `const [state, setState] = useState('')`)
- JSX return statement with some content
- Default export (e.g., `export default ComponentName`)

## Testing (Optional)

After creating the snippet, open `src/components/NewComponent.tsx` and:
1. Type `rfc`
2. Press Tab or Enter
3. Your snippet should expand!

## VSCode Snippet Syntax Reminders

- Use `$1`, `$2`, `$3` for tab stops (cursor positions)
- Use `${1:defaultText}` for placeholders with default text
- Body should be an array of strings, one per line
- Escape special characters if needed
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the workspace
echo "Opening VSCode with React workspace..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/README.md'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Create React Snippet Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open Command Palette (Ctrl+Shift+P)"
echo "  2. Type 'Snippets: Configure User Snippets'"
echo "  3. Select 'typescriptreact.json' or 'javascriptreact.json'"
echo "  4. Create snippet with prefix 'rfc'"
echo "  5. Include: interface, component, useState, return, export"
echo "  6. Save the file (Ctrl+S)"
echo ""
echo "Workspace: $WORKSPACE_DIR"
echo "Snippet location: /home/ga/.config/Code/User/snippets/"