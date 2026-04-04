#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Custom File Viewer Task ==="

WORKSPACE="/home/ga/workspace/db_debug"
ASSETS="/workspace/tasks/configure_custom_file_viewer/assets"

# Create workspace
sudo -u ga mkdir -p "$WORKSPACE"
cd "$WORKSPACE"

# Create SQLite database with test data
echo "Creating test SQLite database..."
sudo -u ga sqlite3 "$WORKSPACE/test_data.sqlite" << 'EOF'
CREATE TABLE users (
    user_id INTEGER PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    name TEXT,
    created_at TEXT
);

INSERT INTO users VALUES 
    (1, 'alice@example.com', 'Alice Smith', '2024-01-15'),
    (2, 'bob@example.com', 'Bob Jones', '2024-01-16'),
    (3, 'charlie@example.com', 'Charlie Brown', '2024-01-17');

CREATE TABLE sessions (
    session_id TEXT PRIMARY KEY,
    user_id INTEGER,
    ip_address TEXT,
    FOREIGN KEY(user_id) REFERENCES users(user_id)
);

INSERT INTO sessions VALUES
    ('sess_001', 1, '192.168.1.10'),
    ('sess_002', 2, '192.168.1.11');
EOF

# Create README with context
cat > "$WORKSPACE/README.md" << 'EOF'
# Bug Investigation: User ID Mismatch

## Issue
Production bug report: User "alice@example.com" is seeing data from "bob@example.com"

## Files
- `test_data.sqlite`: Database snapshot from QA environment
  
## Task
The bug is likely in the `users` table. We need to check:
1. What is alice's user_id?
2. What is bob's user_id?
3. Are there any duplicate entries?

Open the database file in VSCode to investigate.

## Hint
You may need to install an SQLite viewer extension first.
Search the Extensions marketplace (Ctrl+Shift+X) for "SQLite".
EOF

# Create investigation notes template
cat > "$WORKSPACE/investigation_notes.txt" << 'EOF'
# Investigation Notes
# (Fill this out after viewing the database)

Alice's user_id: [FILL IN]
Bob's user_id: [FILL IN]
Number of users in table: [FILL IN]
EOF

sudo chown -R ga:ga "$WORKSPACE"

# Uninstall any existing SQLite extensions to ensure clean state
echo "Ensuring clean state (removing existing SQLite extensions if any)..."
su - ga -c "DISPLAY=:1 code --uninstall-extension alexcvzz.vscode-sqlite" 2>/dev/null || true
su - ga -c "DISPLAY=:1 code --uninstall-extension qwtel.sqlite-viewer" 2>/dev/null || true
su - ga -c "DISPLAY=:1 code --uninstall-extension mtxr.sqltools" 2>/dev/null || true
sleep 2

# Open VSCode with workspace
echo "Opening VSCode with workspace..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Configure Custom File Viewer Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Install an SQLite viewer extension (Ctrl+Shift+X, search 'SQLite')"
echo "  2. Open test_data.sqlite file"
echo "  3. View the users table"
echo "  4. Extract alice's user_id, bob's user_id, and total user count"
echo "  5. Fill in investigation_notes.txt with the findings"
echo "  6. Save the notes file"
echo ""
echo "Workspace: $WORKSPACE"
echo "Database: $WORKSPACE/test_data.sqlite"
echo "Notes: $WORKSPACE/investigation_notes.txt"