#!/usr/bin/env python3
"""
Verifier for scrub_image_secret_squash task.

Checks:
1. Image 'legacy-app:safe' exists (10 pts)
2. Secret string is NOT present in image history (40 pts)
   - Verified by grepping 'docker save' output
3. Metadata restored (ENV, CMD, Ports) (20 pts)
4. Application runs and serves correct content (30 pts)

Anti-gaming:
- The secret check inspects the full binary layer history, not just the current filesystem.
- The functional check ensures the agent didn't just delete the secret AND the code.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_scrub_image_secret_squash(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Read result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to read result: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # 1. Image Exists (10 pts)
    if result.get("safe_image_exists", False):
        score += 10
        feedback_parts.append("Image 'legacy-app:safe' created")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Image 'legacy-app:safe' not found. Task failed."
        }
        
    # 2. Secret Scrubbed (40 pts)
    if not result.get("secret_found_in_history", True):
        score += 40
        feedback_parts.append("Secret successfully removed from history")
    else:
        feedback_parts.append("FAIL: Secret string still found in image layers! Did you squash/flatten the image?")
        
    # 3. Metadata Correct (20 pts)
    if result.get("metadata_correct", False):
        score += 20
        feedback_parts.append("Metadata (ENV/CMD) restored correctly")
    else:
        feedback_parts.append("FAIL: Metadata missing or incorrect (check ENV APP_COLOR, CMD, and ExposedPorts)")
        
    # 4. App Functional (30 pts)
    if result.get("app_functional", False):
        score += 30
        feedback_parts.append("App functional")
    else:
        resp = result.get("app_response", "No response")
        feedback_parts.append(f"FAIL: App verification failed. Response: {resp}")

    # Final Score
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }