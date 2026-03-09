#!/usr/bin/env python3
"""
Verifier for configure_email_autoresponder task.

Scoring Criteria:
1. Autoresponder Enabled (20 pts)
2. Autoreply File Exists/Created (10 pts)
3. Content Checks (Dates, Contact, Signature, Core Text) (60 pts)
4. Configuration Saved/Persisted (10 pts)
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_email_autoresponder(traj, env_info, task_info):
    """
    Verify that the email autoresponder was configured correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # ================================================================
    # Copy result file from container
    # ================================================================
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

    # ================================================================
    # CRITERION 1: Autoresponder Enabled (20 pts)
    # ================================================================
    enabled = result.get('autoresponder_enabled', False)
    file_path = result.get('autoreply_file_path', '')
    
    # If file exists, we consider it enabled even if CLI flag is ambiguous
    if enabled or (file_path and os.path.basename(file_path)):
        score += 20
        feedback_parts.append("Autoresponder enabled")
        is_active = True
    else:
        feedback_parts.append("Autoresponder NOT enabled")
        is_active = False

    # ================================================================
    # CRITERION 2: Autoreply File Exists (10 pts)
    # ================================================================
    if file_path:
        score += 10
        feedback_parts.append("Autoreply file exists")
    else:
        feedback_parts.append("Autoreply file not found")

    # ================================================================
    # CRITERION 3: Content Checks (60 pts)
    # ================================================================
    content = result.get('autoreply_content', '')
    content_lower = content.lower()
    
    # 3a. Dates (15 pts)
    has_start = "january 13" in content_lower
    has_end = "january 24" in content_lower and "2025" in content_lower
    if has_start and has_end:
        score += 15
        feedback_parts.append("Dates correct")
    elif has_start or has_end:
        score += 7
        feedback_parts.append("Dates partially correct")
    else:
        feedback_parts.append("Dates missing")

    # 3b. Alternate Contact (15 pts)
    has_david_email = "david@acmecorp.test" in content_lower
    has_david_name = "david park" in content_lower
    if has_david_email and has_david_name:
        score += 15
        feedback_parts.append("Alternate contact correct")
    elif has_david_email:
        score += 10
        feedback_parts.append("Alternate email found (name missing)")
    else:
        feedback_parts.append("Alternate contact missing")

    # 3c. Signature (10 pts)
    has_sig_name = "sarah chen" in content_lower
    has_sig_title = "marketing manager" in content_lower
    if has_sig_name and has_sig_title:
        score += 10
        feedback_parts.append("Signature correct")
    elif has_sig_name:
        score += 5
        feedback_parts.append("Signature partial")
    else:
        feedback_parts.append("Signature missing")

    # 3d. Core Text (20 pts)
    has_vacation = "vacation" in content_lower
    has_ooo = "out of the office" in content_lower or "out of office" in content_lower
    if has_vacation and has_ooo:
        score += 20
        feedback_parts.append("Message body correct")
    elif has_vacation or has_ooo:
        score += 10
        feedback_parts.append("Message body partial")
    else:
        feedback_parts.append("Message body missing core phrases")

    # ================================================================
    # CRITERION 4: Configuration Saved / Anti-Gaming (10 pts)
    # ================================================================
    # Check if file was created during task
    created_during = result.get('file_created_during_task', False)
    
    # If autoresponder is active AND (file created during task OR we verified enabled status)
    # We give points for saving if the feature is demonstrably active
    if is_active and (created_during or enabled):
        score += 10
        feedback_parts.append("Configuration saved")
    else:
        feedback_parts.append("Configuration not saved or predates task")

    # ================================================================
    # Final Scoring
    # ================================================================
    passed = score >= 60 and is_active
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "content_found": content[:100] + "..." if len(content) > 100 else content,
            "is_active": is_active
        }
    }