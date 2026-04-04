#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Prepare Presentation Mode Task ==="

WORKSPACE_DIR="/home/ga/workspace/demo_project"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Initialize git repository
cd "$WORKSPACE_DIR"
sudo -u ga git init
sudo -u ga git config user.name "Demo User"
sudo -u ga git config user.email "demo@example.com"

# Create demo Python project files
cat > "$WORKSPACE_DIR/main.py" << 'EOF'
def process_data(data):
    """Process data for presentation demo"""
    results = []
    for item in data:
        results.append(item * 2)
    return results

def main():
    data = [1, 2, 3, 4, 5]
    result = process_data(data)
    print(f"Processed data: {result}")

if __name__ == "__main__":
    main()
EOF

cat > "$WORKSPACE_DIR/config.py" << 'EOF'
# Configuration file
DATABASE_URL = "postgresql://localhost/demo"
API_KEY = "demo_key_12345"
DEBUG = True
LOG_LEVEL = "INFO"
EOF

cat > "$WORKSPACE_DIR/test.py" << 'EOF'
import unittest
from main import process_data

class TestProcessData(unittest.TestCase):
    def test_doubles_values(self):
        self.assertEqual(process_data([1, 2, 3]), [2, 4, 6])
    
    def test_empty_list(self):
        self.assertEqual(process_data([]), [])

if __name__ == '__main__':
    unittest.main()
EOF

cat > "$WORKSPACE_DIR/utils.py" << 'EOF'
def helper_function(x):
    """A utility helper function"""
    return x + 1

def format_output(data):
    """Format data for display"""
    return ", ".join(str(x) for x in data)
EOF

cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Demo Project

This is a sample project for the live coding presentation.

## Features
- Data processing pipeline
- Unit tests
- Configuration management

## Usage