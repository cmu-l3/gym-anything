#!/usr/bin/env python3
"""
Verifier for clone_virtual_server task.

Evaluates if the agent successfully cloned a virtual server with:
1. Correct domain name
2. All required features (Web, DNS, Mail, MySQL)
3. Content actually copied (files + DB)
4. Correct password set
"""

import json
import os
import tempfile
import logging
import sys
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_clone_virtual_server(traj, env_info, task_info):
    """
    Verify the cloning of a virtual server.
    """
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
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

    # 2. Scoring Logic
    score = 0
    max_score = 100
    feedback = []

    # Criterion 1: Domain Exists (20 pts)
    if result.get('domain_exists', False):
        score += 20
        feedback.append("Target domain exists (+20)")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target domain 'acmecorp-staging.test' was not created."
        }

    # Criterion 2: Features Enabled (30 pts total)
    features = result.get('features', {})
    feature_points = 0
    missing_features = []
    
    if features.get('web'): feature_points += 10
    else: missing_features.append('Web')
    
    if features.get('mysql'): feature_points += 10
    else: missing_features.append('MySQL')
    
    if features.get('dns'): feature_points += 5
    else: missing_features.append('DNS')
    
    if features.get('mail'): feature_points += 5
    else: missing_features.append('Mail')

    score += feature_points
    if missing_features:
        feedback.append(f"Missing features: {', '.join(missing_features)}")
    else:
        feedback.append(f"All features enabled (+{feature_points})")

    # Criterion 3: Content Verification (20 pts)
    # Did the agent actually CLONE, or just create a new empty domain?
    content = result.get('content_verification', {})
    db = result.get('database_verification', {})
    
    cloned_correctly = False
    
    # Check for marker file or file count match
    source_count = content.get('source_file_count', 0)
    target_count = content.get('file_count', 0)
    marker_found = content.get('marker_found', False)
    
    if marker_found:
        score += 15
        cloned_correctly = True
        feedback.append("Web content cloned successfully (marker found) (+15)")
    elif source_count > 0 and target_count >= (source_count * 0.9):
        score += 15
        cloned_correctly = True
        feedback.append(f"Web content cloned successfully ({target_count} files) (+15)")
    else:
        feedback.append("Web content missing or empty (did you use Clone?)")

    # Database existence check
    if db.get('db_exists'):
        score += 5
        feedback.append("Database created (+5)")
    else:
        feedback.append("Database missing")

    # Criterion 4: Password Verification (10 pts)
    if result.get('security_verification', {}).get('password_valid'):
        score += 10
        feedback.append("Admin password is correct (+10)")
    else:
        feedback.append("Admin password incorrect or user not created")

    # Criterion 5: Anti-gaming Timestamp (5 pts)
    if content.get('created_during_task'):
        score += 5
        feedback.append("Domain created during task window (+5)")
    else:
        feedback.append("Domain timestamp pre-dates task (reused environment?)")

    # Criterion 6: VLM Verification (15 pts)
    # Check if we can see the "Cloning virtual server" progress output or relevant UI
    vlm_score = 0
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        Review these screenshots of a Virtualmin server management task.
        I am looking for evidence that the user performed a 'Clone Virtual Server' operation.
        
        Look for:
        1. A form titled "Clone Virtual Server"
        2. Progress output showing "Cloning..." or "Copying..."
        3. A success message "Virtual server ... created successfully" or "Clone complete"
        
        Return JSON: {"evidence_found": true/false, "confidence": "high/med/low"}
        """
        
        try:
            vlm_res = query_vlm(frames, vlm_prompt)
            if vlm_res.get('parsed', {}).get('evidence_found', False):
                vlm_score = 15
                feedback.append("VLM confirmed cloning workflow (+15)")
            else:
                # Fallback: if we verified content via files, we can give partial VLM credit
                # assuming the agent did the work but screenshots missed the specific loading bar
                if cloned_correctly:
                    vlm_score = 10 
                    feedback.append("VLM inconclusive, but file verification passed (+10)")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            if cloned_correctly: vlm_score = 10
            
    score += vlm_score

    # Final result calculation
    # Pass requirement: Domain exists + Features OK + Content Copied (Clone used)
    # Min score ~65-70
    passed = (
        result.get('domain_exists', False) and 
        cloned_correctly and 
        score >= 70
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }