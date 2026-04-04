#!/usr/bin/env python3
"""
Verifier for system_branding_config task.

Scoring (100 points total):
- Application Title correct (25 pts) [MANDATORY]
- Application Introduction correct (25 pts)
- Application Notification correct (15 pts)
- Max Analytics Records correct (15 pts)
- Application Footer correct (10 pts)
- Persistence check (10 pts)

Pass threshold: 60 points
Mandatory: Application Title must be correct
"""

import json
import tempfile
import os
import logging
import re

logger = logging.getLogger(__name__)

def normalize_text(text):
    """Normalize text for comparison (trim whitespace, handle encoding issues)."""
    if not text:
        return ""
    # Remove HTML tags if present (intro can be rich text)
    text = re.sub('<[^<]+?>', '', text)
    return " ".join(text.split())

def verify_system_branding_config(traj, env_info, task_info):
    """Verify system branding settings."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/system_branding_result.json", temp_path)
            with open(temp_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not load result file: {e}"}
        finally:
            if os.path.exists(temp_path):
                os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"System error: {e}"}

    # Get Metadata
    metadata = task_info.get('metadata', {})
    target_title = normalize_text(metadata.get('target_title', "Sierra Leone HMIS"))
    target_intro = normalize_text(metadata.get('target_intro', "Welcome to the Sierra Leone Health Information Management System"))
    target_notif = normalize_text(metadata.get('target_notification', "System maintenance is scheduled"))
    target_limit = str(metadata.get('target_analytics_limit', "100000"))
    target_footer = normalize_text(metadata.get('target_footer', "Ministry of Health and Sanitation"))

    # Get Actuals
    settings = result.get('settings', {})
    actual_title = normalize_text(settings.get('applicationTitle', ''))
    actual_intro = normalize_text(settings.get('applicationIntro', ''))
    actual_notif = normalize_text(settings.get('applicationNotification', ''))
    actual_limit = str(settings.get('keyAnalyticsMaxLimit', ''))
    actual_footer = normalize_text(settings.get('applicationFooter', ''))
    
    # Sometimes analytics limit returns as integer in JSON, convert safely
    if actual_limit.endswith('.0'):
        actual_limit = actual_limit[:-2]

    score = 0
    feedback_parts = []
    correct_count = 0

    # 1. Application Title (Mandatory) - Exact Match preferred
    if actual_title == target_title:
        score += 25
        correct_count += 1
        feedback_parts.append(f"Title set correctly (+25)")
    elif target_title.lower() in actual_title.lower():
        # Partial credit if slightly off but contains main words
        score += 15
        correct_count += 1
        feedback_parts.append(f"Title set partially correct (+15)")
    else:
        feedback_parts.append(f"Title incorrect: found '{actual_title}', expected '{target_title}'")
        # Mandatory fail if title is completely wrong
        return {
            "passed": False, 
            "score": score, 
            "feedback": "Application Title (Mandatory) not set correctly. " + " | ".join(feedback_parts)
        }

    # 2. Application Intro - Substring match
    if target_intro in actual_intro:
        score += 25
        correct_count += 1
        feedback_parts.append("Introduction set correctly (+25)")
    elif "Sierra Leone Health Information Management System" in actual_intro:
        score += 15
        correct_count += 1
        feedback_parts.append("Introduction set partially correct (+15)")
    else:
        feedback_parts.append("Introduction incorrect/missing")

    # 3. Notification - Substring match
    if target_notif in actual_notif:
        score += 15
        correct_count += 1
        feedback_parts.append("Notification set correctly (+15)")
    elif "System maintenance" in actual_notif and "GMT" in actual_notif:
        score += 10
        correct_count += 1
        feedback_parts.append("Notification set partially correct (+10)")
    else:
        feedback_parts.append("Notification incorrect/missing")

    # 4. Analytics Limit
    if actual_limit == target_limit:
        score += 15
        correct_count += 1
        feedback_parts.append("Analytics limit set correctly (+15)")
    else:
        feedback_parts.append(f"Analytics limit incorrect: {actual_limit}")

    # 5. Footer
    if target_footer in actual_footer:
        score += 10
        correct_count += 1
        feedback_parts.append("Footer set correctly (+10)")
    elif "Ministry of Health and Sanitation" in actual_footer:
        score += 5
        correct_count += 1
        feedback_parts.append("Footer set partially correct (+5)")
    else:
        feedback_parts.append("Footer incorrect/missing")

    # 6. Persistence/Verification Bonus
    # If at least 2 settings were verified via API, we award the persistence points
    if correct_count >= 2:
        score += 10
        feedback_parts.append("Settings persisted verification (+10)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }