#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Modernize Callback Pattern Task ==="

WORKSPACE_DIR="/home/ga/workspace/callback_migration"
ASSETS_DIR="/workspace/tasks/modernize_callback_pattern/assets"

# Create workspace structure
sudo -u ga mkdir -p "$WORKSPACE_DIR/test"

# Copy legacy callback-based code from assets
if [ -f "$ASSETS_DIR/file_processor_callbacks.js" ]; then
    sudo -u ga cp "$ASSETS_DIR/file_processor_callbacks.js" "$WORKSPACE_DIR/file_processor.js"
    echo "✓ Copied callback-based file_processor.js"
else
    echo "⚠️  Asset file not found, creating inline..."
    cat > "$WORKSPACE_DIR/file_processor.js" << 'EOF'
// Legacy callback-based file processor
const fs = require('fs');
const path = require('path');

function readAndParse(filename, callback) {
    fs.readFile(filename, 'utf8', function(err, data) {
        if (err) {
            return callback(err);
        }
        
        try {
            const parsed = JSON.parse(data);
            callback(null, parsed);
        } catch (parseErr) {
            callback(parseErr);
        }
    });
}

function processFiles(filenames, callback) {
    const results = [];
    let pending = filenames.length;
    
    if (pending === 0) {
        return callback(null, results);
    }
    
    filenames.forEach(function(filename, index) {
        readAndParse(filename, function(err, data) {
            if (err) {
                return callback(err);
            }
            
            results[index] = data;
            pending--;
            
            if (pending === 0) {
                callback(null, results);
            }
        });
    });
}

function writeResult(filename, data, callback) {
    const content = JSON.stringify(data, null, 2);
    fs.writeFile(filename, content, 'utf8', function(err) {
        if (err) {
            return callback(err);
        }
        callback(null, { success: true, file: filename });
    });
}

module.exports = {
    readAndParse,
    processFiles,
    writeResult
};
EOF
    sudo chown ga:ga "$WORKSPACE_DIR/file_processor.js"
fi

# Copy test file
if [ -f "$ASSETS_DIR/file_processor.test.js" ]; then
    sudo -u ga cp "$ASSETS_DIR/file_processor.test.js" "$WORKSPACE_DIR/test/"
    echo "✓ Copied test file"
else
    echo "⚠️  Test asset not found, creating inline..."
    cat > "$WORKSPACE_DIR/test/file_processor.test.js" << 'EOF'
const { readAndParse, processFiles, writeResult } = require('../file_processor');
const fs = require('fs');
const path = require('path');

describe('File Processor', function() {
    test('readAndParse should read and parse JSON', function(done) {
        const testFile = path.join(__dirname, 'test-data.json');
        fs.writeFileSync(testFile, '{"test": true}');
        
        readAndParse(testFile, function(err, result) {
            expect(err).toBeNull();
            expect(result).toEqual({ test: true });
            fs.unlinkSync(testFile);
            done();
        });
    });
    
    test('writeResult should write JSON file', function(done) {
        const testFile = path.join(__dirname, 'output.json');
        const testData = { message: 'Hello World' };
        
        writeResult(testFile, testData, function(err, result) {
            expect(err).toBeNull();
            expect(result.success).toBe(true);
            const content = fs.readFileSync(testFile, 'utf8');
            expect(JSON.parse(content)).toEqual(testData);
            fs.unlinkSync(testFile);
            done();
        });
    });
});
EOF
    sudo chown ga:ga "$WORKSPACE_DIR/test/file_processor.test.js"
fi

# Create package.json
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "callback-migration",
  "version": "1.0.0",
  "description": "Callback to Promise migration exercise",
  "main": "file_processor.js",
  "scripts": {
    "test": "jest"
  },
  "devDependencies": {
    "jest": "^29.0.0"
  }
}
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Install dependencies (suppress output for cleaner logs)
echo "Installing npm dependencies..."
cd "$WORKSPACE_DIR"
sudo -u ga npm install --silent 2>/dev/null || echo "⚠️  npm install had warnings (non-fatal)"

# Open VSCode with the files
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/file_processor.js' '$WORKSPACE_DIR/test/file_processor.test.js'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Modernize Callback Pattern Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Review file_processor.js - notice the callback-based patterns"
echo "  2. Convert all functions to async/await:"
echo "     - Remove callback parameters"
echo "     - Add 'async' keyword to function definitions"
echo "     - Use 'await' for async operations"
echo "     - Replace callback(err) with throw or reject"
echo "     - Replace callback(null, result) with return"
echo "  3. Add try/catch blocks for error handling"
echo "  4. Update test file to use async/await syntax"
echo "  5. Save all files (Ctrl+S)"
echo ""
echo "Files:"
echo "  - Main: $WORKSPACE_DIR/file_processor.js"
echo "  - Tests: $WORKSPACE_DIR/test/file_processor.test.js"