#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Bundle Size Analysis Task ==="

WORKSPACE_DIR="/home/ga/workspace/react-app"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create package.json with intentionally bloated dependencies
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "react-app-bloated",
  "version": "1.0.0",
  "description": "React app with bundle size issues",
  "main": "index.js",
  "scripts": {
    "build": "webpack --mode production --json > dist/stats.json",
    "test": "echo \"No tests\" && exit 0"
  },
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "lodash": "^4.17.21",
    "moment": "^2.29.4",
    "chart.js": "^4.4.0",
    "axios": "^1.6.0",
    "date-fns": "^2.30.0"
  },
  "devDependencies": {
    "webpack": "^5.89.0",
    "webpack-cli": "^5.1.4"
  }
}
EOF

# Create minimal webpack config
cat > "$WORKSPACE_DIR/webpack.config.js" << 'EOF'
const path = require('path');

module.exports = {
  entry: './src/index.js',
  output: {
    filename: 'bundle.js',
    path: path.resolve(__dirname, 'dist'),
  },
  mode: 'production',
};
EOF

# Create src directory with sample app
sudo -u ga mkdir -p "$WORKSPACE_DIR/src"

cat > "$WORKSPACE_DIR/src/index.js" << 'EOF'
import _ from 'lodash';
import moment from 'moment';
import { Chart } from 'chart.js';
import axios from 'axios';

const data = _.range(1, 100);
const now = moment().format('YYYY-MM-DD');

console.log('App loaded', data, now);
console.log('Chart available:', typeof Chart);
console.log('Axios available:', typeof axios);
EOF

# Create dist directory with pre-built bundle and stats
sudo -u ga mkdir -p "$WORKSPACE_DIR/dist"

# Create realistic stats.json for webpack-bundle-analyzer
cat > "$WORKSPACE_DIR/dist/stats.json" << 'EOF'
{
  "assets": [
    {
      "name": "bundle.js",
      "size": 867234
    }
  ],
  "modules": [
    {
      "name": "./node_modules/lodash/lodash.js",
      "size": 236589,
      "reasons": [{"moduleName": "./src/index.js"}]
    },
    {
      "name": "./node_modules/moment/moment.js",
      "size": 193456,
      "reasons": [{"moduleName": "./src/index.js"}]
    },
    {
      "name": "./node_modules/chart.js/dist/chart.js",
      "size": 172345,
      "reasons": [{"moduleName": "./src/index.js"}]
    },
    {
      "name": "./node_modules/react-dom/cjs/react-dom.production.min.js",
      "size": 123456,
      "reasons": [{"moduleName": "./src/index.js"}]
    },
    {
      "name": "./node_modules/axios/dist/axios.js",
      "size": 45678,
      "reasons": [{"moduleName": "./src/index.js"}]
    },
    {
      "name": "./src/index.js",
      "size": 1234,
      "reasons": []
    }
  ]
}
EOF

# Create a mock bundle.js file
cat > "$WORKSPACE_DIR/dist/bundle.js" << 'EOF'
// Mock production bundle - 867KB worth of minified code
// This file represents the compiled output with all dependencies
(function(){var lodash={};var moment={};var chart={};var axios={};})();
EOF

# Create README with context
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# React App - Bundle Size Investigation

## Current Issue
Production bundle has grown to 850KB, impacting load times.

## Task
Analyze bundle composition and identify optimization opportunities.

## Dependencies
- lodash (full build)
- moment (date library)
- chart.js (charting library)
- axios (HTTP client)
- react, react-dom

## Build Output
See `dist/stats.json` for webpack bundle statistics.
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the project
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Bundle Size Analysis Task Setup Complete ==="
echo "📝 Task Context:"
echo "  - React app at: $WORKSPACE_DIR"
echo "  - Production build exists in dist/"
echo "  - Current bundle size: ~867KB"
echo ""
echo "📋 Instructions:"
echo "  1. Open integrated terminal (Ctrl+\`)"
echo "  2. Install bundle analyzer: npm install --save-dev webpack-bundle-analyzer"
echo "  3. Run analysis: npx webpack-bundle-analyzer dist/stats.json"
echo "  4. Create BUNDLE_ANALYSIS.md with findings"
echo "  5. Include: top dependencies, sizes, recommendations"