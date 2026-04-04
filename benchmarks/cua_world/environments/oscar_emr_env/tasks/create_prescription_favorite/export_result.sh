#!/bin/bash
echo "=== Exporting Prescription Favorite Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get Task Start Time and Initial Count
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_fav_count.txt 2>/dev/null || echo "0")

# Use Python to extract structured data from the database
# We use python3 inside the container logic via docker exec, or run python locally 
# and call docker exec. Running locally is safer for file writing.

cat << 'EOF' > /tmp/extract_favorites.py
import subprocess
import json
import sys

def get_favorites():
    # Query the drug_template table for oscardoc (999998)
    # Columns: template_id, provider_no, template_name, drug_name, brand_name, instructions, quantity, repeats
    # Note: Column names may vary slightly by Oscar version, so we select * and map by index or verify headers
    
    query = "SELECT * FROM drug_template WHERE provider_no='999998'"
    cmd = [
        "docker", "exec", "oscar-db", 
        "mysql", "-u", "oscar", "-poscar", "oscar", 
        "-e", query
    ]
    
    try:
        # Get output with headers
        output = subprocess.check_output(cmd).decode('utf-8', errors='ignore').strip()
        if not output:
            return []
            
        lines = output.split('\n')
        if len(lines) < 2:
            return []
            
        headers = lines[0].split('\t')
        results = []
        
        for line in lines[1:]:
            values = line.split('\t')
            row_dict = {}
            for i, header in enumerate(headers):
                if i < len(values):
                    row_dict[header] = values[i]
            results.append(row_dict)
            
        return results
        
    except Exception as e:
        sys.stderr.write(f"Error querying DB: {e}\n")
        return []

favorites = get_favorites()
print(json.dumps(favorites, indent=2))
EOF

# Execute the extraction script
echo "Extracting favorites data..."
python3 /tmp/extract_favorites.py > /tmp/current_favorites.json 2>/dev/null || echo "[]" > /tmp/current_favorites.json

# Check if application is running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "initial_count": $INITIAL_COUNT,
    "app_running": $APP_RUNNING,
    "favorites": $(cat /tmp/current_favorites.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"
rm -f /tmp/extract_favorites.py /tmp/current_favorites.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="