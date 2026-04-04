#!/usr/bin/env python3
"""
Verifier for complete_todo_implementations task.

Criteria:
1. Compilation Success (10 pts)
2. All Tests Pass (10 pts per method x 6 = 60 pts)
3. TODOs Removed (10 pts)
4. Test Files Integrity (5 pts)
5. VLM Verification (15 pts) - Verified TODO usage and code editing
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_complete_todo_implementations(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Import VLM helpers (if available in environment)
    try:
        from gym_anything.vlm import vlm_verify_intellij_task
    except ImportError:
        vlm_verify_intellij_task = None

    # Load result JSON
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Load initial checksums
    initial_checksums = ""
    temp_chk = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/initial_test_checksums.txt", temp_chk.name)
        with open(temp_chk.name, 'r') as f:
            initial_checksums = f.read()
    except Exception:
        pass
    finally:
        if os.path.exists(temp_chk.name):
            os.unlink(temp_chk.name)

    score = 0
    feedback = []

    # 1. Compilation & Test Execution (Base Check)
    test_output = result.get("test_output", "")
    if "BUILD SUCCESS" in test_output or "Tests run:" in test_output:
        score += 10
        feedback.append("Project compilation successful (10/10)")
    else:
        feedback.append("Project failed to compile (0/10)")

    # 2. Verify Tests Passing (60 pts)
    # We parse the output to see which tests passed.
    # Expected patterns: "testIsPalindrome", "testCountWords", etc.
    # Note: If build failed, these won't be present.
    
    methods_map = {
        "testIsPalindrome": "isPalindrome",
        "testCountWords": "countWords",
        "testReverseWords": "reverseWords",
        "testGcd": "gcd",
        "testIsPrime": "isPrime",
        "testFactorial": "factorial"
    }
    
    # Simple parsing: If "Failures: 0, Errors: 0" is found at the end of summary, all pass.
    # Otherwise, look for specific failures.
    
    passing_methods = set(methods_map.values()) # Assume all pass initially
    
    if "BUILD FAILURE" in test_output or "Failures:" in test_output:
        # Regex to find failed tests
        # Format often: testName(ClassName): Message
        failed_tests = re.findall(r'test(\w+)\(', test_output) 
        # Also check for standard JUnit output like "testIsPalindrome"
        
        # A safer heuristic: check if method names appear in failure sections
        for test_name, method in methods_map.items():
            # If the test name appears near "Failure" or "Error"
            # This is a simplification; robust parsing of raw text is hard without XML.
            # We'll use a strict "Tests run: X, Failures: 0" check for perfect score,
            # and partial penalization otherwise.
            pass

    # Improved parsing logic
    # Check if ANY failures occurred
    failures_match = re.search(r'Tests run: (\d+), Failures: (\d+), Errors: (\d+)', test_output)
    total_failures = 0
    if failures_match:
        total_failures = int(failures_match.group(2)) + int(failures_match.group(3))
    
    if total_failures == 0 and "BUILD SUCCESS" in test_output:
        score += 60
        feedback.append("All tests passed (60/60)")
    else:
        # If failures exist, we assume they failed evenly unless we can prove specific ones passed.
        # Since we have 6 methods, subtract 10 pts for every failure (approx).
        points_deducted = min(60, total_failures * 10)
        score += (60 - points_deducted)
        feedback.append(f"{total_failures} test failures detected ({60 - points_deducted}/60)")

    # 3. TODO Removal (10 pts)
    su_content = result.get("string_utils_content", "")
    mu_content = result.get("math_utils_content", "")
    
    todo_count = su_content.count("// TODO") + mu_content.count("// TODO")
    if todo_count == 0:
        score += 10
        feedback.append("All TODO comments removed (10/10)")
    else:
        feedback.append(f"{todo_count} TODO comments remain (0/10)")

    # 4. Test Integrity (5 pts)
    # Check if checksums match
    current_chk = result.get("current_test_checksums", {})
    integrity_pass = True
    
    if initial_checksums:
        for line in initial_checksums.strip().split('\n'):
            parts = line.split()
            if len(parts) >= 2:
                orig_hash = parts[0]
                filename = os.path.basename(parts[1]).replace(".java", "")
                curr_hash = current_chk.get(filename, "")
                if orig_hash != curr_hash:
                    integrity_pass = False
    
    if integrity_pass:
        score += 5
        feedback.append("Test files integrity verified (5/5)")
    else:
        score = 0 # CHEATING DETECTED - Zero the score
        feedback.append("CRITICAL: Test files were modified! Score reset to 0.")

    # 5. Anti-gaming: File Modification Timestamp
    if not result.get("files_modified_during_task", False):
        if score > 0:
            score = 0
            feedback.append("CRITICAL: Source files were not modified during task time. Score reset to 0.")

    # 6. VLM Verification (15 pts)
    # We verify that the user actually used the IDE features
    vlm_score = 0
    if vlm_verify_intellij_task:
        vlm_res = vlm_verify_intellij_task(
            traj, env_info,
            "Implement 6 TODO methods in Java using IntelliJ. Open TODO tool window, edit code, run tests.",
            [
                "TODO tool window is visible (list of tasks)",
                "Editor shows code being written in StringUtils or MathUtils",
                "Tests are running (Run tool window or terminal output)"
            ]
        )
        if vlm_res and vlm_res.get("vlm_passed"):
            vlm_score = 15
            feedback.append("VLM: Workflow verified (15/15)")
        else:
            feedback.append(f"VLM: {vlm_res.get('vlm_feedback', 'Workflow not clearly observed')} (0/15)")
    else:
        # Fallback if VLM not available but code works
        if score >= 60:
            vlm_score = 15
            feedback.append("VLM: Skipped (module unavailable), assuming valid due to passing tests (15/15)")
    
    score += vlm_score

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }