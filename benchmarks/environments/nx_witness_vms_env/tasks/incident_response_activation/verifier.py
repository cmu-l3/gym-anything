#!/usr/bin/env python3
"""
Verifier for incident_response_activation task.

Scenario: Security breach response — restore full surveillance capability
across 4 independent subtasks.

Scoring (100 points):
  - All 3 cameras restored to 24/7 continuous recording     : 30 pts
    (10 pts each: Parking Lot, Entrance Camera, Server Room)
  - security.operator fullName updated to 'Night Watch Commander' : 15 pts
  - security.operator email updated correctly               : 15 pts
  - incident.cmdr user created with correct details         : 20 pts
  - 'Incident Command Center' layout created                : 5 pts
  - Layout contains all 3 cameras                          : 15 pts

Pass threshold: 65 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/incident_response_activation_result.json"
TARGET_SEC_OP_FULLNAME = "night watch commander"
TARGET_SEC_OP_EMAIL = "nightwatch@facility-security.com"
TARGET_ICMDR_LOGIN = "incident.cmdr"
TARGET_ICMDR_FULLNAME = "incident commander"
TARGET_ICMDR_EMAIL = "incident@facility-security.com"
TARGET_LAYOUT_NAME = "incident command center"


def verify_incident_response_activation(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env(RESULT_PATH, tmp.name)
            with open(tmp.name, "r") as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export script may not have run",
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []

    # --- Subtask 1: Camera recording restoration (30 pts total, 10 each) ---
    cameras = result.get("cameras", {})
    cam_labels = [
        ("parking", "Parking Lot Camera"),
        ("entrance", "Entrance Camera"),
        ("server", "Server Room Camera"),
    ]
    cameras_enabled = 0
    for cam_key, cam_display in cam_labels:
        cam = cameras.get(cam_key, {})
        is_enabled = cam.get("is_enabled", False)
        has_always = cam.get("has_always", False)
        days = cam.get("days_covered", 0)
        if is_enabled and has_always and days >= 7:
            score += 10
            cameras_enabled += 1
            feedback_parts.append(f"{cam_display}: 24/7 recording enabled (10/10)")
        elif is_enabled and has_always:
            score += 7
            feedback_parts.append(
                f"{cam_display}: recording enabled but not all 7 days "
                f"({days} days covered) (7/10)"
            )
        elif is_enabled:
            score += 3
            feedback_parts.append(
                f"{cam_display}: recording enabled but not 'always' type (3/10)"
            )
        else:
            feedback_parts.append(f"{cam_display}: recording still DISABLED (0/10)")

    # --- Subtask 2: security.operator user updated ---
    sec_op = result.get("security_operator", {})
    so_exists = sec_op.get("exists", False)
    so_fullname = sec_op.get("fullname", "").lower().strip()
    so_email = sec_op.get("email", "").lower().strip()

    if so_exists and so_fullname == TARGET_SEC_OP_FULLNAME:
        score += 15
        feedback_parts.append(
            "security.operator fullName updated to 'Night Watch Commander' (15/15)"
        )
    elif so_exists and "night watch" in so_fullname:
        score += 10
        feedback_parts.append(
            f"security.operator fullName close match '{sec_op.get('fullname','')}' (10/15)"
        )
    elif so_exists:
        feedback_parts.append(
            f"security.operator fullName NOT updated — still '{sec_op.get('fullname','')}' (0/15)"
        )
    else:
        feedback_parts.append("security.operator user NOT found (0/15)")

    if so_exists and so_email == TARGET_SEC_OP_EMAIL:
        score += 15
        feedback_parts.append(
            "security.operator email updated correctly (15/15)"
        )
    elif so_exists and "nightwatch" in so_email:
        score += 10
        feedback_parts.append(
            f"security.operator email close match '{sec_op.get('email','')}' (10/15)"
        )
    elif so_exists:
        feedback_parts.append(
            f"security.operator email NOT updated — got '{sec_op.get('email','')}' (0/15)"
        )
    else:
        feedback_parts.append("security.operator user NOT found — email check skipped (0/15)")

    # --- Subtask 3: incident.cmdr user created (20 pts) ---
    icmdr = result.get("incident_commander", {})
    ic_exists = icmdr.get("exists", False)
    ic_fullname = icmdr.get("fullname", "").lower().strip()
    ic_email = icmdr.get("email", "").lower().strip()

    if ic_exists and ic_fullname == TARGET_ICMDR_FULLNAME and ic_email == TARGET_ICMDR_EMAIL:
        score += 20
        feedback_parts.append(
            "incident.cmdr created with correct name and email (20/20)"
        )
    elif ic_exists and ic_email == TARGET_ICMDR_EMAIL:
        score += 15
        feedback_parts.append(
            f"incident.cmdr created, email correct, name mismatch "
            f"(got '{icmdr.get('fullname','')}') (15/20)"
        )
    elif ic_exists and ic_fullname == TARGET_ICMDR_FULLNAME:
        score += 12
        feedback_parts.append(
            f"incident.cmdr created, name correct, email mismatch "
            f"(got '{icmdr.get('email','')}') (12/20)"
        )
    elif ic_exists:
        score += 8
        feedback_parts.append(
            f"incident.cmdr account created but name/email incorrect (8/20)"
        )
    else:
        feedback_parts.append("incident.cmdr user NOT created (0/20)")

    # --- Subtask 4: 'Incident Command Center' layout (5 + 15 pts) ---
    icc = result.get("incident_command_center", {})
    icc_found = icc.get("found", False)
    layout_cams = result.get("layout_cameras", {})
    has_parking = layout_cams.get("has_parking", False)
    has_entrance = layout_cams.get("has_entrance", False)
    has_server = layout_cams.get("has_server", False)

    if icc_found:
        score += 5
        feedback_parts.append("'Incident Command Center' layout created (5/5)")
    else:
        feedback_parts.append("'Incident Command Center' layout NOT created (0/5)")

    if icc_found and has_parking and has_entrance and has_server:
        score += 15
        feedback_parts.append(
            "Layout contains all 3 cameras (Parking, Entrance, Server Room) (15/15)"
        )
    elif icc_found:
        present = []
        missing = []
        for flag, name in [
            (has_parking, "Parking Lot Camera"),
            (has_entrance, "Entrance Camera"),
            (has_server, "Server Room Camera"),
        ]:
            (present if flag else missing).append(name)
        cam_score = len(present) * 5
        score += cam_score
        feedback_parts.append(
            f"Layout has {len(present)}/3 cameras "
            f"(missing: {', '.join(missing) if missing else 'none'}) ({cam_score}/15)"
        )
    else:
        feedback_parts.append("Layout camera check skipped — layout not found (0/15)")

    passed = score >= 65
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
    }
