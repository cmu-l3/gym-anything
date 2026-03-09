#!/usr/bin/env python3
"""
Verifier for handle_incoming_share_intents task.
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _read_json_from_env(copy_from_env, container_path: str) -> dict:
    """Copy a JSON file out of the container and return parsed dict."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(container_path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception as exc:
        logger.debug("Could not read JSON %s: %s", container_path, exc)
        return {}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

def verify_handle_incoming_share_intents(traj, env_info, task_info):
    """
    Verify the Android app is configured to handle share intents.
    
    Scoring Criteria (100 pts total):
    1. Build Success (30 pts): The project must compile.
    2. Manifest Configuration (40 pts):
       - ACTION_SEND present (15 pts)
       - mimeType 'text/plain' present (15 pts)
       - CATEGORY_DEFAULT present (10 pts)
    3. Activity Logic (30 pts):
       - References Intent.EXTRA_TEXT (15 pts)
       - Sets text to input field (15 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: copy_from_env not available"}

    # Read result from export script
    result = _read_json_from_env(copy_from_env, "/tmp/task_result.json")
    if not result:
        return {"passed": False, "score": 0, "feedback": "Verification failed: No result file generated"}

    score = 0
    feedback_parts = []
    
    # 1. Build Verification
    build_success = result.get("build_success", False)
    if build_success:
        score += 30
        feedback_parts.append("Build Success: PASS (30/30)")
    else:
        feedback_parts.append("Build Success: FAIL (0/30) - Project did not compile")

    # 2. Manifest Verification
    manifest_content = result.get("manifest_content", "")
    manifest_score = 0
    
    # Check for ACTION_SEND
    if 'android.intent.action.SEND' in manifest_content:
        manifest_score += 15
        feedback_parts.append("Manifest Action: PASS")
    else:
        feedback_parts.append("Manifest Action: FAIL - Missing android.intent.action.SEND")

    # Check for mimeType text/plain
    # Regex to handle variations in quotes or spacing
    if re.search(r'mimeType\s*=\s*["\']text/plain["\']', manifest_content):
        manifest_score += 15
        feedback_parts.append("Manifest MimeType: PASS")
    else:
        feedback_parts.append("Manifest MimeType: FAIL - Missing mimeType='text/plain'")

    # Check for CATEGORY_DEFAULT
    # Strictly speaking, for implicit intents targeting an Activity, DEFAULT is usually required 
    # to receive them via startActivity() unless the launcher sends it explicitly.
    if 'android.intent.category.DEFAULT' in manifest_content:
        manifest_score += 10
        feedback_parts.append("Manifest Category: PASS")
    else:
        feedback_parts.append("Manifest Category: FAIL - Missing android.intent.category.DEFAULT")
        
    score += manifest_score
    
    # 3. Activity Logic Verification
    activity_content = result.get("activity_content", "")
    code_score = 0
    
    # Check for extracting EXTRA_TEXT
    # Matches Intent.EXTRA_TEXT or "android.intent.extra.TEXT"
    if 'EXTRA_TEXT' in activity_content or 'android.intent.extra.TEXT' in activity_content:
        code_score += 15
        feedback_parts.append("Code Extraction: PASS")
    else:
        feedback_parts.append("Code Extraction: FAIL - logic to read Intent.EXTRA_TEXT not found")
        
    # Check for setting text to the UI
    # Looking for .setText( or .text = 
    if re.search(r'\.setText\(', activity_content) or re.search(r'\.text\s*=', activity_content):
        code_score += 15
        feedback_parts.append("UI Update: PASS")
    else:
        feedback_parts.append("UI Update: FAIL - logic to set text to EditText not found")
        
    score += code_score

    # Final Pass Determination
    # Threshold: 75 points. 
    # Must at least build (30) + have correct manifest (40) + extract text (15) = 85 ideally.
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }