#!/usr/bin/env python3
"""
Verifier for restore_virtual_server task.

Scoring Criteria:
1. Domain Exists (Critical) - 20 pts
2. Created During Task (Anti-Gaming) - 20 pts
3. Features Enabled (Web, DNS, Mail, MySQL) - 10 pts each (40 total)
4. Data Integrity (Marker File & User) - 10 pts each (20 total)

Pass Threshold: 70 points AND Domain Exists AND Created During Task
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_restore_virtual_server(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Domain Exists (Critical)
    domain_exists = result.get("domain_exists", False)
    if domain_exists:
        score += 20
        feedback_parts.append("Domain restored successfully.")
    else:
        feedback_parts.append("Domain 'greenleaf-organics.test' not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Anti-Gaming (Created During Task)
    created_during_task = result.get("created_during_task", False)
    if created_during_task:
        score += 20
        feedback_parts.append("Restoration occurred during task window.")
    else:
        feedback_parts.append("Domain existed before task or timestamp check failed.")
        # If the domain wasn't created during the task, they didn't do the work
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " (Anti-gaming check failed)"}

    # 3. Features
    features = result.get("features", {})
    feature_score = 0
    missing_features = []
    
    if features.get("web"): feature_score += 10
    else: missing_features.append("Web")
    
    if features.get("dns"): feature_score += 10
    else: missing_features.append("DNS")
    
    if features.get("mail"): feature_score += 10
    else: missing_features.append("Mail")
    
    if features.get("mysql"): feature_score += 10
    else: missing_features.append("MySQL")
    
    score += feature_score
    if missing_features:
        feedback_parts.append(f"Missing features: {', '.join(missing_features)}.")
    else:
        feedback_parts.append("All features enabled.")

    # 4. Data Integrity
    marker_restored = result.get("marker_restored", False)
    user_restored = result.get("user_restored", False)
    
    if marker_restored:
        score += 10
        feedback_parts.append("Files restored correctly.")
    else:
        feedback_parts.append("File restoration verification failed.")
        
    if user_restored:
        score += 10
        feedback_parts.append("Users restored correctly.")
    else:
        feedback_parts.append("User 'info' missing.")

    # Final Evaluation
    passed = (score >= 70 and domain_exists and created_during_task)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }