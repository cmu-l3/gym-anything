#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up React Webpack Optimization Task ==="

WORKSPACE_DIR="/home/ga/workspace/news_portal"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/components"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/utils"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

cd "$WORKSPACE_DIR"

# 1. package.json
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "news-portal",
  "version": "1.0.0",
  "scripts": {
    "build": "webpack --mode production",
    "test": "jest"
  },
  "dependencies": {
    "bootstrap": "^5.2.3",
    "lodash": "^4.17.21",
    "moment": "^2.29.4",
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  },
  "devDependencies": {
    "@babel/core": "^7.20.0",
    "@babel/preset-env": "^7.20.0",
    "@babel/preset-react": "^7.20.0",
    "@testing-library/react": "^13.4.0",
    "babel-jest": "^29.3.1",
    "babel-loader": "^9.1.0",
    "css-loader": "^6.7.0",
    "jest": "^29.3.1",
    "jest-environment-jsdom": "^29.3.1",
    "mini-css-extract-plugin": "^2.7.0",
    "style-loader": "^3.3.1",
    "webpack": "^5.75.0",
    "webpack-cli": "^5.0.0"
  },
  "jest": {
    "testEnvironment": "jsdom",
    "moduleNameMapper": {
      "\\.css$": "<rootDir>/tests/styleMock.js"
    }
  }
}
EOF

# 2. .babelrc
cat > "$WORKSPACE_DIR/.babelrc" << 'EOF'
{
  "presets": ["@babel/preset-env", ["@babel/preset-react", {"runtime": "automatic"}]]
}
EOF

# 3. webpack.config.js (BUGGY)
cat > "$WORKSPACE_DIR/webpack.config.js" << 'EOF'
const path = require('path');
const MiniCssExtractPlugin = require('mini-css-extract-plugin');
const webpack = require('webpack');

module.exports = {
  entry: './src/index.js',
  output: {
    path: path.resolve(__dirname, 'dist'),
    filename: 'main.js',
    clean: true,
  },
  module: {
    rules: [
      {
        test: /\.(js|jsx)$/,
        exclude: /node_modules/,
        use: ['babel-loader'],
      },
      {
        test: /\.css$/,
        // BUG: Using style-loader instead of extracting CSS
        use: ['style-loader', 'css-loader'],
      },
    ],
  },
  plugins: [
    // BUG: Missing MiniCssExtractPlugin instantiation
    // BUG: Missing webpack.IgnorePlugin for moment locales
  ],
  // BUG: Missing optimization.splitChunks for vendor extraction
};
EOF

# 4. src/index.js
cat > "$WORKSPACE_DIR/src/index.js" << 'EOF'
import React from 'react';
import { createRoot } from 'react-dom/client';
import 'bootstrap/dist/css/bootstrap.min.css';
import App from './App';

const container = document.getElementById('root');
if (container) {
  const root = createRoot(container);
  root.render(<App />);
}
EOF

# 5. src/App.js (BUGGY: Static Import)
cat > "$WORKSPACE_DIR/src/App.js" << 'EOF'
import React from 'react';
import InteractiveMap from './components/InteractiveMap';
import { debouncedLog } from './utils/formatters';

const App = () => {
  const handleClick = () => {
    debouncedLog('User interacted with the main application.');
  };

  return (
    <div className="container mt-4">
      <h1>Global News Portal</h1>
      <button className="btn btn-primary mb-3" onClick={handleClick}>
        Refresh News
      </button>
      <div className="map-container border p-2">
        {/* BUG: InteractiveMap is statically imported and not lazy loaded */}
        <InteractiveMap />
      </div>
    </div>
  );
};

export default App;
EOF

# 6. src/components/InteractiveMap.js
cat > "$WORKSPACE_DIR/src/components/InteractiveMap.js" << 'EOF'
import React from 'react';

// Simulating a heavy component with large embedded data
const geoJsonMock = {
  type: "FeatureCollection",
  features: Array.from({ length: 5000 }).map((_, i) => ({
    type: "Feature",
    properties: { id: i, name: `Region ${i}` },
    geometry: { type: "Point", coordinates: [ (Math.random() * 360) - 180, (Math.random() * 180) - 90 ] }
  }))
};

const InteractiveMap = () => {
  return (
    <div>
      <h3>Interactive Election Map</h3>
      <p>Loaded {geoJsonMock.features.length} regions.</p>
    </div>
  );
};

export default InteractiveMap;
EOF

# 7. src/utils/formatters.js (BUGGY: Full lodash import)
cat > "$WORKSPACE_DIR/src/utils/formatters.js" << 'EOF'
import _ from 'lodash';
import moment from 'moment';

export const debouncedLog = _.debounce((msg) => {
  console.log(`[${moment().format('YYYY-MM-DD HH:mm:ss')}] ${msg}`);
}, 300);
EOF

# 8. tests/App.test.js
cat > "$WORKSPACE_DIR/tests/App.test.js" << 'EOF'
import React from 'react';
import { render } from '@testing-library/react';
import App from '../src/App';

test('renders App without crashing', () => {
  const { container } = render(<App />);
  expect(container.querySelector('h1').textContent).toBe('Global News Portal');
});
EOF

# 9. tests/styleMock.js
cat > "$WORKSPACE_DIR/tests/styleMock.js" << 'EOF'
module.exports = {};
EOF

# Install dependencies
echo "Installing npm dependencies (this may take a minute)..."
sudo -u ga npm install --no-audit --no-fund

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Initial build to populate dist (so it exists)
sudo -u ga npm run build > /dev/null 2>&1 || true

# Start VSCode
if ! pgrep -f "code.*--ms-enable-electron-run-as-node" > /dev/null; then
    su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR/webpack.config.js $WORKSPACE_DIR/src/App.js $WORKSPACE_DIR/src/utils/formatters.js &"
    sleep 5
fi

# Wait and maximize
wait_for_vscode 30
WID=$(get_vscode_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_vscode_window
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="