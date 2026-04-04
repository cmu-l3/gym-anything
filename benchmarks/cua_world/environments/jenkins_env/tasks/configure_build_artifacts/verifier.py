#!/usr/bin/env python3
"""
Verifier for Jenkins Configure Build Artifacts task.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_build_artifacts(traj, env_info, task_info):
    """
    Verify configuration of build retention and artifact archiving.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_days = metadata.get('expected_days_to_keep', '14')
    expected_num = metadata.get('expected_num_to_keep', '5')
    
    # We expect these substrings in the artifact pattern
    required_artifacts = ["reports/*.xml", "reports/*.html"]

    try:
        # Load result
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        max_score = 100
        feedback_parts = []
        
        # 1. Job Existence (10 pts)
        if result.get('job_exists'):
            score += 10
            feedback_parts.append("Job exists")
        else:
            return {"passed": False, "score": 0, "feedback": "Job 'Integration-Tests' not found"}

        # 2. Config Changed (Anti-gaming) (10 pts)
        if result.get('config_changed'):
            score += 10
            feedback_parts.append("Configuration modified")
        else:
            feedback_parts.append("No configuration changes detected")

        # 3. Log Rotation (30 pts)
        # Check Days
        actual_days = result.get('log_rotator', {}).get('days_to_keep', '')
        if str(actual_days).strip() == str(expected_days):
            score += 15
            feedback_parts.append(f"Days to keep correct ({expected_days})")
        else:
            feedback_parts.append(f"Days to keep incorrect (Expected {expected_days}, got '{actual_days}')")

        # Check Num
        actual_num = result.get('log_rotator', {}).get('num_to_keep', '')
        if str(actual_num).strip() == str(expected_num):
            score += 15
            feedback_parts.append(f"Max builds to keep correct ({expected_num})")
        else:
            feedback_parts.append(f"Max builds incorrect (Expected {expected_num}, got '{actual_num}')")

        # 4. Artifact Archiver (50 pts)
        actual_artifacts = result.get('artifact_archiver', {}).get('artifacts', '')
        if actual_artifacts:
            # Check for coverage of required patterns
            # Flexible check: "reports/*.xml, reports/*.html" vs "reports/*.html, reports/*.xml"
            # Normalize strings for comparison
            actual_norm = str(actual_artifacts).lower().replace(" ", "")
            
            # Points for simply having the archiver active
            score += 10
            
            # Points for specific patterns
            found_all = True
            for req in required_artifacts:
                req_norm = req.lower().replace(" ", "")
                if req_norm in actual_norm:
                    score += 20  # 20 pts per pattern (2 patterns = 40 pts)
                    feedback_parts.append(f"Found artifact pattern: {req}")
                else:
                    found_all = False
                    feedback_parts.append(f"Missing artifact pattern: {req}")
        else:
            feedback_parts.append("No Artifact Archiver configured")

        passed = score >= 70 and result.get('config_changed')
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}