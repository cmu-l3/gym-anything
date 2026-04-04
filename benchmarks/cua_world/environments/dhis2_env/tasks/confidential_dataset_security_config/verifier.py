#!/usr/bin/env python3
"""
Verifier for confidential_dataset_security_config task.

Scoring (100 points total):
- User Group Created (15 pts)
- Data Set Created (15 pts)
- Data Set Period Correct (10 pts)
- Public Access Revoked (30 pts) [CRITICAL]
- Group Added to Sharing (15 pts)
- Group Permissions Correct (15 pts)

Pass threshold: 65 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_confidential_dataset_security_config(traj, env_info, task_info):
    """Verify security configuration for the mental health dataset."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/security_config_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        try:
            with open(temp_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}
        finally:
            os.unlink(temp_path)

        score = 0
        feedback_parts = []
        
        if result.get("error"):
            return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

        # 1. User Group Created (15 pts)
        if result.get("user_group_found"):
            score += 15
            feedback_parts.append("User Group created (+15)")
        else:
            feedback_parts.append("User Group 'Mental Health Specialists' not found")

        # 2. Data Set Created (15 pts)
        if result.get("data_set_found"):
            score += 15
            feedback_parts.append("Data Set created (+15)")
            
            # 3. Period Type (10 pts)
            period = result.get("data_set_period", "").lower()
            if period == "monthly":
                score += 10
                feedback_parts.append("Period type correct (+10)")
            else:
                feedback_parts.append(f"Incorrect period type: {result.get('data_set_period')}")
                
            # 4. Public Access Revoked (30 pts)
            public_access = result.get("data_set_public_access", "")
            # Expected "--------" (8 dashes)
            if public_access == "--------":
                score += 30
                feedback_parts.append("Public access successfully revoked (+30)")
            else:
                feedback_parts.append(f"Public access NOT revoked (Found: {public_access})")
                
            # 5. Group Added to Sharing (15 pts)
            if result.get("target_group_id_in_acl"):
                score += 15
                feedback_parts.append("Specialist group added to permissions (+15)")
                
                # 6. Group Permissions Correct (15 pts)
                # Expect r-rw---- or similar pattern where Data is rw and Metadata is r/rw
                # Standard pattern string in API: "r-rw----" (Metadata: r-, Data: rw, Other: ----)
                access = result.get("group_access_pattern", "")
                
                # Check for Data Capture (rw) and Metadata View (r or rw)
                # First two chars: Metadata. Next two: Data.
                # r-rw.... OK
                # rwrw.... OK
                if len(access) >= 4 and access[2:4] == "rw":
                    score += 15
                    feedback_parts.append("Group permissions correct (Data Capture) (+15)")
                else:
                    feedback_parts.append(f"Incorrect group permissions: {access}")
            else:
                feedback_parts.append("Specialist group NOT added to data set permissions")
                
        else:
            feedback_parts.append("Data Set 'Adolescent Mental Health Surveillance' not found")

        passed = score >= 65 and result.get("data_set_public_access") == "--------"

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verifier exception: {str(e)}"}