#!/usr/bin/env python3
"""
Verifier for URL Rewrite SEO Migration task.

Criteria:
1. Five specific custom URL rewrites must exist.
2. Target paths must match exactly.
3. Redirect types must be correct (301 for permanent, 302 for temporary).
4. Anti-gaming: Total custom rewrite count must have increased by at least 5.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_url_rewrite_seo_migration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
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

    # 2. Extract Data
    rewrites = result.get("rewrites", {})
    initial_count = int(result.get("initial_count", 0))
    current_count = int(result.get("current_count", 0))
    
    metadata = task_info.get("metadata", {})
    expected_list = metadata.get("expected_rewrites", [])

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 3. Verify Each Rewrite (17 points per correct rewrite: 10 for existence/target, 7 for type)
    # Total for 5 rewrites = 85 points
    
    for expected in expected_list:
        req = expected["request_path"]
        exp_target = expected["target_path"]
        exp_type = str(expected["redirect_type"])
        
        actual = rewrites.get(req, {})
        exists = actual.get("exists", False)
        act_target = actual.get("target_path", "")
        act_type = str(actual.get("redirect_type", ""))
        
        if exists:
            # Check target path (case-insensitive usually fine for paths, but task requires exact)
            if act_target.strip().lower() == exp_target.strip().lower():
                score += 10
                
                # Check redirect type
                if act_type == exp_type:
                    score += 7
                    feedback_parts.append(f"✓ {req}: Correct ({exp_type})")
                else:
                    feedback_parts.append(f"⚠ {req}: Wrong type (expected {exp_type}, got {act_type})")
            else:
                score += 5 # Partial credit for existence
                feedback_parts.append(f"⚠ {req}: Wrong target (expected {exp_target}, got {act_target})")
        else:
            feedback_parts.append(f"✗ {req}: Not found")

    # 4. Anti-gaming Check (15 points)
    # Did the agent actually create new rewrites?
    delta = current_count - initial_count
    if delta >= 5:
        score += 15
        feedback_parts.append("✓ New rewrites created count verified")
    elif delta > 0:
        score += int(delta * 3)
        feedback_parts.append(f"⚠ Only {delta} new rewrites detected (expected 5)")
    else:
        feedback_parts.append("✗ No new rewrites detected in database")

    # 5. Finalize
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }