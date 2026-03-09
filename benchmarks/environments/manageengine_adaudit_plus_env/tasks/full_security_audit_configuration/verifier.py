#!/usr/bin/env python3
"""
Verifier for full_security_audit_configuration task.

Scoring (100 points total):
  - Technician security_ops created (Operator role):   20 pts
  - Email notification configured:                     15 pts
  - Scheduled 'Security Summary' daily report:         20 pts
  - Assessment file exists and modified after start:   10 pts
  - Assessment mentions 'bruteforce1' (primary threat): 20 pts
  - Assessment is substantial (>=300 chars):            15 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_full_security_audit_configuration(traj, env_info, task_info):
    """
    Verify that the agent:
    1. Created security_ops technician with Operator role
    2. Configured an email notification (threshold-based alerting)
    3. Scheduled a daily 'Security Summary' report
    4. Wrote a threat assessment naming bruteforce1 as primary threat
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
        copy_from_env("C:/Users/Docker/full_security_audit_configuration_result.json", temp_path)
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
    # Criterion 1: Technician security_ops with Operator role — 20 pts
    # -----------------------------------------------------------------------
    try:
        tech_exists = result.get("tech_security_ops_exists", False)
        if isinstance(tech_exists, str):
            tech_exists = tech_exists.lower() == "true"
        tech_role = str(result.get("tech_security_ops_role", "")).lower()

        if tech_exists:
            pts = 14
            if "operator" in tech_role:
                pts = 20
            score += pts
            subscores["tech_security_ops"] = True
            feedback_parts.append(f"Technician security_ops created (role: {tech_role}) (+{pts})")
        else:
            subscores["tech_security_ops"] = False
            feedback_parts.append("Technician security_ops NOT found (0/20)")
    except Exception as e:
        logger.warning(f"Technician check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 2: Email notification configured — 15 pts
    # -----------------------------------------------------------------------
    try:
        notif_configured = result.get("notification_configured", False)
        if isinstance(notif_configured, str):
            notif_configured = notif_configured.lower() == "true"
        notif_email = str(result.get("notification_email", "")).lower().strip()
        notif_has_threshold = result.get("notification_has_threshold", False)
        if isinstance(notif_has_threshold, str):
            notif_has_threshold = notif_has_threshold.lower() == "true"

        if notif_configured and notif_email and notif_email not in ("", "none"):
            pts = 10
            if notif_has_threshold:
                pts = 15
            score += pts
            subscores["notification"] = True
            feedback_parts.append(f"Notification configured (email: {notif_email}) (+{pts})")
        elif notif_configured or (notif_email and notif_email not in ("", "none")):
            score += 8
            subscores["notification"] = "partial"
            feedback_parts.append(f"Notification partially configured (+8)")
        else:
            subscores["notification"] = False
            feedback_parts.append("Email notification NOT configured (0/15)")
    except Exception as e:
        logger.warning(f"Notification check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 3: Scheduled 'Security Summary' daily report — 20 pts
    # -----------------------------------------------------------------------
    try:
        sec_report_found = result.get("security_report_found", False)
        if isinstance(sec_report_found, str):
            sec_report_found = sec_report_found.lower() == "true"
        report_name = str(result.get("security_report_name", "")).lower()

        if sec_report_found or ("security" in report_name and ("summary" in report_name or "daily" in report_name)):
            score += 20
            subscores["security_report"] = True
            feedback_parts.append(f"Scheduled Security Summary report found: '{report_name}' (+20)")
        elif "security" in report_name and report_name not in ("", "none"):
            score += 10
            subscores["security_report"] = "partial"
            feedback_parts.append(f"Security-related report found ('{report_name}') but missing summary/daily (+10)")
        else:
            subscores["security_report"] = False
            feedback_parts.append("Scheduled 'Security Summary' report NOT found (0/20)")
    except Exception as e:
        logger.warning(f"Report check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 4: Assessment file exists and modified after task start — 10 pts
    # -----------------------------------------------------------------------
    try:
        assessment_exists = result.get("assessment_file_exists", False)
        if isinstance(assessment_exists, str):
            assessment_exists = assessment_exists.lower() == "true"
        modified_after = result.get("assessment_file_modified_after_start", False)
        if isinstance(modified_after, str):
            modified_after = modified_after.lower() == "true"
        task_start = int(result.get("task_start", 0))
        file_mod = int(result.get("assessment_file_mod_time", 0))

        if assessment_exists and modified_after and task_start > 0 and file_mod > task_start:
            score += 10
            subscores["file_fresh"] = True
            feedback_parts.append("Threat assessment file created after task started (+10)")
        elif assessment_exists and task_start == 0:
            score += 5
            subscores["file_fresh"] = "partial"
            feedback_parts.append("Threat assessment file exists (timestamp unavailable) (+5)")
        elif assessment_exists:
            score += 4
            subscores["file_fresh"] = "partial"
            feedback_parts.append("Threat assessment file exists but may be pre-existing (+4)")
        else:
            subscores["file_fresh"] = False
            feedback_parts.append("Threat assessment file NOT found at Desktop path (0/10)")
    except Exception as e:
        logger.warning(f"File existence check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 5: Assessment mentions bruteforce1 (primary threat) — 20 pts
    # -----------------------------------------------------------------------
    try:
        has_bruteforce1 = result.get("assessment_has_bruteforce1", False)
        if isinstance(has_bruteforce1, str):
            has_bruteforce1 = has_bruteforce1.lower() == "true"
        has_testattacker = result.get("assessment_has_testattacker", False)
        if isinstance(has_testattacker, str):
            has_testattacker = has_testattacker.lower() == "true"
        has_threat_language = result.get("assessment_has_threat_language", False)
        if isinstance(has_threat_language, str):
            has_threat_language = has_threat_language.lower() == "true"

        if has_bruteforce1:
            pts = 15
            if has_testattacker:
                pts = 20
            score += pts
            subscores["threat_identification"] = True
            feedback_parts.append(f"Assessment correctly identifies bruteforce1 as primary threat (+{pts})")
        elif assessment_exists and has_threat_language:
            score += 8
            subscores["threat_identification"] = "partial"
            feedback_parts.append("Assessment discusses threats but misses bruteforce1 as primary account (+8)")
        else:
            subscores["threat_identification"] = False
            feedback_parts.append("Assessment does not identify bruteforce1 as primary threat (0/20)")
    except Exception as e:
        logger.warning(f"Content check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 6: Assessment is substantial (>=300 chars) — 15 pts
    # -----------------------------------------------------------------------
    try:
        content_len = int(result.get("assessment_content_length", 0))
        file_size = int(result.get("assessment_file_size", 0))
        effective_size = max(content_len, file_size)

        if effective_size >= 600:
            score += 15
            subscores["report_substantial"] = True
            feedback_parts.append(f"Threat assessment is comprehensive ({effective_size} chars/bytes) (+15)")
        elif effective_size >= 300:
            score += 10
            subscores["report_substantial"] = "partial"
            feedback_parts.append(f"Threat assessment is adequate ({effective_size} chars/bytes) (+10)")
        elif effective_size >= 100:
            score += 5
            subscores["report_substantial"] = "partial"
            feedback_parts.append(f"Threat assessment is thin ({effective_size} chars/bytes) (+5)")
        else:
            subscores["report_substantial"] = False
            feedback_parts.append(f"Threat assessment too short or missing ({effective_size} chars) (0/15)")
    except Exception as e:
        logger.warning(f"Size check failed: {e}")

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores,
    }
