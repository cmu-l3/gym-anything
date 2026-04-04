#!/usr/bin/env python3
"""
Verifier for brute_force_response task.

Scoring (100 points total):
  - Technician incident_handler created (Operator role):   25 pts
  - Notification configured for security-alerts@corp.local: 25 pts
  - Analysis file exists and modified after task start:    20 pts
  - Analysis file mentions 'rwilliams' (correct target):   30 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_brute_force_response(traj, env_info, task_info):
    """
    Verify that the agent:
    1. Created incident_handler technician with Operator role
    2. Configured security-alerts@corp.local notification
    3. Produced an analysis file naming rwilliams as the primary attack target
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    subscores = {}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    temp_path = temp_file.name
    temp_file.close()

    try:
        copy_from_env("C:/Users/Docker/brute_force_response_result.json", temp_path)
        with open(temp_path, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Result JSON malformed: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        try:
            os.unlink(temp_path)
        except Exception:
            pass

    # -----------------------------------------------------------------------
    # Criterion 1: Technician incident_handler created (25 pts)
    # -----------------------------------------------------------------------
    try:
        tech_exists = result.get("tech_incident_handler_exists", False)
        if isinstance(tech_exists, str):
            tech_exists = tech_exists.lower() == "true"
        tech_role = str(result.get("tech_incident_handler_role", "")).lower()

        if tech_exists:
            pts = 18
            if "operator" in tech_role:
                pts = 25
            score += pts
            subscores["tech_created"] = True
            feedback_parts.append(f"Technician incident_handler created (role: {tech_role}) (+{pts})")
        else:
            subscores["tech_created"] = False
            feedback_parts.append("Technician incident_handler NOT found (0/25)")
    except Exception as e:
        logger.warning(f"Technician check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 2: Notification for security-alerts@corp.local (25 pts)
    # -----------------------------------------------------------------------
    try:
        notif_email = str(result.get("notification_email", "")).lower()
        notif_has_target = result.get("notification_has_security_alerts", False)
        if isinstance(notif_has_target, str):
            notif_has_target = notif_has_target.lower() == "true"

        if notif_has_target or "security-alerts" in notif_email or "security.alerts" in notif_email:
            score += 25
            subscores["notification"] = True
            feedback_parts.append("Notification configured for security-alerts@corp.local (+25)")
        elif notif_email and notif_email not in ("", "none"):
            score += 12
            subscores["notification"] = "partial"
            feedback_parts.append(f"Notification configured for '{notif_email}' — expected security-alerts@corp.local (+12)")
        else:
            subscores["notification"] = False
            feedback_parts.append("Notification NOT configured (0/25)")
    except Exception as e:
        logger.warning(f"Notification check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 3: Analysis file exists and is fresh (20 pts)
    # -----------------------------------------------------------------------
    try:
        file_exists = result.get("analysis_file_exists", False)
        if isinstance(file_exists, str):
            file_exists = file_exists.lower() == "true"
        modified_after = result.get("analysis_file_modified_after_start", False)
        if isinstance(modified_after, str):
            modified_after = modified_after.lower() == "true"
        task_start = int(result.get("task_start", 0))
        file_mod = int(result.get("analysis_file_mod_time", 0))

        if file_exists and modified_after and task_start > 0 and file_mod > task_start:
            score += 20
            subscores["file_fresh"] = True
            feedback_parts.append("Analysis file created after task started (+20)")
        elif file_exists and task_start == 0:
            score += 10
            subscores["file_fresh"] = "partial"
            feedback_parts.append("Analysis file exists (timestamp unavailable) (+10)")
        elif file_exists:
            score += 8
            subscores["file_fresh"] = "partial"
            feedback_parts.append("Analysis file exists but may be pre-existing (+8)")
        else:
            subscores["file_fresh"] = False
            feedback_parts.append("Analysis file not found at Desktop path (0/20)")
    except Exception as e:
        logger.warning(f"File existence check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 4: Analysis file mentions rwilliams (correct primary target) (30 pts)
    # -----------------------------------------------------------------------
    try:
        has_rwilliams = result.get("analysis_has_rwilliams", False)
        if isinstance(has_rwilliams, str):
            has_rwilliams = has_rwilliams.lower() == "true"
        content_len = int(result.get("analysis_file_content_length", 0))
        has_bf_language = result.get("analysis_has_brute_force_language", False)
        if isinstance(has_bf_language, str):
            has_bf_language = has_bf_language.lower() == "true"

        if has_rwilliams and content_len >= 100:
            score += 30
            subscores["correct_target"] = True
            feedback_parts.append("Analysis correctly identifies rwilliams as attack target (+30)")
        elif has_rwilliams:
            score += 20
            subscores["correct_target"] = "partial"
            feedback_parts.append("Analysis mentions rwilliams but file is thin (+20)")
        elif file_exists and has_bf_language and content_len >= 200:
            score += 10
            subscores["correct_target"] = "partial"
            feedback_parts.append("Analysis discusses brute force but wrong/missing target account (+10)")
        else:
            subscores["correct_target"] = False
            feedback_parts.append("Analysis does not identify rwilliams as primary target (0/30)")
    except Exception as e:
        logger.warning(f"Content check failed: {e}")

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores,
    }
