#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Debug Timezone Conversion Task ==="

WORKSPACE_DIR="/home/ga/workspace/meeting-scheduler"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Create directory structure
sudo -u ga mkdir -p utils test .vscode

# Create package.json
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "meeting-scheduler",
  "version": "1.0.0",
  "description": "Meeting scheduling app with timezone bug",
  "main": "app.js",
  "dependencies": {
    "moment-timezone": "^0.5.43"
  },
  "scripts": {
    "test": "node test/timezone-bug.js"
  }
}
EOF

# Create the buggy date converter utility
cat > "$WORKSPACE_DIR/utils/dateConverter.js" << 'EOF'
const moment = require('moment-timezone');

/**
 * Convert a local time string to UTC timestamp
 * @param {string} localTimeStr - Time in format "2024-01-15 14:00"
 * @param {string} timezone - IANA timezone (e.g., "America/Los_Angeles")
 * @returns {number} UTC timestamp
 */
function localToUTC(localTimeStr, timezone) {
    // Parse the local time string (this already interprets it as local time)
    const localMoment = moment.tz(localTimeStr, timezone);
    
    // BUG: We're converting to UTC, but moment.tz() already handled the timezone
    // This double-applies the offset
    const utcOffset = localMoment.utcOffset();
    const utcTimestamp = localMoment.valueOf() - (utcOffset * 60 * 1000);
    
    return utcTimestamp;
}

/**
 * Convert UTC timestamp to local time string
 * @param {number} utcTimestamp - UTC timestamp
 * @param {string} timezone - IANA timezone
 * @returns {string} Local time string
 */
function utcToLocal(utcTimestamp, timezone) {
    return moment.utc(utcTimestamp).tz(timezone).format('YYYY-MM-DD HH:mm');
}

module.exports = { localToUTC, utcToLocal };
EOF

# Create test script that demonstrates the bug
cat > "$WORKSPACE_DIR/test/timezone-bug.js" << 'EOF'
const { localToUTC, utcToLocal } = require('../utils/dateConverter');

console.log('=== Timezone Bug Reproduction ===\n');

// User on East Coast schedules meeting for 2:00 PM EST
const estTime = '2024-01-15 14:00';
const estTimezone = 'America/New_York';

console.log('1. East Coast user schedules meeting:');
console.log('   Local time: ' + estTime + ' ' + estTimezone);

// Convert to UTC for storage (BUG: this will double-convert)
const utcTimestamp = localToUTC(estTime, estTimezone);
console.log('   Stored as UTC timestamp: ' + utcTimestamp);
console.log('   Should be: ' + new Date('2024-01-15T19:00:00Z').getTime() + ' (7 PM UTC)');

// West Coast user views the meeting
const pstTimezone = 'America/Los_Angeles';
const pstTime = utcToLocal(utcTimestamp, pstTimezone);

console.log('\n2. West Coast user views meeting:');
console.log('   Displayed time: ' + pstTime + ' ' + pstTimezone);
console.log('   Expected time: 2024-01-15 11:00 ' + pstTimezone + ' (11 AM PST)');
console.log('   ' + (pstTime === '2024-01-15 11:00' ? '✓ CORRECT' : '✗ INCORRECT'));

// Calculate the error
const expectedUTC = new Date('2024-01-15T19:00:00Z').getTime();
const hoursDiff = Math.round((utcTimestamp - expectedUTC) / (1000 * 60 * 60));

console.log('\n3. Analysis:');
console.log('   Time difference: ' + Math.abs(hoursDiff) + ' hours off');
console.log('   This indicates a double timezone conversion bug.');
EOF

# Create launch.json for debugging
cat > "$WORKSPACE_DIR/.vscode/launch.json" << 'EOF'
{
    "version": "0.2.0",
    "configurations": [
        {
            "type": "node",
            "request": "launch",
            "name": "Debug Timezone Bug",
            "program": "${workspaceFolder}/test/timezone-bug.js",
            "console": "integratedTerminal",
            "skipFiles": ["<node_internals>/**"]
        }
    ]
}
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Install npm dependencies
echo "Installing Node.js dependencies..."
cd "$WORKSPACE_DIR"
sudo -u ga npm install --silent 2>&1 | grep -v "npm WARN" || true

# Initialize git repository for better workflow
cd "$WORKSPACE_DIR"
sudo -u ga git init > /dev/null 2>&1 || true
sudo -u ga git config user.name "GA User" > /dev/null 2>&1 || true
sudo -u ga git config user.email "ga@localhost" > /dev/null 2>&1 || true
sudo -u ga git add . > /dev/null 2>&1 || true
sudo -u ga git commit -m "Initial commit" > /dev/null 2>&1 || true

# Open VSCode with the workspace and key file
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/utils/dateConverter.js'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Debug Timezone Conversion Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Review the code in utils/dateConverter.js (already open)"
echo "  2. Run 'npm test' in terminal to see the bug"
echo "  3. Use debugger (F5) to step through localToUTC function"
echo "  4. Identify where double timezone conversion happens"
echo "  5. Add a comment marking the bug line (e.g., // BUG: ...)"
echo "  6. Save the file (Ctrl+S)"
echo ""
echo "Workspace: $WORKSPACE_DIR"