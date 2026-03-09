#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up VSCode Crash Recovery Task ==="

WORKSPACE_DIR="/home/ga/workspace/crash_recovery_test"

# Clean up any existing workspace
sudo -u ga rm -rf "$WORKSPACE_DIR" 2>/dev/null || true
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create initial Python files
cat > "$WORKSPACE_DIR/routes.py" << 'INITEOF'
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/health')
def health_check():
    return jsonify({"status": "healthy"})
INITEOF

cat > "$WORKSPACE_DIR/validation.py" << 'INITEOF'
import re

def validate_username(username):
    if len(username) < 3:
        return False
    return username.isalnum()
INITEOF

cat > "$WORKSPACE_DIR/test_validation.py" << 'INITEOF'
import unittest
from validation import validate_username

class TestValidation(unittest.TestCase):
    def test_valid_username(self):
        self.assertTrue(validate_username("user123"))
    
    def test_short_username(self):
        self.assertFalse(validate_username("ab"))
INITEOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

echo "Initial files created"

# Save expected final content for verification
mkdir -p /tmp/expected_crash_recovery
chmod 777 /tmp/expected_crash_recovery

cat > "/tmp/expected_crash_recovery/routes_expected.py" << 'EXPECTEDEOF'
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/health')
def health_check():
    return jsonify({"status": "healthy"})

@app.route('/api/data')
def get_data():
    return jsonify({"data": [1, 2, 3]})
EXPECTEDEOF

cat > "/tmp/expected_crash_recovery/validation_expected.py" << 'EXPECTEDEOF'
import re

def validate_username(username):
    if len(username) < 3:
        return False
    return username.isalnum()

def validate_email(email):
    pattern = r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    return re.match(pattern, email) is not None
EXPECTEDEOF

cat > "/tmp/expected_crash_recovery/test_expected.py" << 'EXPECTEDEOF'
import unittest
from validation import validate_username

class TestValidation(unittest.TestCase):
    def test_valid_username(self):
        self.assertTrue(validate_username("user123"))
    
    def test_short_username(self):
        self.assertFalse(validate_username("ab"))
    
    def test_email_validation(self):
        from validation import validate_email
        self.assertTrue(validate_email("test@example.com"))
EXPECTEDEOF

echo "Expected content saved for verification"

# Create Python script to simulate VSCode crash with unsaved changes
cat > "/tmp/create_vscode_backup.py" << 'PYEOF'
#!/usr/bin/env python3
import os
import json
import time
import hashlib
from pathlib import Path

def get_workspace_hash(workspace_path):
    """Generate workspace hash similar to VSCode"""
    # VSCode uses the workspace folder path to generate a hash
    return hashlib.sha1(workspace_path.encode()).hexdigest()

def create_backup_structure():
    """Create VSCode Hot Exit backup structure"""
    workspace = "/home/ga/workspace/crash_recovery_test"
    backup_base = Path("/home/ga/.config/Code/Backups")
    
    # Create backup directory with workspace hash
    workspace_hash = get_workspace_hash(workspace)
    backup_dir = backup_base / workspace_hash
    backup_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"Creating backup in: {backup_dir}")
    
    # Create backup files for each modified file
    files_to_backup = {
        "routes.py": open("/tmp/expected_crash_recovery/routes_expected.py").read(),
        "validation.py": open("/tmp/expected_crash_recovery/validation_expected.py").read(),
        "test_validation.py": open("/tmp/expected_crash_recovery/test_expected.py").read()
    }
    
    backup_metadata = {}
    
    for filename, content in files_to_backup.items():
        filepath = os.path.join(workspace, filename)
        
        # Create unique backup file name using file path hash
        file_hash = hashlib.md5(filepath.encode()).hexdigest()
        backup_file = backup_dir / file_hash
        
        # Write backup content (VSCode stores as plain text with metadata)
        with open(backup_file, 'w') as f:
            f.write(content)
        
        backup_metadata[filepath] = file_hash
        print(f"Created backup for {filename}")
    
    # Create workspace metadata file
    workspace_json = {
        "folder": f"file://{workspace}",
        "backups": backup_metadata
    }
    
    with open(backup_dir / "workspace.json", 'w') as f:
        json.dump(workspace_json, f, indent=2)
    
    print(f"Backup structure created successfully")
    print(f"Workspace: {workspace}")
    print(f"Backup dir: {backup_dir}")

if __name__ == "__main__":
    create_backup_structure()
PYEOF

chmod +x /tmp/create_vscode_backup.py

# Open VSCode briefly to initialize workspace
echo "Opening VSCode to initialize workspace..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' --new-window" &
wait_for_vscode 15
wait_for_window "Visual Studio Code" 25
sleep 3

# Open the files in VSCode
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/routes.py'" &
sleep 1
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/validation.py'" &
sleep 1
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/test_validation.py'" &
sleep 2

echo "Files opened in VSCode"

# Close VSCode gracefully first (to ensure workspace is registered)
pkill -15 code 2>/dev/null || true
sleep 3

# Ensure VSCode is fully closed
pkill -9 code 2>/dev/null || true
pkill -9 code-server 2>/dev/null || true
sleep 2

echo "VSCode closed"

# Now create the backup files (simulating unsaved changes at crash)
echo "Creating Hot Exit backup files..."
sudo -u ga python3 /tmp/create_vscode_backup.py

# Verify backup was created
BACKUP_BASE="/home/ga/.config/Code/Backups"
if [ -d "$BACKUP_BASE" ] && [ "$(ls -A $BACKUP_BASE 2>/dev/null)" ]; then
    echo "✅ Backup directory created successfully"
    ls -la "$BACKUP_BASE"
else
    echo "⚠️ Warning: Backup directory may not be created properly"
fi

echo "=== Crash Recovery Task Setup Complete ==="
echo ""
echo "📝 Scenario:"
echo "   You were editing three Python files when your laptop battery died."
echo "   VSCode crashed with unsaved changes to:"
echo "   - routes.py (new get_data function)"
echo "   - validation.py (new validate_email function)"  
echo "   - test_validation.py (new test_email_validation method)"
echo ""
echo "🎯 Your task:"
echo "   1. Reopen VSCode - it should automatically restore the workspace"
echo "   2. VSCode's Hot Exit feature should have preserved your unsaved changes"
echo "   3. Verify the three files show as modified/dirty (unsaved)"
echo "   4. Check the content matches what you expect"
echo "   5. Save all files (Ctrl+K S) to confirm recovery was successful"
echo ""
echo "💡 Tip: VSCode should reopen the workspace automatically with unsaved changes"