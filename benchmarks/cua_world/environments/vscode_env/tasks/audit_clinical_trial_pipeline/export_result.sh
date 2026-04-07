#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Clinical Trial Pipeline Result ==="

WORKSPACE_DIR="/home/ga/workspace/clinical_trial_analysis"
RESULT_FILE="/tmp/clinical_trial_result.json"

# Best-effort: focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1

echo "Saving all files..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Remove any stale result file (Lesson 132)
rm -f "$RESULT_FILE"

# Collect all relevant source files into a single JSON dict
python3 << PYEXPORT
import json, os

workspace = "$WORKSPACE_DIR"

files_to_export = {
    "config.py":                    os.path.join(workspace, "config.py"),
    "analysis/data_loader.py":      os.path.join(workspace, "analysis", "data_loader.py"),
    "analysis/primary_endpoint.py": os.path.join(workspace, "analysis", "primary_endpoint.py"),
    "analysis/safety_analysis.py":  os.path.join(workspace, "analysis", "safety_analysis.py"),
    "analysis/subgroup_analysis.py":os.path.join(workspace, "analysis", "subgroup_analysis.py"),
    "analysis/report_generator.py": os.path.join(workspace, "analysis", "report_generator.py"),
    "run_analysis.py":              os.path.join(workspace, "run_analysis.py"),
}

result = {}
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

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

print(f"Exported {len([v for v in result.values() if v is not None])} files to $RESULT_FILE")
PYEXPORT

echo "=== Export Complete ==="
ls -la "$RESULT_FILE" 2>/dev/null || echo "Warning: result file not created"
