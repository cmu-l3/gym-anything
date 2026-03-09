#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Recover from Timeline Task ==="

WORKSPACE_DIR="/home/ga/workspace"
FILE_PATH="${WORKSPACE_DIR}/data_processor.py"
VSCODE_SETTINGS="/home/ga/.config/Code/User/settings.json"

# Create workspace directory
sudo -u ga mkdir -p "${WORKSPACE_DIR}"

# Ensure Timeline and local history features are enabled
echo "Configuring VSCode settings for Timeline..."
sudo -u ga mkdir -p "$(dirname "${VSCODE_SETTINGS}")"

# Update or create settings to enable Timeline
if [ -f "${VSCODE_SETTINGS}" ]; then
    # Backup existing settings
    sudo -u ga cp "${VSCODE_SETTINGS}" "${VSCODE_SETTINGS}.bak"
    
    # Update settings to ensure Timeline is enabled
    sudo -u ga python3 << 'PYEOF'
import json
import os

settings_path = "/home/ga/.config/Code/User/settings.json"
try:
    with open(settings_path, 'r') as f:
        settings = json.load(f)
except:
    settings = {}

# Enable Timeline and local history
settings['timeline.showView'] = True
settings['workbench.localHistory.enabled'] = True
settings['workbench.localHistory.maxFileSize'] = 5242880
settings['workbench.localHistory.maxFileEntries'] = 50

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)

print("VSCode settings updated for Timeline")
PYEOF
else
    # Create new settings file
    sudo -u ga bash -c 'cat > '"${VSCODE_SETTINGS}"' << '\''SETTINGSEOF'\''
{
  "timeline.showView": true,
  "workbench.localHistory.enabled": true,
  "workbench.localHistory.maxFileSize": 5242880,
  "workbench.localHistory.maxFileEntries": 50
}
SETTINGSEOF'
fi

echo "Creating file history for Timeline..."

# Step 1: Create ORIGINAL working version (with validate_headers function)
sudo -u ga bash -c 'cat > '"${FILE_PATH}"' << '\''ORIGINAL_EOF'\''
"""
Data processing utilities for CSV transformation pipeline
"""
import csv
from typing import List, Dict, Any


def read_csv_file(filepath: str) -> List[Dict[str, Any]]:
    """Read CSV file and return list of dictionaries."""
    with open(filepath, '\''r'\'', encoding='\''utf-8'\'') as f:
        reader = csv.DictReader(f)
        return list(reader)


def validate_headers(filepath: str, required_headers: List[str]) -> bool:
    """
    Validate that CSV file contains all required headers.
    
    Args:
        filepath: Path to CSV file
        required_headers: List of header names that must be present
        
    Returns:
        True if all required headers present, False otherwise
        
    Raises:
        FileNotFoundError: If file doesn'\''t exist
        ValueError: If file is empty or has no headers
    """
    with open(filepath, '\''r'\'', encoding='\''utf-8'\'') as f:
        reader = csv.DictReader(f)
        actual_headers = reader.fieldnames
        
        if not actual_headers:
            raise ValueError(f"No headers found in {filepath}")
        
        missing = set(required_headers) - set(actual_headers)
        if missing:
            print(f"Missing required headers: {missing}")
            return False
        
        return True


def transform_row(row_data: Dict[str, Any]) -> Dict[str, Any]:
    """Transform a single row of data."""
    # Apply transformations here
    result = {}
    for key, value in row_data.items():
        result[key.lower().strip()] = value.strip() if value else ""
    return result


def write_csv_file(filepath: str, row_data: List[Dict[str, Any]]) -> None:
    """Write list of dictionaries to CSV file."""
    if not row_data:
        return
    
    with open(filepath, '\''w'\'', encoding='\''utf-8'\'', newline='\'\'') as f:
        writer = csv.DictWriter(f, fieldnames=row_data[0].keys())
        writer.writeheader()
        writer.writerows(row_data)


def process_csv(input_file: str, output_file: str) -> bool:
    """Process CSV file with validation and transformation."""
    try:
        data = read_csv_file(input_file)
        transformed = [transform_row(row) for row in data]
        write_csv_file(output_file, transformed)
        return True
    except Exception as e:
        print(f"Error processing CSV: {e}")
        return False
ORIGINAL_EOF'

echo "Original file created with validate_headers function"

# Wait to create distinct timestamp for Timeline
sleep 4

# Step 2: Make a minor edit to create another history entry
# This simulates normal editing workflow
sudo -u ga bash -c 'echo "" >> '"${FILE_PATH}"
sudo -u ga bash -c 'echo "# Last modified: $(date)" >> '"${FILE_PATH}"

echo "Made minor edit to create history entry"

# Wait again to create clear separation in Timeline
sleep 4

# Step 3: Create the BROKEN version (missing validate_headers)
sudo -u ga bash -c 'cat > '"${FILE_PATH}"' << '\''BROKEN_EOF'\''
"""
Data processing utilities for CSV transformation pipeline
"""
import csv
from typing import List, Dict, Any


def read_csv_file(filepath: str) -> List[Dict[str, Any]]:
    """Read CSV file and return list of dictionaries."""
    with open(filepath, '\''r'\'', encoding='\''utf-8'\'') as f:
        reader = csv.DictReader(f)
        return list(reader)


def transform_row(row_data: Dict[str, Any]) -> Dict[str, Any]:
    """Transform a single row of data."""
    # Apply transformations here
    result = {}
    for key, value in row_data.items():
        result[key.lower().strip()] = value.strip() if value else ""
    return result


def write_csv_file(filepath: str, row_data: List[Dict[str, Any]]) -> None:
    """Write list of dictionaries to CSV file."""
    if not row_data:
        return
    
    with open(filepath, '\''w'\'', encoding='\''utf-8'\'', newline='\'\'') as f:
        writer = csv.DictWriter(f, fieldnames=row_data[0].keys())
        writer.writeheader()
        writer.writerows(row_data)


# Main processing pipeline
def process_csv(input_file: str, output_file: str) -> bool:
    """Process CSV file with validation and transformation."""
    try:
        # PROBLEM: validate_headers() function is MISSING here!
        # It was accidentally deleted during Find & Replace operation
        # You need to recover it using VSCode'\''s Timeline view
        
        data = read_csv_file(input_file)
        transformed = [transform_row(row) for row in data]
        write_csv_file(output_file, transformed)
        return True
    except Exception as e:
        print(f"Error processing CSV: {e}")
        return False
BROKEN_EOF'

echo "File now in 'broken' state with validate_headers() missing"

# Ensure proper ownership
sudo chown -R ga:ga "${WORKSPACE_DIR}"

# Launch VSCode with the workspace
echo "Launching VSCode..."
su - ga -c "DISPLAY=:1 code '${WORKSPACE_DIR}' '${FILE_PATH}'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Recover from Timeline Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Notice validate_headers() function is missing from data_processor.py"
echo "  2. Open Timeline view (Explorer sidebar → TIMELINE section at bottom)"
echo "  3. Browse file history to find earlier version with the function"
echo "  4. Compare or open the historical version"
echo "  5. Copy the validate_headers() function"
echo "  6. Paste it back into the current file (between read_csv_file and transform_row)"
echo "  7. Save the file (Ctrl+S)"
echo ""
echo "The function should validate CSV headers using csv.DictReader"