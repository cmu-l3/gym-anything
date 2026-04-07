#!/bin/bash
set -e
echo "=== Exporting Remediate Cryptographic Flaws Result ==="

WORKSPACE_DIR="/home/ga/workspace/crypto_vault"
EVAL_JSON="/tmp/crypto_result.json"

# Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Force save in VSCode (Ctrl+S)
su - ga -c "DISPLAY=:1 xdotool key ctrl+s" 2>/dev/null || true
sleep 1

cd "$WORKSPACE_DIR"

# Write and execute the dynamic evaluator INSIDE the container to safely utilize dependencies
cat > /tmp/evaluator.py << 'EVALEOF'
import json
import os
import ast
import subprocess
import traceback

workspace = "/home/ga/workspace/crypto_vault"
target_file = os.path.join(workspace, "secure_vault.py")
report = {
    "ast_checks": {},
    "dynamic_checks": {},
    "pytest_passed": False,
    "git_commit": "",
    "file_modified": False,
    "error": None
}

try:
    # 1. File Modification Check
    mtime = os.path.getmtime(target_file)
    task_start = float(open('/tmp/task_start_time.txt').read().strip())
    report["file_modified"] = mtime > task_start

    # 2. AST Checks
    with open(target_file, 'r') as f:
        source = f.read()
    tree = ast.parse(source)

    def has_attr(tree, attr_name):
        return any(isinstance(node, ast.Attribute) and node.attr == attr_name for node in ast.walk(tree))

    report["ast_checks"]["uses_pbkdf2"] = has_attr(tree, 'pbkdf2_hmac')
    report["ast_checks"]["uses_md5"] = has_attr(tree, 'md5')
    report["ast_checks"]["uses_gcm"] = has_attr(tree, 'GCM')
    report["ast_checks"]["uses_cbc_or_ecb"] = has_attr(tree, 'CBC') or has_attr(tree, 'ECB')
    
    # verify_token checks
    verify_token_node = next((n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'verify_token'), None)
    if verify_token_node:
        report["ast_checks"]["uses_compare_digest"] = has_attr(verify_token_node, 'compare_digest')
        report["ast_checks"]["uses_eq"] = any(isinstance(node, ast.Eq) for node in ast.walk(verify_token_node))
    else:
        report["ast_checks"]["uses_compare_digest"] = False
        report["ast_checks"]["uses_eq"] = True

    # generate_api_key checks
    api_key_node = next((n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'generate_api_key'), None)
    if api_key_node:
        report["ast_checks"]["uses_secrets_choice"] = any(
            isinstance(n, ast.Attribute) and n.attr == 'choice' and getattr(n.value, 'id', '') == 'secrets'
            for n in ast.walk(api_key_node)
        )
        report["ast_checks"]["uses_random_choice"] = any(
            isinstance(n, ast.Attribute) and n.attr == 'choice' and getattr(n.value, 'id', '') == 'random'
            for n in ast.walk(api_key_node)
        )
    else:
        report["ast_checks"]["uses_secrets_choice"] = False
        report["ast_checks"]["uses_random_choice"] = True

    # 3. Dynamic Cryptographic Checks
    import sys
    sys.path.insert(0, workspace)
    import secure_vault

    # Check nonce randomness
    key = b'12345678901234567890123456789012' # 32 bytes
    plaintext = b"Test dynamic verification string."
    try:
        c1 = secure_vault.encrypt_data(key, plaintext)
        c2 = secure_vault.encrypt_data(key, plaintext)
        report["dynamic_checks"]["nonce_is_random"] = (c1 != c2)
    except Exception as e:
        report["dynamic_checks"]["nonce_is_random"] = False
        report["dynamic_checks"]["encrypt_error"] = str(e)

    # 4. Pytest
    pytest_run = subprocess.run(["pytest", "tests/test_vault.py"], cwd=workspace, capture_output=True, text=True)
    report["pytest_passed"] = (pytest_run.returncode == 0)

    # 5. Git commit check
    git_log = subprocess.run(["git", "log", "-1", "--pretty=%B"], cwd=workspace, capture_output=True, text=True)
    report["git_commit"] = git_log.stdout.strip()

except Exception as e:
    report["error"] = traceback.format_exc()

with open("/tmp/crypto_result.json", "w") as f:
    json.dump(report, f, indent=2)
EVALEOF

# Run evaluator
su - ga -c "python3 /tmp/evaluator.py"

echo "=== Export complete ==="