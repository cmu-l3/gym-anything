#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Remove Debug Logging Task ==="

WORKSPACE_DIR="/home/ga/workspace/data_processor"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src" "$WORKSPACE_DIR/tests"

# Create main application file with debug prints scattered
cat > "$WORKSPACE_DIR/src/processor.py" << 'EOF'
import time
from typing import List

def process_batch(items: List[str]) -> List[str]:
    """Process a batch of items"""
    print(f"DEBUG: Starting batch processing with {len(items)} items")
    results = []
    for item in items:
        print(f"DEBUG: Processing item: {item}")
        processed = item.upper()
        results.append(processed)
    print(f"DEBUG: Batch processing complete, got {len(results)} results")
    return results

def validate_input(data: str) -> bool:
    """Validate input data"""
    print(f"DEBUG: Validating input: {data}")
    if not data or len(data) == 0:
        print("DEBUG: Validation failed - empty input")
        return False
    print("DEBUG: Validation passed")
    return True
EOF

# Create worker file with more debug prints
cat > "$WORKSPACE_DIR/src/worker.py" << 'EOF'
import threading
from queue import Queue

class Worker:
    def __init__(self, worker_id: int):
        self.worker_id = worker_id
        self.queue = Queue()
        print(f"DEBUG: Worker {worker_id} initialized")
    
    def start(self):
        print(f"DEBUG: Worker {self.worker_id} starting")
        thread = threading.Thread(target=self._run)
        thread.start()
        print(f"DEBUG: Worker {self.worker_id} thread started")
    
    def _run(self):
        while True:
            item = self.queue.get()
            print(f"DEBUG: Worker {self.worker_id} processing {item}")
            if item is None:
                break
            self._process(item)
    
    def _process(self, item):
        print(f"DEBUG: Processing {item} in worker {self.worker_id}")
        # Actual processing logic
        result = item * 2
        print(f"DEBUG: Result: {result}")
        return result
EOF

# Create logger file with LEGITIMATE prints that should be PRESERVED
cat > "$WORKSPACE_DIR/src/logger.py" << 'EOF'
import sys
from datetime import datetime

def log_info(message: str):
    """Legitimate logging function - DO NOT REMOVE"""
    timestamp = datetime.now().isoformat()
    print(f"[INFO] {timestamp}: {message}")

def log_error(message: str):
    """Legitimate error logging - DO NOT REMOVE"""
    timestamp = datetime.now().isoformat()
    print(f"[ERROR] {timestamp}: {message}", file=sys.stderr)

def print_banner():
    """Print application banner"""
    print("=" * 50)
    print("Data Processor v1.0")
    print("=" * 50)
EOF

# Create config file with debug print
cat > "$WORKSPACE_DIR/src/config.py" << 'EOF'
import os

class Config:
    def __init__(self):
        self.db_host = os.getenv("DB_HOST", "localhost")
        print(f"DEBUG: Config initialized with db_host={self.db_host}")
        self.max_workers = 4
        print(f"DEBUG: max_workers set to {self.max_workers}")
    
    def validate(self):
        print("DEBUG: Validating configuration")
        if not self.db_host:
            print("DEBUG: Invalid config - no db_host")
            return False
        return True
EOF

# Create test file with prints that should be PRESERVED
cat > "$WORKSPACE_DIR/tests/test_processor.py" << 'EOF'
import unittest
from src.processor import process_batch

class TestProcessor(unittest.TestCase):
    def test_process_batch(self):
        print("Running test_process_batch")
        items = ["a", "b", "c"]
        results = process_batch(items)
        print(f"Test results: {results}")
        self.assertEqual(len(results), 3)
EOF

# Create utils file with debug print
cat > "$WORKSPACE_DIR/src/utils.py" << 'EOF'
def retry_operation(func, max_attempts=3):
    """Retry an operation with exponential backoff"""
    print(f"DEBUG: retry_operation called with max_attempts={max_attempts}")
    for attempt in range(max_attempts):
        print(f"DEBUG: Attempt {attempt + 1}")
        try:
            return func()
        except Exception as e:
            print(f"DEBUG: Attempt failed with error: {e}")
            if attempt == max_attempts - 1:
                raise
    print("DEBUG: All retry attempts exhausted")
EOF

# Create __init__.py files
touch "$WORKSPACE_DIR/src/__init__.py"
touch "$WORKSPACE_DIR/tests/__init__.py"

# Create README with instructions
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Data Processor

## Cleanup Task

Remove all DEBUG print statements from the src/ directory EXCEPT:
- src/logger.py (contains legitimate logging functions)
- tests/ directory (contains test output)

Debug prints to remove are marked with "DEBUG:" prefix and are scattered across:
- src/processor.py (6 debug prints)
- src/worker.py (6 debug prints)
- src/config.py (4 debug prints)
- src/utils.py (4 debug prints)

Total: 20 debug prints to remove, 5 legitimate prints to preserve in logger.py.

Use Find in Files (Ctrl+Shift+F) to search for: print.*DEBUG
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/README.md'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Remove Debug Logging Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open Find in Files (Ctrl+Shift+F)"
echo "  2. Search for: print.*DEBUG"
echo "  3. Review results (~20 debug prints in src/)"
echo "  4. Remove debug prints from processor.py, worker.py, config.py, utils.py"
echo "  5. PRESERVE prints in logger.py and tests/"
echo "  6. Save all files (Ctrl+K S)"
echo ""
echo "Workspace: $WORKSPACE_DIR"