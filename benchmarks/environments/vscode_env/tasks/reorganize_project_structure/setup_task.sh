#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Reorganize Project Structure Task ==="

WORKSPACE_DIR="/home/ga/workspace/messy_project"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create initial messy structure with files in root
echo "Creating messy project structure..."

# Create app.py (main application)
cat > "$WORKSPACE_DIR/app.py" << 'EOF'
from helpers import format_data

def process_request(data):
    """Process incoming request data"""
    return format_data(data)

def main():
    sample_data = {"key": "value", "number": 42}
    result = process_request(sample_data)
    print(f"Result: {result}")

if __name__ == "__main__":
    main()
EOF

# Create helpers.py (utility functions)
cat > "$WORKSPACE_DIR/helpers.py" << 'EOF'
def format_data(data):
    """Format data for output"""
    if isinstance(data, dict):
        items = [f"{k}={v}" for k, v in data.items()]
        return f"Formatted: {{{', '.join(items)}}}"
    return f"Formatted: {data}"

def helper_function():
    """Additional helper function"""
    return "Helper utility"
EOF

# Create test_app.py (tests)
cat > "$WORKSPACE_DIR/test_app.py" << 'EOF'
from app import process_request

def test_process_request():
    """Test the process_request function"""
    test_data = {"test": "data", "value": 123}
    result = process_request(test_data)
    assert "Formatted" in result
    assert "test=data" in result
    print("✅ Test passed!")
    return True

def test_empty_data():
    """Test with empty data"""
    result = process_request({})
    assert "Formatted" in result
    print("✅ Empty data test passed!")
    return True

if __name__ == "__main__":
    test_process_request()
    test_empty_data()
    print("All tests passed!")
EOF

# Create settings.ini (configuration)
cat > "$WORKSPACE_DIR/settings.ini" << 'EOF'
[DEFAULT]
debug = true
log_level = INFO
max_connections = 100

[database]
host = localhost
port = 5432
name = myapp

[api]
timeout = 30
retries = 3
EOF

# Create README.md (documentation - stays in root)
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Messy Project

This project needs to be reorganized into proper directory structure.

## Current Issues
- All files are in root directory
- No proper package structure
- Imports will break when reorganized

## Required Structure
- src/ - for main application code
- utils/ - for utility functions
- tests/ - for test files
- config/ - for configuration files
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

echo "✅ Messy project structure created"
echo "Files in workspace:"
ls -la "$WORKSPACE_DIR"

# Open VSCode with workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Reorganize Project Structure Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "  1. Create directories: src/, utils/, tests/, config/"
echo "  2. Move app.py → src/app.py"
echo "  3. Move helpers.py → utils/helpers.py"
echo "  4. Move test_app.py → tests/test_app.py"
echo "  5. Move settings.ini → config/settings.ini"
echo "  6. Create __init__.py files in src/, utils/, tests/"
echo "  7. Update imports in src/app.py (from helpers → from utils.helpers)"
echo "  8. Update imports in tests/test_app.py (from app → from src.app)"
echo "  9. Save all files"
echo ""
echo "⚠️  Important: Remove old files from root after moving!"