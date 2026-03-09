#!/bin/bash
echo "=== Exporting code_simple_experiment result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python call for all analysis
python3 << 'PYEOF'
import json
import os
import sys
import ast
import datetime
import subprocess

OUTPUT_FILE = "/home/ga/PsychoPyExperiments/simple_rt.py"
RESULT_FILE = "/tmp/code_simple_experiment_result.json"

results = {
    "file_exists": False,
    "file_modified": False,
    "file_size": 0,
    "line_count": 0,
    "syntax_valid": False,
    "has_visual_import": False,
    "has_core_import": False,
    "has_event_import": False,
    "has_window": False,
    "has_textstim": False,
    "has_waitkeys": False,
    "has_draw": False,
    "has_flip": False,
    "has_close": False,
    "psychopy_running": False,
    "task_start_time": 0,
    "result_nonce": "",
    "timestamp": datetime.datetime.now().isoformat(),
    # Anti-gaming: structural complexity
    "code_line_count": 0,  # non-comment, non-blank lines
    "has_expected_text": False,  # checks for 'Press SPACE' text
    "has_bare_psychopy_import": False,  # bare 'import psychopy' (no submodules)
}

# Read task start time
try:
    with open("/home/ga/.task_start_time") as f:
        results["task_start_time"] = int(f.read().strip())
except:
    pass

# Read nonce
try:
    with open("/home/ga/.task_nonce") as f:
        results["result_nonce"] = f.read().strip()
except:
    pass

# PsychoPy running
try:
    ps = subprocess.run(["pgrep", "-f", "psychopy"], capture_output=True)
    results["psychopy_running"] = ps.returncode == 0
except:
    pass

if os.path.isfile(OUTPUT_FILE):
    results["file_exists"] = True
    results["file_size"] = os.path.getsize(OUTPUT_FILE)

    with open(OUTPUT_FILE) as f:
        source = f.read()

    results["line_count"] = source.count("\n") + 1

    # Count non-comment, non-blank lines
    code_lines = [l.strip() for l in source.split("\n")
                  if l.strip() and not l.strip().startswith("#")]
    results["code_line_count"] = len(code_lines)

    # Check modification time
    mtime = int(os.path.getmtime(OUTPUT_FILE))
    if mtime > results["task_start_time"]:
        results["file_modified"] = True

    # Validate Python syntax
    try:
        compile(source, OUTPUT_FILE, "exec")
        results["syntax_valid"] = True
    except SyntaxError:
        pass

    # AST analysis for imports and function calls
    try:
        tree = ast.parse(source)

        for node in ast.walk(tree):
            # Check imports
            if isinstance(node, (ast.Import, ast.ImportFrom)):
                module = ""
                if isinstance(node, ast.ImportFrom) and node.module:
                    module = node.module
                names = [alias.name for alias in node.names]
                if "psychopy" in module or "psychopy" in names:
                    if "visual" in names or "visual" in module:
                        results["has_visual_import"] = True
                    if "core" in names or "core" in module:
                        results["has_core_import"] = True
                    if "event" in names or "event" in module:
                        results["has_event_import"] = True
                    # Bare `import psychopy` without specific submodules
                    if "psychopy" in names and "visual" not in names:
                        results["has_bare_psychopy_import"] = True

            # Check function calls
            if isinstance(node, ast.Call):
                func = node.func
                if isinstance(func, ast.Attribute):
                    attr = func.attr
                    if attr == "Window":
                        results["has_window"] = True
                    elif attr == "TextStim":
                        results["has_textstim"] = True
                        # Check text argument for expected content (require both "press" and "space")
                        for kw in node.keywords:
                            if kw.arg == "text" and isinstance(kw.value, ast.Constant):
                                val = str(kw.value.value).lower()
                                if "press" in val and "space" in val:
                                    results["has_expected_text"] = True
                        # Also check positional args
                        for arg in node.args:
                            if isinstance(arg, ast.Constant) and isinstance(arg.value, str):
                                val = arg.value.lower()
                                if "press" in val and "space" in val:
                                    results["has_expected_text"] = True
                    elif attr == "waitKeys":
                        results["has_waitkeys"] = True
                    elif attr == "draw":
                        results["has_draw"] = True
                    elif attr == "flip":
                        results["has_flip"] = True
                    elif attr in ("close", "quit"):
                        results["has_close"] = True
                elif isinstance(func, ast.Name):
                    if func.id == "Window":
                        results["has_window"] = True
                    elif func.id == "TextStim":
                        results["has_textstim"] = True
                    elif func.id == "waitKeys":
                        results["has_waitkeys"] = True

            # Check for string containing expected text (only in TextStim context)
            # Removed: global string constant check was too broad

    except Exception as e:
        print(f"AST analysis error: {e}", file=sys.stderr)

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/code_simple_experiment_result.json
echo "=== Export complete ==="
