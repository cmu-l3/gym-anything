#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Purge Commented Dead Code Task ==="

WORKSPACE_DIR="/home/ga/workspace/comment_cleanup_project"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

# Create src/main.py
cat > "$WORKSPACE_DIR/src/main.py" << 'MAINEOF'
"""
Main application entry point.
Processes user data and generates reports.
"""
import json
from utils import format_output

# Old implementation - replaced with async version
# def process_data(data):
#     """Process data synchronously"""
#     results = []
#     for item in data:
#         results.append(transform(item))
#     return results

async def process_data(data):
    """Process data asynchronously with better performance"""
    results = []
    for item in data:
        results.append(await transform_async(item))
    return results

# print("Debug: Starting application")  # Old debug statement

def main():
    # Load configuration
    config = load_config()
    
    # Old way of loading - before we switched to JSON
    # with open('config.txt') as f:
    #     config = f.read().split('\n')
    
    data = fetch_data(config)
    results = process_data(data)
    
    # TODO: Add error handling here for network failures
    # if results is None:
    #     print("Failed to fetch")
    #     return
    
    print(format_output(results))

# Legacy function - kept for rollback
# FIXME: Remove this after v2.0 release and migration is confirmed
# def old_main():
#     """Original main function - DO NOT DELETE YET"""
#     print("Legacy mode")
#     legacy_process()

if __name__ == "__main__":
    main()
MAINEOF

# Create src/utils.py
cat > "$WORKSPACE_DIR/src/utils.py" << 'UTILSEOF'
"""Utility functions for data processing"""
# import pandas as pd  # Removed pandas dependency
# from datetime import datetime as dt  # Old import style
from datetime import datetime

def format_output(data):
    """Format data for display"""
    # Old string formatting approach
    # return "Results: %s" % str(data)
    return f"Results: {data}"

# def debug_print(msg):
#     print(f"[DEBUG] {msg}")

def validate_input(data):
    """Validate input data structure"""
    # Check for required fields
    required = ['id', 'name', 'value']
    
    # Old validation logic - too permissive
    # if 'id' in data:
    #     return True
    # return False
    
    return all(field in data for field in required)

# Helper for logging
# LOG_LEVEL = "DEBUG"  # Changed to use env var instead

def get_timestamp():
    """Get current timestamp"""
    return datetime.now().isoformat()
    # return dt.now().strftime("%Y-%m-%d %H:%M:%S")  # Old format
UTILSEOF

# Create src/data_processor.py
cat > "$WORKSPACE_DIR/src/data_processor.py" << 'PROCESSOREOF'
"""Data processing pipeline"""

class DataProcessor:
    """Handles data transformation and validation"""
    
    def __init__(self, config):
        self.config = config
        # self.cache = {}  # Removed caching due to memory issues
    
    def transform(self, item):
        """Transform a single data item"""
        # Apply business rules
        result = {
            'id': item['id'],
            'processed': True
        }
        
        # Old transformation logic - kept commented for reference
        # result['name'] = item['name'].upper()
        # result['value'] = item['value'] * 2
        
        # New transformation
        result['name'] = item['name'].title()
        result['value'] = item['value'] * 1.5
        
        return result
    
    # def batch_transform(self, items):
    #     """Old batch processing - replaced by streaming"""
    #     return [self.transform(item) for item in items]
    
    def stream_transform(self, items):
        """Stream processing for large datasets"""
        for item in items:
            yield self.transform(item)

# Experimental feature - didn't work out
# class AdvancedProcessor(DataProcessor):
#     def transform(self, item):
#         # ML-based transformation
#         model_output = self.ml_model.predict(item)
#         return model_output

def normalize_data(data):
    """Normalize data to standard format"""
    # The old normalization was too aggressive
    # data = {k: str(v).lower() for k, v in data.items()}
    return {k: v for k, v in data.items() if v is not None}
PROCESSOREOF

# Create src/legacy_handler.py
cat > "$WORKSPACE_DIR/src/legacy_handler.py" << 'LEGACYEOF'
"""
Legacy compatibility layer.
This module provides backward compatibility with old API.
"""

# NOTE: This entire module is scheduled for deprecation in Q3 2024
# See migration guide: docs/migration_v2.md

def handle_legacy_request(request):
    """
    Handle requests from old API format.
    Converts v1 API calls to v2 format.
    """
    # Modern handler
    return convert_to_v2(request)

# def handle_legacy_request_old(request):
#     """Original implementation - before v2 conversion"""
#     if request.get('version') == 1:
#         return process_v1(request)
#     return None

# Old conversion utilities - replaced by new converter
# def convert_field_names(data):
#     mapping = {'old_id': 'id', 'old_name': 'name'}
#     return {mapping.get(k, k): v for k, v in data.items()}

def convert_to_v2(request):
    """Convert v1 request to v2 format"""
    # Implementation here
    pass

# Dead code from prototype phase
# def experimental_handler(req):
#     print("Experimental")
#     try:
#         result = req.process()
#     except:
#         result = None
#     return result

# class LegacyParser:
#     def parse(self, data):
#         return data.split(',')
LEGACYEOF

# Create tests/test_main.py
cat > "$WORKSPACE_DIR/tests/test_main.py" << 'TESTEOF'
"""Unit tests for main module"""
import unittest
# from unittest.mock import Mock, patch
from src.main import main, process_data

class TestMain(unittest.TestCase):
    """Test cases for main functionality"""
    
    def test_process_data(self):
        """Test data processing"""
        data = [{'id': 1, 'value': 10}]
        # results = process_data(data)
        # self.assertEqual(len(results), 1)
        # TODO: Fix this test after async refactor
        pass
    
    # def test_old_format(self):
    #     """Test old data format - no longer supported"""
    #     data = "1,2,3,4"
    #     result = process_data(data)
    #     self.assertIsNotNone(result)
    
    def test_main_execution(self):
        """Test main function runs without error"""
        # This test needs improvement
        # Currently just checking it doesn't crash
        pass

# Old test suite - before refactoring
# class TestLegacyMain(unittest.TestCase):
#     def test_legacy_processing(self):
#         result = old_main()
#         self.assertTrue(result)
TESTEOF

# Create README.md for context
cat > "$WORKSPACE_DIR/README.md" << 'READMEEOF'
# Comment Cleanup Project

This project needs cleanup of commented-out dead code.

## Task
Remove all commented-out dead code while preserving:
- Docstrings
- TODO/FIXME/NOTE comments
- Explanatory comments

## Files
- src/main.py
- src/utils.py
- src/data_processor.py
- src/legacy_handler.py
- tests/test_main.py
READMEEOF

# Set permissions
sudo chown -R ga:ga "$WORKSPACE_DIR"
sudo chmod -R 755 "$WORKSPACE_DIR"

# Open VSCode with the workspace
echo "Opening VSCode with workspace..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open the first file to give context
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/src/main.py'" &
sleep 2

echo "=== Purge Commented Dead Code Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Review files in src/ and tests/ directories"
echo "  2. Remove commented-out dead code (old functions, imports, debug statements)"
echo "  3. Preserve docstrings and TODO/FIXME/NOTE comments"
echo "  4. Preserve explanatory comments (e.g., '# Check for required fields')"
echo "  5. Save all modified files"
echo ""
echo "Files to clean:"
echo "  - src/main.py"
echo "  - src/utils.py"
echo "  - src/data_processor.py"
echo "  - src/legacy_handler.py"
echo "  - tests/test_main.py"