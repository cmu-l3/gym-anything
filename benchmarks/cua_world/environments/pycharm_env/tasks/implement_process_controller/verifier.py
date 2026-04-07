#!/usr/bin/env python3
"""
Verifier for implement_process_controller task.

SCORING CRITERIA:
1. Transition Logic (30 pts): 8/8 tests in test_transitions.py pass
2. Guard Logic (30 pts): 6/6 tests in test_guards.py pass
3. Action Logic (25 pts): 6/6 tests in test_actions.py pass
4. Code Quality (15 pts):
   - 5 pts: Source files exist and are not empty
   - 5 pts: Valid Python syntax in implementation files
   - 5 pts: Test files intact (anti-gaming check)

Pass threshold: 60/100
"""

import json
import os
import tempfile
import ast

def check_syntax(code_str):
    """Return True if code_str has valid Python syntax."""
    try:
        ast.parse(code_str)
        return True
    except SyntaxError:
        return False

def verify_implement_process_controller(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    task_name = "implement_process_controller"
    result_path = f"/tmp/{task_name}_result.json"

    # Retrieve result JSON
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env(result_path, tmp_path)
            with open(tmp_path, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to retrieve or parse result file: {str(e)}",
        }

    score = 0
    feedback_parts = []

    # Test Counts (from export script)
    trans_pass = result.get("transition_tests_passed", 0)
    guards_pass = result.get("guard_tests_passed", 0)
    actions_pass = result.get("action_tests_passed", 0)
    total_passed = result.get("tests_passed", 0)
    
    # Expected totals
    TRANS_TOTAL = 8
    GUARDS_TOTAL = 6
    ACTIONS_TOTAL = 6

    # 1. Transition Logic (30 pts)
    # Proportional scoring
    trans_score = int(30 * (trans_pass / TRANS_TOTAL)) if TRANS_TOTAL > 0 else 0
    score += trans_score
    if trans_pass == TRANS_TOTAL:
        feedback_parts.append(f"Transition logic: Perfect ({trans_pass}/{TRANS_TOTAL})")
    else:
        feedback_parts.append(f"Transition logic: {trans_pass}/{TRANS_TOTAL} passed")

    # 2. Guard Logic (30 pts)
    guards_score = int(30 * (guards_pass / GUARDS_TOTAL)) if GUARDS_TOTAL > 0 else 0
    score += guards_score
    if guards_pass == GUARDS_TOTAL:
        feedback_parts.append(f"Guard logic: Perfect ({guards_pass}/{GUARDS_TOTAL})")
    else:
        feedback_parts.append(f"Guard logic: {guards_pass}/{GUARDS_TOTAL} passed")

    # 3. Action Logic (25 pts)
    actions_score = int(25 * (actions_pass / ACTIONS_TOTAL)) if ACTIONS_TOTAL > 0 else 0
    score += actions_score
    if actions_pass == ACTIONS_TOTAL:
        feedback_parts.append(f"Action logic: Perfect ({actions_pass}/{ACTIONS_TOTAL})")
    else:
        feedback_parts.append(f"Action logic: {actions_pass}/{ACTIONS_TOTAL} passed")

    # 4. Code Quality & Integrity (15 pts)
    
    # Test Integrity (Anti-gaming)
    if result.get("test_integrity", False):
        score += 5
        feedback_parts.append("Test integrity: Valid (+5)")
    else:
        feedback_parts.append("Test integrity: FAIL (Test files modified!)")

    # Source files existence
    if result.get("source_files_exist", False):
        score += 5
        feedback_parts.append("Source files: Present (+5)")
    else:
        feedback_parts.append("Source files: Missing or empty")

    # Syntax check (requires reading files)
    syntax_ok = True
    for fname in ["machine.py", "guards.py", "actions.py"]:
        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix=".py") as tmp:
                remote_path = f"/home/ga/PycharmProjects/process_controller/controller/{fname}"
                copy_from_env(remote_path, tmp.name)
                with open(tmp.name, "r") as f:
                    content = f.read()
                    if not check_syntax(content):
                        syntax_ok = False
                        feedback_parts.append(f"Syntax Error in {fname}")
        except:
            syntax_ok = False
            feedback_parts.append(f"Could not read {fname}")
    
    if syntax_ok:
        score += 5
        feedback_parts.append("Syntax: Valid (+5)")

    # Final tally
    passed = score >= 60 and total_passed > 10
    
    summary = f"Score: {score}/100 | Tests Passed: {total_passed}/20"
    return {
        "passed": passed,
        "score": score,
        "feedback": f"{summary} | " + " | ".join(feedback_parts)
    }