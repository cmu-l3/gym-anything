#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Genomic QC Pipeline Result ==="

WORKSPACE_DIR="/home/ga/workspace/genomic_pipeline"
RESULT_FILE="/tmp/genomic_pipeline_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Best-effort: focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1

echo "Saving all files..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Remove any stale result file
rm -f "$RESULT_FILE"

# Check if output.json was generated
OUTPUT_JSON_PATH="$WORKSPACE_DIR/output.json"
FILE_CREATED_DURING_TASK="false"
if [ -f "$OUTPUT_JSON_PATH" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_JSON_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Collect all relevant source files into a single JSON dict
python3 << PYEXPORT
import json
import os

workspace = "$WORKSPACE_DIR"
output_path = "$OUTPUT_JSON_PATH"
created_during_task = "$FILE_CREATED_DURING_TASK" == "true"

files_to_export = {
    "src/fastq_parser.py": os.path.join(workspace, "src", "fastq_parser.py"),
    "src/sequence_utils.py": os.path.join(workspace, "src", "sequence_utils.py"),
    "src/translator.py": os.path.join(workspace, "src", "translator.py"),
    "src/trimmer.py": os.path.join(workspace, "src", "trimmer.py"),
}

result = {
    "meta": {
        "output_json_exists": os.path.exists(output_path),
        "output_json_created_during_task": created_during_task
    }
}

for label, path in files_to_export.items():
    try:
        with open(path, "r", encoding="utf-8") as f:
            result[label] = f.read()
    except FileNotFoundError:
        result[label] = None
        print(f"Warning: {path} not found")
    except Exception as e:
        result[label] = None
        print(f"Warning: error reading {path}: {e}")

# Include output.json contents if it exists
if os.path.exists(output_path):
    try:
        with open(output_path, "r", encoding="utf-8") as f:
            result["output.json"] = json.load(f)
    except Exception as e:
        result["output.json"] = f"ERROR PARSING JSON: {e}"

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

print(f"Exported files to $RESULT_FILE")
PYEXPORT

echo "=== Export Complete ==="
ls -la "$RESULT_FILE" 2>/dev/null || echo "Warning: result file not created"