#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Cross-Platform Paths Task ==="

WORKSPACE_DIR="/home/ga/workspace/data-processor"
sudo -u ga mkdir -p "$WORKSPACE_DIR"/{config,logs,data,utils,output}

# Create main.py with hardcoded paths
cat > "$WORKSPACE_DIR/main.py" << 'EOF'
#!/usr/bin/env python3
"""
Main entry point for data processor
ISSUE: Hardcoded Unix-style paths fail on Windows
"""

config_file = "config/database.conf"
log_file = "logs/app.log"

def load_config():
    """Load configuration - BROKEN on Windows"""
    with open(config_file, 'r') as f:
        return f.read()

def setup_logging():
    """Setup logging - BROKEN on Windows"""
    log_path = "logs/app.log"
    print(f"Logging to: {log_path}")
    return log_path

if __name__ == "__main__":
    print("Starting data processor...")
    try:
        config = load_config()
        print("Config loaded successfully")
    except FileNotFoundError as e:
        print(f"ERROR: {e}")
        print("This fails on Windows due to path separator issues!")
EOF

# Create config_loader.py
cat > "$WORKSPACE_DIR/config_loader.py" << 'EOF'
"""Configuration loader module"""

def get_config_path(filename):
    """Get path to config file - BROKEN on Windows"""
    return "config/" + filename

def load_settings():
    """Load settings file"""
    settings_path = "config/settings.json"
    return settings_path
EOF

# Create data/processor.py
cat > "$WORKSPACE_DIR/data/processor.py" << 'EOF'
"""Data processing module"""

class DataProcessor:
    def __init__(self):
        """Initialize processor - BROKEN on Windows"""
        self.output_dir = "output/processed"
        self.input_dir = "data/input"
    
    def process(self):
        """Process data"""
        print(f"Processing data to: {self.output_dir}")
EOF

# Create utils/logger.py
cat > "$WORKSPACE_DIR/utils/logger.py" << 'EOF'
"""Logging utilities"""

LOG_DIR = "logs/application"
ERROR_LOG = "logs/errors.log"
DEBUG_LOG = "logs/debug.log"

def init_logger():
    """Initialize logger - BROKEN on Windows"""
    print(f"Logs directory: {LOG_DIR}")
    print(f"Error log: {ERROR_LOG}")
EOF

# Create test script
cat > "$WORKSPACE_DIR/test_paths.py" << 'EOF'
#!/usr/bin/env python3
"""
Test script to verify cross-platform path fixes
"""
import re
import sys
from pathlib import Path

def test_no_hardcoded_paths():
    """Verify no hardcoded Unix paths remain"""
    files = [
        "main.py", "config_loader.py", 
        "data/processor.py", "utils/logger.py"
    ]
    
    violations = []
    for file in files:
        if not Path(file).exists():
            continue
        content = Path(file).read_text()
        # Look for string literals with forward slashes
        matches = re.findall(r'["\'][\w]+/[\w/\.]+["\']', content)
        if matches:
            violations.extend([(file, m) for m in matches])
    
    if violations:
        print("❌ FAIL: Found hardcoded paths:")
        for file, match in violations[:5]:
            print(f"  {file}: {match}")
        return False
    
    print("✓ No hardcoded Unix-style paths found")
    return True

def test_platform_agnostic_code():
    """Verify platform-agnostic solutions used"""
    files = [
        "main.py", "config_loader.py",
        "data/processor.py", "utils/logger.py"
    ]
    
    total_uses = 0
    for file in files:
        if not Path(file).exists():
            continue
        content = Path(file).read_text()
        
        # Count pathlib or os.path usage
        pathlib_uses = content.count('Path(') + content.count(' / ')
        ospath_uses = content.count('os.path.join(')
        total_uses += pathlib_uses + ospath_uses
    
    if total_uses < 4:
        print(f"❌ FAIL: Only {total_uses} platform-agnostic path constructions found (need 4+)")
        return False
    
    print(f"✓ Found {total_uses} platform-agnostic path constructions")
    return True

def test_imports_present():
    """Verify necessary imports added"""
    files = ["main.py", "config_loader.py", "data/processor.py", "utils/logger.py"]
    
    has_pathlib = False
    has_os = False
    
    for file in files:
        if not Path(file).exists():
            continue
        content = Path(file).read_text()
        if 'from pathlib import' in content or 'import pathlib' in content:
            has_pathlib = True
        if 'import os' in content:
            has_os = True
    
    if not (has_pathlib or has_os):
        print("❌ FAIL: No pathlib or os imports found")
        return False
    
    print("✓ Proper imports present")
    return True

if __name__ == "__main__":
    print("Running cross-platform path verification tests...\n")
    
    tests = [
        test_no_hardcoded_paths,
        test_platform_agnostic_code,
        test_imports_present
    ]
    
    passed = sum(test() for test in tests)
    total = len(tests)
    
    print(f"\n{'='*50}")
    print(f"Results: {passed}/{total} tests passed")
    print('='*50)
    
    sys.exit(0 if passed == total else 1)
EOF

chmod +x "$WORKSPACE_DIR/test_paths.py"

# Create dummy config file so load_config doesn't fail immediately
cat > "$WORKSPACE_DIR/config/database.conf" << 'EOF'
[database]
host=localhost
port=5432
EOF

# Create README with instructions
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Data Processor - Cross-Platform Path Fix

## Problem
This application crashes on Windows with: