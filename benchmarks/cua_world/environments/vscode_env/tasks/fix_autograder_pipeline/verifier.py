#!/usr/bin/env python3
"""
Verifier for the fix_autograder_pipeline task.

Validates 5 bug fixes based on the resulting scores of running the agent's 
modified autograder against the predefined student submissions.
Fallback regex checks applied if grading scripts crashed.
"""

import sys
import os
import json
import re
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_autograder(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/autograder_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    scores = result.get('scores', {})
    source_files = result.get('source_files', {})
    
    total_score = 0
    feedback_parts = []
    
    script_crashed = "error" in scores
    if script_crashed:
        feedback_parts.append(f"⚠️ run_grader.py failed to run: {scores.get('error')[:100]}")

    # -------------------------------------------------------------
    # Bug 1: Timeout handling (test_runner.py)
    # Dave gets partial credit if timeouts map to "timeout" instead of "error"
    # -------------------------------------------------------------
    dave_score = scores.get("dave", 0)
    runner_src = source_files.get("test_runner.py", "")
    
    timeout_fixed = False
    if not script_crashed and dave_score > 0 and dave_score != 100:
        timeout_fixed = True
    elif 'return {"status": "timeout"' in runner_src or "status': 'timeout'" in runner_src or "status':\"timeout\"" in runner_src:
        timeout_fixed = True
        
    if timeout_fixed:
        total_score += 20
        feedback_parts.append("✅ Timeout status correctly returned for partial credit.")
    else:
        feedback_parts.append("❌ Timeout handling not fixed (timed-out code still gets 'error').")

    # -------------------------------------------------------------
    # Bug 2: Float Tolerance (output_comparator.py)
    # Carol's score becomes 100 if float math isclose is used.
    # -------------------------------------------------------------
    carol_score = scores.get("carol", 0)
    comp_src = source_files.get("output_comparator.py", "")
    
    float_fixed = False
    if not script_crashed and carol_score == 100:
        float_fixed = True
    elif re.search(r'isclose', comp_src) and 'abs(float' not in comp_src:
        float_fixed = True
        
    if float_fixed:
        total_score += 20
        feedback_parts.append("✅ Floating point tolerance check fixed.")
    else:
        feedback_parts.append("❌ Strict float absolute difference not replaced with relative tolerance.")

    # -------------------------------------------------------------
    # Bug 3: Whitespace stripping (output_comparator.py)
    # Grace's formatter submission gets 100 if trailing spaces are stripped.
    # -------------------------------------------------------------
    grace_score = scores.get("grace", 0)
    
    whitespace_fixed = False
    if not script_crashed and grace_score == 100:
        whitespace_fixed = True
    elif "a = a.strip()" in comp_src or "a.strip()" in comp_src and "lstrip" not in comp_src:
        whitespace_fixed = True
        
    if whitespace_fixed:
        total_score += 20
        feedback_parts.append("✅ Whitespace stripping made symmetric (strip vs lstrip).")
    else:
        feedback_parts.append("❌ Output comparator still uses lstrip(), failing valid trailing spaces.")

    # -------------------------------------------------------------
    # Bug 4: Integer truncation (score_calculator.py)
    # Bob gets 60 and Frank gets ~67 if truncation is removed.
    # -------------------------------------------------------------
    bob_score = scores.get("bob", 0)
    frank_score = scores.get("frank", 0)
    calc_src = source_files.get("score_calculator.py", "")
    
    truncation_fixed = False
    if not script_crashed and (bob_score == 60 or frank_score in [66, 67, 87, 88]):
        truncation_fixed = True
    elif "int(passed / total)" not in calc_src and ("round" in calc_src or "//" in calc_src or "int((passed" in calc_src):
        truncation_fixed = True
        
    if truncation_fixed:
        total_score += 20
        feedback_parts.append("✅ Integer truncation bug in percentage calculation fixed.")
    else:
        feedback_parts.append("❌ Score calculation still truncates decimals to zero.")

    # -------------------------------------------------------------
    # Bug 5: Delimiter splitting (test_parser.py)
    # Eve's formatter output contains "---", which breaks standard split.
    # -------------------------------------------------------------
    eve_score = scores.get("eve", 0)
    parser_src = source_files.get("test_parser.py", "")
    
    delimiter_fixed = False
    if not script_crashed and eve_score == 100:
        delimiter_fixed = True
    elif r'split("\n---\n")' in parser_src or r"split('\n---\n')" in parser_src:
        delimiter_fixed = True
        
    if delimiter_fixed:
        total_score += 20
        feedback_parts.append("✅ Test parser greedy delimiter splitting fixed.")
    else:
        feedback_parts.append("❌ Test parser still splits greedily on '---'.")

    # -------------------------------------------------------------
    # Anti-Gaming: Check hidden submission
    # -------------------------------------------------------------
    hidden_score = scores.get("hidden", 0)
    if not script_crashed and hidden_score not in [0, 80]:
        total_score = 0
        feedback_parts.append("🚨 Anti-gaming alert: Hidden submission scored incorrectly. Hardcoded logic detected.")

    passed = total_score >= 60
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts)
    }