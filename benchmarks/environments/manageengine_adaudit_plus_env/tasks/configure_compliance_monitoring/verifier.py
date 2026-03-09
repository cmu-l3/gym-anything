#!/usr/bin/env python3
"""
Verifier for configure_compliance_monitoring task.

Scoring (100 points total):
  - Technician gdpr_auditor created (Auditor role): 20 pts
  - SMTP server configured (smtp.internal.corp):    20 pts
  - Scheduled report 'User Account Changes - Daily' exists: 20 pts
  - Scheduled report 'Privileged Access Weekly' exists:     20 pts
  - Notification configured for noc@internal.corp:          20 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_configure_compliance_monitoring(traj, env_info, task_info):
    """
    Verify that the agent configured ADAudit Plus with SMTP, compliance technician,
    two scheduled reports, and notification settings.
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
        copy_from_env("C:/Users/Docker/configure_compliance_monitoring_result.json", temp_path)
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

    metadata = task_info.get("metadata", {})
    expected_smtp = metadata.get("smtp_server", "smtp.internal.corp").lower()
    expected_report1 = metadata.get("report1_name", "user account changes").lower()
    expected_report2 = metadata.get("report2_name", "privileged access").lower()
    expected_notif = metadata.get("notification_email", "noc@internal.corp").lower()
    expected_tech = metadata.get("tech_username", "gdpr_auditor").lower()

    # -----------------------------------------------------------------------
    # Criterion 1: Technician gdpr_auditor with Auditor role (20 pts)
    # -----------------------------------------------------------------------
    try:
        tech_exists = result.get("tech_gdpr_auditor_exists", False)
        if isinstance(tech_exists, str):
            tech_exists = tech_exists.lower() == "true"
        tech_role = str(result.get("tech_gdpr_auditor_role", "")).lower()

        if tech_exists:
            pts = 15
            if "auditor" in tech_role:
                pts = 20
            score += pts
            subscores["tech_gdpr_auditor"] = True
            feedback_parts.append(f"Technician gdpr_auditor created (role: {tech_role}) (+{pts})")
        else:
            subscores["tech_gdpr_auditor"] = False
            feedback_parts.append("Technician gdpr_auditor NOT found (0/20)")
    except Exception as e:
        logger.warning(f"Technician check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 2: SMTP server configured (20 pts)
    # -----------------------------------------------------------------------
    try:
        smtp_server = str(result.get("smtp_server", "")).lower().strip()
        smtp_matches = result.get("smtp_matches_expected", False)
        if isinstance(smtp_matches, str):
            smtp_matches = smtp_matches.lower() == "true"

        # Award full points for exact match, partial for any SMTP configured
        if smtp_server and expected_smtp in smtp_server:
            score += 20
            subscores["smtp_configured"] = True
            feedback_parts.append(f"SMTP server correctly set to '{smtp_server}' (+20)")
        elif smtp_server and smtp_server not in ("", "none"):
            score += 10
            subscores["smtp_configured"] = "partial"
            feedback_parts.append(f"SMTP server configured ('{smtp_server}') but expected '{expected_smtp}' (+10)")
        else:
            subscores["smtp_configured"] = False
            feedback_parts.append("SMTP server not configured (0/20)")
    except Exception as e:
        logger.warning(f"SMTP check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 3: Scheduled report 'User Account Changes - Daily' (20 pts)
    # -----------------------------------------------------------------------
    try:
        report1_found = result.get("report1_found", False)
        if isinstance(report1_found, str):
            report1_found = report1_found.lower() == "true"
        report1_name = str(result.get("report1_name", "")).lower()

        if report1_found or ("user account" in report1_name or "account change" in report1_name):
            score += 20
            subscores["report1"] = True
            feedback_parts.append(f"Report 1 'User Account Changes - Daily' found (+20)")
        else:
            subscores["report1"] = False
            feedback_parts.append("Report 'User Account Changes - Daily' not found (0/20)")
    except Exception as e:
        logger.warning(f"Report1 check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 4: Scheduled report 'Privileged Access Weekly' (20 pts)
    # -----------------------------------------------------------------------
    try:
        report2_found = result.get("report2_found", False)
        if isinstance(report2_found, str):
            report2_found = report2_found.lower() == "true"
        report2_name = str(result.get("report2_name", "")).lower()

        if report2_found or ("privileged access" in report2_name or "privileged" in report2_name):
            score += 20
            subscores["report2"] = True
            feedback_parts.append(f"Report 2 'Privileged Access Weekly' found (+20)")
        else:
            subscores["report2"] = False
            feedback_parts.append("Report 'Privileged Access Weekly' not found (0/20)")
    except Exception as e:
        logger.warning(f"Report2 check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 5: Notification configured for noc@internal.corp (20 pts)
    # -----------------------------------------------------------------------
    try:
        notif_email = str(result.get("notification_email", "")).lower()
        notif_has_noc = result.get("notification_has_noc", False)
        if isinstance(notif_has_noc, str):
            notif_has_noc = notif_has_noc.lower() == "true"

        if notif_has_noc or expected_notif in notif_email or "noc" in notif_email:
            score += 20
            subscores["notification"] = True
            feedback_parts.append(f"Notification configured for noc@internal.corp (+20)")
        elif notif_email and notif_email not in ("", "none"):
            score += 10
            subscores["notification"] = "partial"
            feedback_parts.append(f"Notification configured for '{notif_email}' but expected noc@internal.corp (+10)")
        else:
            subscores["notification"] = False
            feedback_parts.append("Notification not configured (0/20)")
    except Exception as e:
        logger.warning(f"Notification check failed: {e}")

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores,
    }
