#!/usr/bin/env python3
import json
import os
import tempfile

def verify_fix_gdpr_data_cleaner(traj, env_info, task_info):
    """
    Verify that the GDPR data cleaner pipeline is fixed.
    
    Criteria:
    1. Tests Pass (25 pts): pytest exit code 0.
    2. Stable Hashing (25 pts): Running pipeline twice produces identical hashes.
    3. Data Retention (25 pts): Row count > 480 (indicates phone regex relaxed).
    4. IP Privacy (25 pts): Output IPs match 'x.x.x.xxx' format.
    
    Pass Threshold: 100 points.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env not available"
        }
    
    task_name = "fix_gdpr_data_cleaner"
    result_path = f"/tmp/{task_name}_result.json"
    
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env(result_path, tmp_path)
            with open(tmp_path, "r") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load result JSON: {str(e)}"
        }

    score = 0
    feedback = []
    
    # 1. Tests Pass
    if result.get("all_tests_pass", False):
        score += 25
        feedback.append("Tests passed (25/25)")
    else:
        feedback.append(f"Tests failed: {result.get('tests_failed', 0)} failures")

    # 2. Stable Hashing
    if result.get("hashes_stable") == "true":
        score += 25
        feedback.append("Hashing is deterministic (25/25)")
    elif result.get("hashes_stable") == "missing_column":
        feedback.append("Hashing failed: email_hash column missing")
    else:
        feedback.append("Hashing failed: Non-deterministic results detected (did you remove hash()?)")

    # 3. Data Retention (Phone Regex)
    # Original count 500. Bad regex drops ~30%. Good regex should drop < 5% (truly bad data).
    rows = result.get("row_count", 0)
    if rows >= 480:
        score += 25
        feedback.append(f"Data retention good: {rows} rows (25/25)")
    else:
        feedback.append(f"Data retention poor: {rows} rows (Too many valid phone numbers dropped?)")

    # 4. IP Privacy
    if result.get("ip_mask_correct") == "true":
        score += 25
        feedback.append("IP masking correct (25/25)")
    else:
        feedback.append("IP masking incorrect (Expected format x.x.x.xxx)")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }