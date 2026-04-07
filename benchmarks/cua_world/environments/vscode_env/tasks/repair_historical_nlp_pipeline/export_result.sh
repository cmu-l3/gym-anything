#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Exporting Repair Historical NLP Pipeline Result ==="

WORKSPACE_DIR="/home/ga/workspace/historical_nlp"
RESULT_FILE="/tmp/nlp_pipeline_result.json"

# Best-effort: focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run the test suite and capture output
echo "Running pytest..."
cd "$WORKSPACE_DIR"
sudo -u ga pytest tests/ > /tmp/pytest_output.txt 2>&1 || true
PYTEST_EXIT_CODE=$?

# Run the pipeline E2E script
sudo -u ga python3 run_pipeline.py data/raw_gutenberg_excerpt.txt output/cleaned.jsonl > /tmp/e2e_output.txt 2>&1 || true

# Hash the tests directory again
FINAL_TEST_HASH=$(find "$WORKSPACE_DIR/tests" -type f -exec md5sum {} + | sort | md5sum | awk '{print $1}')
INITIAL_TEST_HASH=$(cat /tmp/initial_tests_hash.txt)

# Gather file contents
python3 << PYEXPORT
import json, os

workspace = "$WORKSPACE_DIR"

files_to_export = {
    "pipeline/normalizer.py":       os.path.join(workspace, "pipeline", "normalizer.py"),
    "pipeline/cleaner.py":          os.path.join(workspace, "pipeline", "cleaner.py"),
    "pipeline/sentence_splitter.py":os.path.join(workspace, "pipeline", "sentence_splitter.py"),
    "pipeline/bpe_tokenizer.py":    os.path.join(workspace, "pipeline", "bpe_tokenizer.py"),
    "output/cleaned.jsonl":         os.path.join(workspace, "output", "cleaned.jsonl"),
    "pytest_output.txt":            "/tmp/pytest_output.txt"
}

result = {
    "initial_test_hash": "$INITIAL_TEST_HASH",
    "final_test_hash": "$FINAL_TEST_HASH",
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "files": {}
}

for label, path in files_to_export.items():
    try:
        with open(path, "r", encoding="utf-8") as f:
            result["files"][label] = f.read()
    except FileNotFoundError:
        result["files"][label] = None
    except Exception as e:
        result["files"][label] = f"ERROR: {e}"

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

print(f"Exported files to $RESULT_FILE")
PYEXPORT

chmod 666 "$RESULT_FILE"
echo "=== Export Complete ==="