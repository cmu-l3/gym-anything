#!/bin/bash
set -e
echo "=== Exporting export_registry_backup result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

OUTPUT_FILE="/home/ga/Documents/registry_backup.json"
RESULT_JSON="/tmp/task_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Prepare the python analysis script
# This script runs INSIDE the container to analyze the file and the database
cat > /tmp/analyze_export.py << 'PYEOF'
import os
import sys
import json
import django
from django.conf import settings
from datetime import datetime

# Setup Django environment to query DB
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')

# Load env vars manually since we are running a standalone script
try:
    with open('/opt/aerobridge/.env') as f:
        for line in f:
            line = line.strip()
            if '=' in line and not line.startswith('#'):
                k, _, v = line.partition('=')
                os.environ.setdefault(k, v.strip("'").strip('"'))
except Exception as e:
    print(f"Warning: could not parse .env: {e}", file=sys.stderr)

try:
    django.setup()
except Exception as e:
    print(f"Warning: django setup failed: {e}", file=sys.stderr)

def analyze():
    output_path = "/home/ga/Documents/registry_backup.json"
    result = {
        "file_exists": False,
        "file_size": 0,
        "file_mtime": 0,
        "valid_json": False,
        "is_fixture_structure": False,
        "indentation_style": "unknown",
        "model_counts_file": {},
        "model_counts_db": {},
        "registry_models_present": 0,
        "error": None
    }
    
    # 1. Check file metadata
    if os.path.exists(output_path):
        result["file_exists"] = True
        stat = os.stat(output_path)
        result["file_size"] = stat.st_size
        result["file_mtime"] = stat.st_mtime
        
        # 2. Check indentation (simple heuristic before parsing)
        try:
            with open(output_path, 'r') as f:
                head = [next(f) for _ in range(10)]
            # If pretty printed with indent 2, we expect lines starting with 2 spaces
            # Compact JSON typically has no newlines or very few
            if len(head) > 1:
                # Check for 2-space indent pattern: line starts with "  " but not "   " or "    "
                starts_with_2 = any(line.startswith('  ') and not line.startswith('   ') for line in head)
                starts_with_4 = any(line.startswith('    ') for line in head)
                
                if starts_with_2:
                    result["indentation_style"] = "indent_2"
                elif starts_with_4:
                    result["indentation_style"] = "indent_4"
                else:
                    result["indentation_style"] = "other_multiline"
            else:
                result["indentation_style"] = "compact"
        except Exception as e:
            result["indentation_style"] = "error"

        # 3. Parse JSON and count models
        try:
            with open(output_path, 'r') as f:
                data = json.load(f)
            
            result["valid_json"] = True
            
            if isinstance(data, list):
                # Check structure of first item
                if len(data) > 0 and isinstance(data[0], dict) and 'model' in data[0] and 'pk' in data[0]:
                    result["is_fixture_structure"] = True
                
                # Count models in file
                file_counts = {}
                for item in data:
                    if isinstance(item, dict) and 'model' in item:
                        model_name = item['model']
                        file_counts[model_name] = file_counts.get(model_name, 0) + 1
                result["model_counts_file"] = file_counts
                
                # Count how many strictly belong to 'registry' app
                result["registry_models_present"] = sum(1 for m in file_counts if m.startswith('registry.'))
        except json.JSONDecodeError:
            result["valid_json"] = False
        except Exception as e:
            result["error"] = f"JSON analysis error: {str(e)}"
    
    # 4. Query Database for ground truth
    try:
        from django.apps import apps
        db_counts = {}
        # Iterate over all models in registry app
        registry_app = apps.get_app_config('registry')
        for model in registry_app.get_models():
            # Format model name as 'app_label.model_name' (lowercase) to match dumpdata output
            model_key = f"registry.{model.__name__.lower()}"
            count = model.objects.count()
            db_counts[model_key] = count
            
        result["model_counts_db"] = db_counts
    except Exception as e:
        result["error"] = f"DB query error: {str(e)}"
        
    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    analyze()
PYEOF

# Run the python script using the virtual environment
echo "Running analysis script..."
/opt/aerobridge_venv/bin/python3 /tmp/analyze_export.py > "$RESULT_JSON" 2>/tmp/analysis_error.log || true

# Append task timing info to the result
# We use jq if available, or python to merge dicts, or just hack it with sed if needed
# Since we have python, let's use it to merge the timing info
python3 -c "
import json
import time

try:
    with open('$RESULT_JSON', 'r') as f:
        data = json.load(f)
except:
    data = {}

data['task_start_time'] = $TASK_START
data['export_time'] = time.time()
data['screenshot_path'] = '/tmp/task_final_state.png'

with open('$RESULT_JSON', 'w') as f:
    json.dump(data, f)
"

# Set permissions so verifier can copy it
chmod 666 "$RESULT_JSON" 2>/dev/null || true

echo "Result stored in $RESULT_JSON"
echo "=== Export complete ==="