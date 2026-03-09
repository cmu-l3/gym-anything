#!/usr/bin/env python3
"""
Verifier for multi_role_access_governance task.

Scoring (100 points total):
  - Technician gov_lead created (Auditor role):       15 pts
  - Technician risk_analyst created (Operator role):  10 pts
  - Technician change_manager created (Operator role): 10 pts
  - Scheduled report 'Group Membership Changes Weekly': 20 pts
  - Audit file exists and modified after task start:  15 pts
  - Audit file mentions 'jsmith' (correct target):    15 pts
  - Audit file mentions 'abrown' (correct target):    15 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_multi_role_access_governance(traj, env_info, task_info):
    """
    Verify that the agent:
    1. Created three governance technicians (gov_lead, risk_analyst, change_manager)
    2. Scheduled a group membership changes report
    3. Wrote a governance audit file naming jsmith and abrown as targets
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
        copy_from_env("C:/Users/Docker/multi_role_access_governance_result.json", temp_path)
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
    # Criterion 1: Technician gov_lead (Auditor role) — 15 pts
    # -----------------------------------------------------------------------
    try:
        gov_lead_exists = result.get("tech_gov_lead_exists", False)
        if isinstance(gov_lead_exists, str):
            gov_lead_exists = gov_lead_exists.lower() == "true"
        gov_lead_role = str(result.get("tech_gov_lead_role", "")).lower()

        if gov_lead_exists:
            pts = 10
            if "auditor" in gov_lead_role:
                pts = 15
            score += pts
            subscores["gov_lead"] = True
            feedback_parts.append(f"Technician gov_lead created (role: {gov_lead_role}) (+{pts})")
        else:
            subscores["gov_lead"] = False
            feedback_parts.append("Technician gov_lead NOT found (0/15)")
    except Exception as e:
        logger.warning(f"gov_lead check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 2: Technician risk_analyst (Operator role) — 10 pts
    # -----------------------------------------------------------------------
    try:
        risk_analyst_exists = result.get("tech_risk_analyst_exists", False)
        if isinstance(risk_analyst_exists, str):
            risk_analyst_exists = risk_analyst_exists.lower() == "true"
        risk_analyst_role = str(result.get("tech_risk_analyst_role", "")).lower()

        if risk_analyst_exists:
            pts = 7
            if "operator" in risk_analyst_role:
                pts = 10
            score += pts
            subscores["risk_analyst"] = True
            feedback_parts.append(f"Technician risk_analyst created (role: {risk_analyst_role}) (+{pts})")
        else:
            subscores["risk_analyst"] = False
            feedback_parts.append("Technician risk_analyst NOT found (0/10)")
    except Exception as e:
        logger.warning(f"risk_analyst check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 3: Technician change_manager (Operator role) — 10 pts
    # -----------------------------------------------------------------------
    try:
        change_manager_exists = result.get("tech_change_manager_exists", False)
        if isinstance(change_manager_exists, str):
            change_manager_exists = change_manager_exists.lower() == "true"
        change_manager_role = str(result.get("tech_change_manager_role", "")).lower()

        if change_manager_exists:
            pts = 7
            if "operator" in change_manager_role:
                pts = 10
            score += pts
            subscores["change_manager"] = True
            feedback_parts.append(f"Technician change_manager created (role: {change_manager_role}) (+{pts})")
        else:
            subscores["change_manager"] = False
            feedback_parts.append("Technician change_manager NOT found (0/10)")
    except Exception as e:
        logger.warning(f"change_manager check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 4: Scheduled report 'Group Membership Changes Weekly' — 20 pts
    # -----------------------------------------------------------------------
    try:
        report_found = result.get("report_found", False)
        if isinstance(report_found, str):
            report_found = report_found.lower() == "true"
        report_name = str(result.get("report_name", "")).lower()

        if report_found or "group" in report_name and ("membership" in report_name or "weekly" in report_name):
            score += 20
            subscores["scheduled_report"] = True
            feedback_parts.append(f"Scheduled report found: '{report_name}' (+20)")
        elif "group" in report_name and report_name not in ("", "none"):
            score += 10
            subscores["scheduled_report"] = "partial"
            feedback_parts.append(f"Group-related report found ('{report_name}') but not specifically membership/weekly (+10)")
        else:
            subscores["scheduled_report"] = False
            feedback_parts.append("Scheduled report 'Group Membership Changes Weekly' NOT found (0/20)")
    except Exception as e:
        logger.warning(f"Report check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 5: Audit file exists and was modified after task start — 15 pts
    # -----------------------------------------------------------------------
    try:
        audit_file_exists = result.get("audit_file_exists", False)
        if isinstance(audit_file_exists, str):
            audit_file_exists = audit_file_exists.lower() == "true"
        modified_after = result.get("audit_file_modified_after_start", False)
        if isinstance(modified_after, str):
            modified_after = modified_after.lower() == "true"
        task_start = int(result.get("task_start", 0))
        file_mod = int(result.get("audit_file_mod_time", 0))

        if audit_file_exists and modified_after and task_start > 0 and file_mod > task_start:
            score += 15
            subscores["file_fresh"] = True
            feedback_parts.append("Governance audit file created after task started (+15)")
        elif audit_file_exists and task_start == 0:
            score += 8
            subscores["file_fresh"] = "partial"
            feedback_parts.append("Governance audit file exists (timestamp unavailable) (+8)")
        elif audit_file_exists:
            score += 5
            subscores["file_fresh"] = "partial"
            feedback_parts.append("Governance audit file exists but may be pre-existing (+5)")
        else:
            subscores["file_fresh"] = False
            feedback_parts.append("Governance audit file not found at Desktop path (0/15)")
    except Exception as e:
        logger.warning(f"File existence check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 6: Audit file mentions jsmith — 15 pts
    # -----------------------------------------------------------------------
    try:
        has_jsmith = result.get("audit_has_jsmith", False)
        if isinstance(has_jsmith, str):
            has_jsmith = has_jsmith.lower() == "true"

        if has_jsmith:
            score += 15
            subscores["identifies_jsmith"] = True
            feedback_parts.append("Audit correctly identifies jsmith as privilege escalation target (+15)")
        else:
            subscores["identifies_jsmith"] = False
            feedback_parts.append("Audit does not mention jsmith (0/15)")
    except Exception as e:
        logger.warning(f"jsmith check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 7: Audit file mentions abrown — 15 pts
    # -----------------------------------------------------------------------
    try:
        has_abrown = result.get("audit_has_abrown", False)
        if isinstance(has_abrown, str):
            has_abrown = has_abrown.lower() == "true"

        if has_abrown:
            score += 15
            subscores["identifies_abrown"] = True
            feedback_parts.append("Audit correctly identifies abrown as privilege escalation target (+15)")
        else:
            subscores["identifies_abrown"] = False
            feedback_parts.append("Audit does not mention abrown (0/15)")
    except Exception as e:
        logger.warning(f"abrown check failed: {e}")

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores,
    }
