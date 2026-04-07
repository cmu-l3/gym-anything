#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Tokenizer Pipeline Result ==="

WORKSPACE_DIR="/home/ga/workspace/tokenizer"
RESULT_FILE="/tmp/tokenizer_result.json"

# Best-effort: focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1

echo "Saving all files..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

rm -f "$RESULT_FILE"

# Collect all modified files into a single JSON dictionary for the verifier
python3 << PYEXPORT
import json, os

workspace = "$WORKSPACE_DIR"

files_to_export = {
    "tokenizer/pre_tokenizers.py": os.path.join(workspace, "tokenizer", "pre_tokenizers.py"),
    "tokenizer/bpe_builder.py":    os.path.join(workspace, "tokenizer", "bpe_builder.py"),
    "tokenizer/decoder.py":        os.path.join(workspace, "tokenizer", "decoder.py"),
}

result = {}
for label, path in files_to_export.items():
    try:
        with open(path, "r", encoding="utf-8") as f:
            result[label] = f.read()
    except FileNotFoundError:
        result[label] = None
    except Exception as e:
        result[label] = f"ERROR: {e}"

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

PYEXPORT

echo "=== Export Complete ==="