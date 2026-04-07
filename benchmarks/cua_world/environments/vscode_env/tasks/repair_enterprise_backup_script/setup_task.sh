#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Repair Enterprise Backup Script Task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

WORKSPACE_DIR="/home/ga/workspace/backup_system"
sudo -u ga mkdir -p "$WORKSPACE_DIR/lib"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"
sudo -u ga mkdir -p "$WORKSPACE_DIR/mocks"

# ─────────────────────────────────────────────────────────────
# 1. Create the buggy Bash scripts
# ─────────────────────────────────────────────────────────────

cat > "$WORKSPACE_DIR/backup_manager.sh" << 'EOF'
#!/bin/bash
# Main Enterprise Backup Script

source lib/common.sh
source lib/db_backup.sh
source lib/fs_backup.sh

# Staging area for unencrypted files
STAGING_DIR="/tmp/backup_unencrypted"
mkdir -p "$STAGING_DIR"

echo "Starting backup process..."

acquire_lock

backup_db
backup_fs

# Finalize
echo "Encrypting and packaging..."
tar -czf /tmp/final_backup.tar.gz -C "$STAGING_DIR" .

# Cleanup staging
rm -rf "$STAGING_DIR"

release_lock

echo "SUCCESS: Backup completed."
EOF

cat > "$WORKSPACE_DIR/lib/common.sh" << 'EOF'
# Common utility functions

PID_FILE="/tmp/backup_manager.pid"

acquire_lock() {
    # BUG 4: Stale lockfile issue. If script is killed, PID file remains and blocks future runs.
    if [ -f "$PID_FILE" ]; then
        echo "ERROR: Backup already running. PID file exists."
        exit 1
    fi
    echo $$ > "$PID_FILE"
}

release_lock() {
    rm -f "$PID_FILE"
}
EOF

cat > "$WORKSPACE_DIR/lib/db_backup.sh" << 'EOF'
# Database backup module

backup_db() {
    echo "Backing up database..."
    
    # BUG 1: Silent pipeline failure. If pg_dump fails, gzip still succeeds and exits with 0.
    pg_dump mydatabase | gzip > "$STAGING_DIR/db_dump.sql.gz"
    
    if [ $? -ne 0 ]; then
        echo "Database backup failed!"
        exit 1
    fi
}
EOF

cat > "$WORKSPACE_DIR/lib/fs_backup.sh" << 'EOF'
# Filesystem backup module

UPLOAD_DIR="/tmp/mock_uploads"

backup_fs() {
    echo "Backing up filesystem..."
    mkdir -p "$STAGING_DIR/uploads"
    
    # BUG 2: Unsafe filename iteration. Fails on files with spaces/newlines.
    for file in $(ls "$UPLOAD_DIR"); do
        cp "$UPLOAD_DIR/$file" "$STAGING_DIR/uploads/" 2>/dev/null || echo "Failed to copy $file"
    done

    # BUG 3: Subshell variable loss. Variable modified in piped while-loop is lost.
    TOTAL_SIZE=0
    find "$STAGING_DIR/uploads" -type f | while read -r f; do
        sz=$(stat -c%s "$f")
        TOTAL_SIZE=$((TOTAL_SIZE + sz))
    done
    
    echo "Total Backup Size: $TOTAL_SIZE bytes"
}
EOF

# Make scripts executable
chmod +x "$WORKSPACE_DIR/backup_manager.sh"

# ─────────────────────────────────────────────────────────────
# 2. Create Python Test Suite (pytest)
# ─────────────────────────────────────────────────────────────

cat > "$WORKSPACE_DIR/tests/test_backup.py" << 'EOF'
import subprocess
import os
import signal
import time
import shutil

WORKSPACE = "/home/ga/workspace/backup_system"

def setup_module(module):
    os.makedirs("/tmp/mock_uploads", exist_ok=True)
    # Create files, including one with a space to test Bug 2
    with open("/tmp/mock_uploads/normal.txt", "w") as f:
        f.write("Normal file")
    with open("/tmp/mock_uploads/file with space.txt", "w") as f:
        f.write("Space file")
    
    os.makedirs(f"{WORKSPACE}/mocks", exist_ok=True)
    with open(f"{WORKSPACE}/mocks/pg_dump", "w") as f:
        f.write("#!/bin/bash\nexit 1\n") # Always fail to test Bug 1
    os.chmod(f"{WORKSPACE}/mocks/pg_dump", 0o755)

def teardown_module(module):
    shutil.rmtree("/tmp/mock_uploads", ignore_errors=True)
    shutil.rmtree("/tmp/backup_unencrypted", ignore_errors=True)
    if os.path.exists("/tmp/backup_manager.pid"):
        os.remove("/tmp/backup_manager.pid")

def test_pipeline_failure_caught():
    """Bug 1: The script should fail if pg_dump fails, not silently create an empty zip."""
    env = os.environ.copy()
    env["PATH"] = f"{WORKSPACE}/mocks:" + env["PATH"]
    
    result = subprocess.run(
        ["bash", f"{WORKSPACE}/backup_manager.sh"],
        env=env,
        capture_output=True,
        text=True
    )
    assert result.returncode != 0, "Script should return non-zero exit code when pg_dump fails."

def test_space_in_filenames_handled():
    """Bug 2: Files with spaces should be successfully copied."""
    env = os.environ.copy()
    # Provide a passing pg_dump
    with open(f"{WORKSPACE}/mocks/pg_dump", "w") as f:
        f.write("#!/bin/bash\necho 'fake sql'\n")
    
    subprocess.run(["bash", f"{WORKSPACE}/backup_manager.sh"], env=env, capture_output=True)
    assert os.path.exists("/tmp/backup_unencrypted/uploads/file with space.txt") or os.path.exists("/tmp/final_backup.tar.gz")

def test_subshell_variable_scope():
    """Bug 3: Total Backup Size should be > 0 (not lost in subshell)."""
    env = os.environ.copy()
    result = subprocess.run(["bash", f"{WORKSPACE}/backup_manager.sh"], env=env, capture_output=True, text=True)
    
    # Parse the output for "Total Backup Size: X bytes"
    for line in result.stdout.split('\n'):
        if "Total Backup Size:" in line:
            size_str = line.split(':')[1].replace('bytes', '').strip()
            assert int(size_str) > 0, f"Total size was {size_str}, expected > 0 (Subshell variable loss)"
            return
    assert False, "Total Backup Size output not found."

def test_stale_lockfile_ignored():
    """Bug 4: A lockfile from a dead process should not block the script."""
    # Write a dead PID
    with open("/tmp/backup_manager.pid", "w") as f:
        f.write("9999999\n")
    
    result = subprocess.run(["bash", f"{WORKSPACE}/backup_manager.sh"], capture_output=True, text=True)
    assert "Backup already running" not in result.stdout, "Script blocked by stale lockfile!"

def test_trap_cleanup_on_interrupt():
    """Bug 5: The script should clean up /tmp/backup_unencrypted even if SIGINT received."""
    os.makedirs("/tmp/backup_unencrypted", exist_ok=True)
    
    process = subprocess.Popen(["bash", f"{WORKSPACE}/backup_manager.sh"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    time.sleep(0.5)
    process.send_signal(signal.SIGINT)
    process.wait()
    
    assert not os.path.exists("/tmp/backup_unencrypted"), "Staging directory was not cleaned up on SIGINT (Missing trap EXIT/SIGINT)"
EOF

# Ensure ownership
chown -R ga:ga "$WORKSPACE_DIR"

# ─────────────────────────────────────────────────────────────
# 3. GUI / VSCode Setup
# ─────────────────────────────────────────────────────────────

# Make sure VSCode runs
if ! pgrep -f "code.*--ms-enable-electron-run-as-node" > /dev/null; then
    echo "Starting VSCode..."
    sudo -u ga DISPLAY=:1 code "$WORKSPACE_DIR" &
    sleep 5
fi

# Wait for VSCode to initialize
for i in {1..30}; do
    if wmctrl -l | grep -qi "Visual Studio Code"; then
        break
    fi
    sleep 1
done

# Focus & Maximize
WID=$(wmctrl -l | grep -i 'Visual Studio Code' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    wmctrl -ia "$WID" 2>/dev/null || true
    wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
if [ -f /tmp/task_initial.png ]; then
    echo "Initial screenshot captured."
fi

echo "=== Task Setup Complete ==="