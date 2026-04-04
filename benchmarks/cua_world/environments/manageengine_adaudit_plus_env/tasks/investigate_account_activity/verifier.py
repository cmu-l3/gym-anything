#!/usr/bin/env python3
"""
Verifier for investigate_account_activity task.

Scoring (100 points total):
  - Technician soc_analyst1 created (Operator role): 30 pts
  - Report file exists at Desktop:                   15 pts
  - Report file modified after task start:           15 pts
  - Report mentions >=2 discovered usernames:        25 pts
  - Report is substantial (>=200 chars):             15 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60

# Usernames that should appear in the report if agent used ADAudit Plus
ACCOUNT_EVENT_USERS = {"jsmith", "mjohnson", "rwilliams", "abrown", "dlee"}
FAILED_LOGON_USERS = {"baduser1", "baduser2", "wrongadmin", "testattacker", "bruteforce1"}
ALL_EXPECTED_USERS = ACCOUNT_EVENT_USERS | FAILED_LOGON_USERS


def verify_investigate_account_activity(traj, env_info, task_info):
    """
    Verify that the agent:
    1. Created technician soc_analyst1 with Operator role
    2. Produced a findings report containing actual usernames from the audit trail
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    subscores = {}

    # Copy result JSON from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    temp_path = temp_file.name
    temp_file.close()

    try:
        copy_from_env("C:/Users/Docker/investigate_account_activity_result.json", temp_path)
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
    # Criterion 1: Technician soc_analyst1 created (30 pts)
    # -----------------------------------------------------------------------
    try:
        tech_exists = result.get("tech_soc_analyst1_exists", False)
        if isinstance(tech_exists, str):
            tech_exists = tech_exists.lower() == "true"
        tech_role = str(result.get("tech_soc_analyst1_role", "")).lower()

        if tech_exists:
            score += 20
            subscores["tech_created"] = True
            feedback_parts.append("Technician soc_analyst1 created (+20)")
            # Bonus for correct role
            if "operator" in tech_role:
                score += 10
                subscores["tech_role_correct"] = True
                feedback_parts.append("Correct Operator role (+10)")
            else:
                feedback_parts.append(f"Technician role '{tech_role}' — expected Operator (+0)")
        else:
            subscores["tech_created"] = False
            feedback_parts.append("Technician soc_analyst1 NOT found in system (0/30)")
    except Exception as e:
        logger.warning(f"Technician check failed: {e}")
        feedback_parts.append(f"Technician check error: {e}")

    # -----------------------------------------------------------------------
    # Criterion 2: Report file exists (15 pts)
    # -----------------------------------------------------------------------
    try:
        report_exists = result.get("report_file_exists", False)
        if isinstance(report_exists, str):
            report_exists = report_exists.lower() == "true"

        if report_exists:
            score += 15
            subscores["report_exists"] = True
            feedback_parts.append("Report file found on Desktop (+15)")
        else:
            subscores["report_exists"] = False
            feedback_parts.append("Report file not found at Desktop path (0/15)")
    except Exception as e:
        logger.warning(f"Report existence check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 3: Report modified after task start (15 pts)
    # -----------------------------------------------------------------------
    try:
        modified_after = result.get("report_modified_after_start", False)
        if isinstance(modified_after, str):
            modified_after = modified_after.lower() == "true"
        task_start = int(result.get("task_start", 0))
        report_mod = int(result.get("report_mod_time", 0))

        if modified_after and task_start > 0 and report_mod > task_start:
            score += 15
            subscores["report_fresh"] = True
            feedback_parts.append("Report created/modified after task started (+15)")
        elif report_exists and task_start == 0:
            # Can't verify timestamp — give partial credit
            score += 8
            subscores["report_fresh"] = "partial"
            feedback_parts.append("Report exists but timestamp unavailable (+8)")
        else:
            subscores["report_fresh"] = False
            feedback_parts.append("Report appears pre-existing or timestamp mismatch (0/15)")
    except Exception as e:
        logger.warning(f"Timestamp check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 4: Report mentions ≥2 real usernames from audit trail (25 pts)
    # -----------------------------------------------------------------------
    try:
        # Use the individual field flags for robustness
        found_users = set()
        user_flags = {
            "dlee": result.get("report_has_dlee", False),
            "mjohnson": result.get("report_has_mjohnson", False),
            "jsmith": result.get("report_has_jsmith", False),
            "abrown": result.get("report_has_abrown", False),
            "rwilliams": result.get("report_has_rwilliams", False),
            "baduser1": result.get("report_has_baduser1", False),
            "baduser2": result.get("report_has_baduser2", False),
            "wrongadmin": result.get("report_has_wrongadmin", False),
            "testattacker": result.get("report_has_testattacker", False),
            "bruteforce1": result.get("report_has_bruteforce1", False),
        }
        for uname, flag in user_flags.items():
            if isinstance(flag, str):
                flag = flag.lower() == "true"
            if flag:
                found_users.add(uname)

        # Fallback: also check found_users_list
        found_list_str = str(result.get("found_users_list", ""))
        if found_list_str:
            for u in found_list_str.split(","):
                u = u.strip().lower()
                if u and u in ALL_EXPECTED_USERS:
                    found_users.add(u)

        total_found = len(found_users)
        if total_found >= 3:
            score += 25
            subscores["report_content"] = total_found
            feedback_parts.append(f"Report contains {total_found} real usernames from audit trail (+25)")
        elif total_found == 2:
            score += 15
            subscores["report_content"] = total_found
            feedback_parts.append(f"Report contains {total_found} real usernames (+15)")
        elif total_found == 1:
            score += 8
            subscores["report_content"] = total_found
            feedback_parts.append(f"Report contains {total_found} real username (+8)")
        else:
            subscores["report_content"] = 0
            feedback_parts.append("Report contains no recognized usernames from ADAudit Plus audit trail (0/25)")
    except Exception as e:
        logger.warning(f"Content check failed: {e}")
        feedback_parts.append(f"Content check error: {e}")

    # -----------------------------------------------------------------------
    # Criterion 5: Report is substantial (≥200 chars) — 15 pts
    # -----------------------------------------------------------------------
    try:
        content_len = int(result.get("report_content_length", 0))
        file_size = int(result.get("report_file_size", 0))
        effective_size = max(content_len, file_size)

        if effective_size >= 400:
            score += 15
            subscores["report_substantial"] = True
            feedback_parts.append(f"Report is comprehensive ({effective_size} chars/bytes) (+15)")
        elif effective_size >= 200:
            score += 8
            subscores["report_substantial"] = "partial"
            feedback_parts.append(f"Report is adequate ({effective_size} chars/bytes) (+8)")
        else:
            subscores["report_substantial"] = False
            feedback_parts.append(f"Report too short ({effective_size} chars) — needs more detail (0/15)")
    except Exception as e:
        logger.warning(f"Size check failed: {e}")

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores,
    }
