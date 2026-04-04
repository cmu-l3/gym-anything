#!/usr/bin/env python3
"""
Verifier for Secure Project Forking Task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_secure_project_forking(traj, env_info, task_info):
    """
    Verifies that the agent created a master volume, cloned it, and re-keyed the clone.
    
    Scoring Criteria:
    1. Master Volume (Alpha) Created & Functional (20 pts)
       - Exists, mounts with Pass+Keyfile, contains data.
    2. Fork (Beta) Volume Exists (10 pts)
    3. Fork Re-keyed Successfully (20 pts)
       - Mounts with New Pass + NO Keyfile.
    4. Header Algorithm Upgraded (20 pts)
       - Beta volume uses Whirlpool.
    5. Cloning Method Verification (30 pts)
       - Filesystem UUIDs match (proof of block-level copy vs file copy).
    """
    
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # 1. Master Volume Check (20 pts)
    if result.get("alpha_mounts_correctly") and result.get("alpha_has_data"):
        score += 20
        feedback_parts.append("✅ Master volume created and functional")
    elif result.get("alpha_exists"):
        score += 10
        feedback_parts.append("⚠️ Master volume exists but mount/data check failed")
    else:
        feedback_parts.append("❌ Master volume missing")
        
    # 2. Fork Volume Existence (10 pts)
    if result.get("beta_exists"):
        score += 10
        feedback_parts.append("✅ Clone volume exists")
    else:
        feedback_parts.append("❌ Clone volume missing")
        
    # 3. Fork Re-keying (20 pts)
    if result.get("beta_mounts_new_creds"):
        if result.get("beta_rejects_old_creds"):
            score += 20
            feedback_parts.append("✅ Clone volume re-keyed successfully (Old creds rejected)")
        else:
            score += 10
            feedback_parts.append("⚠️ Clone mounts with new creds, but old creds might still work (check failed)")
    else:
        feedback_parts.append("❌ Clone volume does not mount with new credentials")
        
    # 4. Header Algorithm (20 pts)
    algo = result.get("beta_hash_algo", "").lower()
    if "whirlpool" in algo:
        score += 20
        feedback_parts.append("✅ Header algorithm upgraded to Whirlpool")
    else:
        feedback_parts.append(f"❌ Header algorithm incorrect: found '{algo}'")
        
    # 5. Cloning Method (UUID Match) (30 pts)
    if result.get("uuids_match"):
        score += 30
        feedback_parts.append("✅ Filesystem UUIDs match (valid clone)")
    elif result.get("alpha_uuid") and result.get("beta_uuid"):
        feedback_parts.append(f"❌ UUID mismatch (Alpha: {result['alpha_uuid']} vs Beta: {result['beta_uuid']}). Did you create a new volume instead of copying?")
    else:
        feedback_parts.append("❌ Could not verify cloning method (UUIDs not available)")

    # Final Check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }