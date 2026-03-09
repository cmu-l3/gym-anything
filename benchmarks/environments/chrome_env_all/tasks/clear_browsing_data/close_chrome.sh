#!/bin/bash
set -e

echo "[Post-task] Closing Chrome to flush data to disk..."

# Send SIGTERM to Chrome processes
pkill -TERM -u ga chrome 2>/dev/null || true

# Wait for graceful shutdown
sleep 3

# Force kill if still running
if pgrep -u ga chrome > /dev/null; then
    echo "[Post-task] Chrome still running, force killing..."
    pkill -9 -u ga chrome 2>/dev/null || true
    sleep 2
fi

# Verify Chrome is stopped
if pgrep -u ga chrome > /dev/null; then
    echo "[Post-task] Warning: Chrome processes may still be running"
else
    echo "[Post-task] Chrome closed successfully"
fi

# Ensure data is synced to disk
sync

echo "[Post-task] Data flushed to disk, ready for verification"