#!/usr/bin/env python3
"""
Verifier for defect_triage_and_escalation task.

Checks 6 independent criteria:
1. Pagination bug priority changed to Immediate (12pts)
2. Pagination bug status changed to In progress (10pts)
3. Comment on pagination bug about production incident (15pts)
4. JWT audit priority changed to High + comment added (18pts)
5. Emergency bug WP created with correct attributes (25pts)
6. Wiki incident report page (20pts)

Total: 100pts. Pass threshold: 65.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_FILE = "/tmp/defect_result.json"


def verify_defect_triage_and_escalation(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(RESULT_FILE, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []

    # --- Anti-gaming gate ---
    pagination = result.get("pagination", {})
    emergency = result.get("emergency", {})
    if not pagination.get("found", False) and not emergency.get("found", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No WP modifications found. Agent likely did nothing.",
        }

    # --- Criterion 1: Pagination bug priority to Immediate (12pts) ---
    if pagination.get("found", False):
        p_priority = (pagination.get("priority") or "").lower()
        if p_priority == "immediate":
            score += 12
            feedback.append("Pagination bug priority changed to 'Immediate'.")
        elif p_priority in ("urgent", "high"):
            score += 7
            feedback.append(f"Pagination bug priority changed to '{p_priority}' (expected 'Immediate').")
        elif p_priority != "normal":
            score += 3
            feedback.append(f"Pagination bug priority is '{p_priority}'.")
        else:
            feedback.append("Pagination bug priority still 'Normal'.")
    else:
        feedback.append("Pagination bug WP not found.")

    # --- Criterion 2: Pagination bug status to In progress (10pts) ---
    if pagination.get("found", False):
        p_status = (pagination.get("status") or "").lower()
        if p_status == "in progress":
            score += 10
            feedback.append("Pagination bug status changed to 'In progress'.")
        elif p_status != "new":
            score += 5
            feedback.append(f"Pagination bug status changed to '{p_status}'.")
        else:
            feedback.append("Pagination bug status still 'New'.")

    # --- Criterion 3: Comment on pagination bug (15pts) ---
    if pagination.get("found", False):
        notes = pagination.get("notes", [])
        all_notes = " ".join(str(n).lower() for n in notes)
        has_production = "production" in all_notes
        has_escalated = "escalat" in all_notes or "p0" in all_notes
        has_customer = "customer" in all_notes or "support" in all_notes or "ticket" in all_notes

        matched = sum([has_production, has_escalated, has_customer])
        if matched >= 2:
            score += 15
            feedback.append("Pagination bug comment matches expected incident content.")
        elif matched >= 1:
            score += 8
            feedback.append("Pagination bug has partial incident comment.")
        elif len(all_notes.strip()) > 10:
            score += 4
            feedback.append("Pagination bug has comment but missing incident keywords.")
        else:
            feedback.append("No relevant comment on pagination bug.")

    # --- Criterion 4: JWT audit priority to High + comment (18pts) ---
    jwt = result.get("jwt", {})
    if jwt.get("found", False):
        j_priority = (jwt.get("priority") or "").lower()
        if j_priority == "high":
            score += 8
            feedback.append("JWT audit priority changed to 'High'.")
        elif j_priority in ("urgent", "immediate"):
            score += 6
            feedback.append(f"JWT audit priority changed to '{j_priority}' (expected 'High').")
        elif j_priority != "normal":
            score += 3
            feedback.append(f"JWT audit priority is '{j_priority}'.")
        else:
            feedback.append("JWT audit priority still 'Normal'.")

        j_notes = jwt.get("notes", [])
        j_all_notes = " ".join(str(n).lower() for n in j_notes)
        has_vuln = "vulnerab" in j_all_notes or "security" in j_all_notes
        has_jwt = "jwt" in j_all_notes or "token" in j_all_notes
        has_logout = "logout" in j_all_notes or "persist" in j_all_notes
        j_matched = sum([has_vuln, has_jwt, has_logout])
        if j_matched >= 2:
            score += 10
            feedback.append("JWT audit comment matches expected security content.")
        elif j_matched >= 1:
            score += 5
            feedback.append("JWT audit has partial security comment.")
        elif len(j_all_notes.strip()) > 10:
            score += 3
            feedback.append("JWT audit has comment but missing security keywords.")
        else:
            feedback.append("No relevant comment on JWT audit.")
    else:
        feedback.append("JWT audit WP not found.")

    # --- Criterion 5: Emergency bug WP created (25pts) ---
    if emergency.get("found", False):
        score += 7
        feedback.append("Emergency bug WP created.")

        e_type = (emergency.get("type_name") or "").lower()
        if e_type == "bug":
            score += 4
            feedback.append("Emergency WP type is 'Bug'.")
        else:
            feedback.append(f"Emergency WP type is '{e_type}', expected 'Bug'.")

        e_assignee = (emergency.get("assignee") or "").lower()
        if "carol" in e_assignee:
            score += 4
            feedback.append("Emergency WP assigned to carol.williams.")
        else:
            feedback.append(f"Emergency WP assigned to '{e_assignee}'.")

        e_version = (emergency.get("version_name") or "").lower()
        if "sprint 1" in e_version or "auth" in e_version:
            score += 3
            feedback.append("Emergency WP in Sprint 1 - Auth & Onboarding.")
        else:
            feedback.append(f"Emergency WP version is '{e_version}'.")

        e_priority = (emergency.get("priority") or "").lower()
        if e_priority == "urgent":
            score += 4
            feedback.append("Emergency WP priority is 'Urgent'.")
        elif e_priority in ("immediate", "high"):
            score += 2
            feedback.append(f"Emergency WP priority is '{e_priority}' (expected 'Urgent').")
        else:
            feedback.append(f"Emergency WP priority is '{e_priority}'.")

        e_desc = (emergency.get("description") or "").lower()
        if "token" in e_desc or "logout" in e_desc or "revoc" in e_desc:
            score += 3
            feedback.append("Emergency WP has relevant description.")
        elif len(e_desc) > 10:
            score += 1
            feedback.append("Emergency WP has description but missing key terms.")
    else:
        initial_count = result.get("initial_wp_count", 0)
        current_count = result.get("current_wp_count", 0)
        if current_count > initial_count:
            score += 3
            feedback.append("New WP created but with wrong subject.")
        else:
            feedback.append("Emergency bug WP NOT created.")

    # --- Criterion 6: Wiki incident report (20pts) ---
    wiki = result.get("wiki", {})
    if wiki.get("exists", False):
        score += 5
        feedback.append("Wiki incident report page exists.")

        content_length = wiki.get("content_length", 0)
        if content_length < 20:
            feedback.append("Wiki content too short.")
        else:
            wiki_score = 0
            if wiki.get("has_pagination", False):
                wiki_score += 3
                feedback.append("Wiki mentions pagination/transaction.")
            if wiki.get("has_production", False):
                wiki_score += 3
                feedback.append("Wiki mentions production/incident.")
            if wiki.get("has_customer", False):
                wiki_score += 3
                feedback.append("Wiki mentions customer/user impact.")
            if wiki.get("has_escalation", False):
                wiki_score += 3
                feedback.append("Wiki mentions escalation/priority.")
            if wiki.get("has_remediation", False):
                wiki_score += 3
                feedback.append("Wiki mentions remediation/fix steps.")

            if wiki_score == 0:
                feedback.append("Wiki content missing all expected keywords.")
            score += wiki_score
    else:
        feedback.append("Wiki incident report page NOT found.")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
