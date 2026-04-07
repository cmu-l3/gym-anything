#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Infrastructure Remediation Result ==="

WORKSPACE_DIR="/home/ga/workspace/platform_infra"
RESULT_FILE="/tmp/infra_remediation_result.json"

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

# Collect all relevant config files into a single JSON dict
python3 << PYEXPORT
import json, os

workspace = "$WORKSPACE_DIR"

files_to_export = {
    "docker/Dockerfile":           os.path.join(workspace, "docker", "Dockerfile"),
    "docker/docker-compose.yml":   os.path.join(workspace, "docker", "docker-compose.yml"),
    "kubernetes/deployment.yaml":  os.path.join(workspace, "kubernetes", "deployment.yaml"),
    "terraform/main.tf":           os.path.join(workspace, "terraform", "main.tf"),
    "nginx/nginx.conf":            os.path.join(workspace, "nginx", "nginx.conf"),
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
