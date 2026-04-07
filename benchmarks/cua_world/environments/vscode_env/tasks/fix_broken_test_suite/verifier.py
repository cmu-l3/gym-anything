#!/usr/bin/env python3
"""
Verifier for fix_broken_test_suite task.

Scores 6 bugs. Each bug has:
- 8 pts for static pattern matching on the fixed test code
- 8 pts for behavioral validation (test fails when library is buggy)
- Max 96 for bugs. +4 points for VLM visual verification.
- Pass threshold: 60.
"""

import os
import json
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

VERIFICATION_PROMPT = """You are verifying if an agent completed a software testing task in VS Code.
Look at these screenshots from the session.
1. Did the agent use VS Code?
2. Did the agent edit Python test files (e.g., files starting with `test_`)?
Answer in JSON:
{
    "used_vscode": true/false,
    "edited_tests": true/false
}
"""

def verify_test_suite(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/test_suite_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    test_contents = result.get('test_contents', {})
    behavioral = result.get('behavioral', {})
    
    # ── Bug 1: Stock Boundary (test_stock_operations.py) ──
    code1 = test_contents.get('test_stock_operations.py', '')
    if "100" in code1 and "10" not in code1.replace("100", ""): 
        # Pattern: changed 10 to 100
        score += 8
        feedback_parts.append("[+] Bug 1 pattern match")
    elif code1.count("100") >= 2:
        score += 8
        feedback_parts.append("[+] Bug 1 pattern match (setup/assert consistent)")
    if behavioral.get('bug1_caught'):
        score += 8
        feedback_parts.append("[+] Bug 1 behavioral: Caught buggy stock limit")

    # ── Bug 2: Float Comparison (test_pricing.py) ──
    code2 = test_contents.get('test_pricing.py', '')
    if "assertAlmostEqual" in code2 or "approx" in code2 or "isclose" in code2:
        score += 8
        feedback_parts.append("[+] Bug 2 pattern match: Uses float-safe assertion")
    if behavioral.get('bug2_caught'):
        score += 8
        feedback_parts.append("[+] Bug 2 behavioral: Caught broken pricing math")

    # ── Bug 3: Wrong Mock Target (test_alerts.py) ──
    code3 = test_contents.get('test_alerts.py', '')
    if "_dispatch_email" in code3 and "send_notification" not in code3:
        score += 8
        feedback_parts.append("[+] Bug 3 pattern match: Patched correct target")
    if behavioral.get('bug3_caught'):
        score += 8
        feedback_parts.append("[+] Bug 3 behavioral: Caught false negative alert")

    # ── Bug 4: Atomicity Assertion (test_transfers.py) ──
    code4 = test_contents.get('test_transfers.py', '')
    if "SRC" in code4 and code4.count("assertEqual") >= 2:
        score += 8
        feedback_parts.append("[+] Bug 4 pattern match: Checks source deduction")
    if behavioral.get('bug4_caught'):
        score += 8
        feedback_parts.append("[+] Bug 4 behavioral: Caught missing deduction")

    # ── Bug 5: Date Mocking (test_reports.py) ──
    code5 = test_contents.get('test_reports.py', '')
    if "freeze_time" in code5 or "patch" in code5 or "Mock" in code5:
        score += 8
        feedback_parts.append("[+] Bug 5 pattern match: Time mocking detected")
    if behavioral.get('bug5_caught'):
        score += 8
        feedback_parts.append("[+] Bug 5 behavioral: Caught hardcoded date")

    # ── Bug 6: Thread Join Timeout (test_concurrent_access.py) ──
    code6 = test_contents.get('test_concurrent_access.py', '')
    if "join()" in code6 and "timeout" not in code6:
        score += 8
        feedback_parts.append("[+] Bug 6 pattern match: Join is blocking")
    elif "assertEqual" in code6 and "100" in code6:
        # Better assertion
        score += 4
        feedback_parts.append("[~] Bug 6 pattern match: Improved assertion")
    
    if behavioral.get('bug6_caught'):
        score += 8
        feedback_parts.append("[+] Bug 6 behavioral: Caught race condition")

    # VLM Verification
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        if final:
            vlm_res = query_vlm(prompt=VERIFICATION_PROMPT, images=frames + [final])
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("used_vscode") and parsed.get("edited_tests"):
                    vlm_score = 4
                    score += vlm_score
                    feedback_parts.append("[+] VLM confirmed VSCode test editing")

    # Base requirements
    if not result.get("all_pass_correct", False):
        score -= 20
        feedback_parts.append("[-] Penalty: Tests failed against CORRECT library")

    passed = score >= task_info.get("metadata", {}).get("pass_threshold", 60)
    
    return {
        "passed": passed,
        "score": max(0, min(100, score)),
        "feedback": " | ".join(feedback_parts)
    }