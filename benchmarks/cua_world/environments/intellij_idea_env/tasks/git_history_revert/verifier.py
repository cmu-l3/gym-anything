#!/usr/bin/env python3
"""
Verifier for git_history_revert task.

Criteria:
1. Revert commit exists in git log (20 pts)
2. Factorial method logic is correct (n-1 not n-2) (25 pts)
3. All tests pass (20 pts)
4. Project compiles (10 pts)
5. History integrity (approx 9 commits, features preserved) (10 pts)
6. VLM Verification (15 pts)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_git_history_revert(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load result
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

    score = 0
    feedback_parts = []
    
    # 1. Revert Commit (20 pts)
    if result.get("has_revert_commit"):
        score += 20
        feedback_parts.append("Revert commit detected")
    else:
        feedback_parts.append("No 'Revert' commit found in recent history")

    # 2. Code Correctness (25 pts)
    content = result.get("math_utils_content", "")
    if "factorial(n - 1)" in content:
        score += 25
        feedback_parts.append("Factorial logic corrected (n-1)")
    elif "factorial(n - 2)" in content:
        feedback_parts.append("Bug still present (n-2)")
    else:
        feedback_parts.append("Recursive call not found in factorial method")

    # 3. Tests Pass (20 pts)
    if result.get("test_result") == "pass":
        score += 20
        feedback_parts.append("All tests passed")
    else:
        failed = result.get("tests_failed", 0)
        feedback_parts.append(f"Tests failed ({failed} failures)")

    # 4. Compilation/Features Preserved (20 pts)
    # If tests ran (pass or fail), it compiled.
    # Also check if features from later commits (GCD, Palindrome) are still there.
    # This ensures they didn't just 'git reset --hard' to an old commit.
    feats = result.get("feature_check", {})
    features_present = feats.get("has_gcd", 0) > 0 and feats.get("has_palindrome", 0) > 0
    
    if features_present:
        score += 10
        feedback_parts.append("Later features (GCD, Palindrome) preserved")
    else:
        feedback_parts.append("Later features missing (possible hard reset used instead of revert)")

    if result.get("test_result") in ["pass", "fail"]: # Meaning maven ran
        score += 10
        feedback_parts.append("Project compiles")

    # 5. History Integrity (5 pts)
    # We expect 9 commits (8 original + 1 revert). 
    # If they did reset --hard, it would be 4 or 5.
    count = result.get("commit_count", 0)
    if count >= 9:
        score += 5
        feedback_parts.append("Git history length correct")
    
    # 6. VLM Verification (Traj check)
    vlm_score = 0
    from utils.intellij_verification_utils import vlm_verify_intellij_task
    
    vlm_result = vlm_verify_intellij_task(
        traj, env_info, task_info['description'],
        checklist_items=[
            "Git Log tab or window visible",
            "Context menu showing 'Revert Commit' or terminal running 'git revert'",
            "Test results panel showing all green/passed"
        ]
    )
    
    if vlm_result:
        vlm_score = min(vlm_result['vlm_score'], 20) # Cap at 20
        if vlm_result['vlm_passed']:
            score += vlm_score
            feedback_parts.append(f"VLM verified workflow ({vlm_score} pts)")
        else:
             feedback_parts.append(f"VLM verification weak: {vlm_result['vlm_feedback']}")
    
    # Final check
    # Need at least Code Correctness AND Revert Commit OR Code Correctness AND Tests Pass with History
    passed = score >= 60 and ("factorial(n - 1)" in content)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }