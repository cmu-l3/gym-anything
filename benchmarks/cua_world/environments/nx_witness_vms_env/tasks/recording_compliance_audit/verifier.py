#!/usr/bin/env python3
"""
Verifier for recording_compliance_audit task.

Scenario: Loss Prevention Manager audits VMS recording coverage gaps.
Setup injected: Parking Lot Camera and Server Room Camera had recording disabled.
Entrance Camera was left with recording enabled as the known-good baseline.

Scoring (100 points):
  - Parking Lot Camera: 24/7 recording enabled with 'always' type   : 25 pts
  - Server Room Camera: 24/7 recording enabled with 'always' type   : 25 pts
  - Entrance Camera: continuous recording still intact               : 10 pts
  - Layout 'Compliance Audit View' created                          : 10 pts
  - Layout contains all cameras in the system                       : 30 pts

Pass threshold: 60 points (agent must fix both broken cameras and create layout)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/recording_compliance_audit_result.json"


def verify_recording_compliance_audit(traj, env_info, task_info):
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

    def is_fully_recording(cam_data):
        """Returns True if camera has 24/7 continuous recording (all 7 days, always type)."""
        if not cam_data or not isinstance(cam_data, dict):
            return False
        if not cam_data.get("is_enabled", False):
            return False
        # Require tasks for at least 5 days and always-type recording
        return cam_data.get("task_count", 0) >= 5 and cam_data.get("has_always_type", False)

    def is_recording_enabled(cam_data):
        """Returns True if camera has at least some recording configured."""
        if not cam_data or not isinstance(cam_data, dict):
            return False
        return cam_data.get("is_enabled", False) and cam_data.get("task_count", 0) > 0

    # --- Subtask 1: Parking Lot Camera recording fixed ---
    parking = result.get("parking_lot_recording", {})
    if is_fully_recording(parking):
        score += 25
        feedback_parts.append("Parking Lot Camera: 24/7 recording enabled (25/25)")
    elif is_recording_enabled(parking):
        score += 12
        feedback_parts.append(
            f"Parking Lot Camera: recording enabled but incomplete schedule "
            f"(days={parking.get('days_covered',0)}, always={parking.get('has_always_type',False)}) (12/25)"
        )
    else:
        feedback_parts.append("Parking Lot Camera: recording NOT enabled (0/25)")

    # --- Subtask 2: Server Room Camera recording fixed ---
    server = result.get("server_room_recording", {})
    if is_fully_recording(server):
        score += 25
        feedback_parts.append("Server Room Camera: 24/7 recording enabled (25/25)")
    elif is_recording_enabled(server):
        score += 12
        feedback_parts.append(
            f"Server Room Camera: recording enabled but incomplete schedule "
            f"(days={server.get('days_covered',0)}, always={server.get('has_always_type',False)}) (12/25)"
        )
    else:
        feedback_parts.append("Server Room Camera: recording NOT enabled (0/25)")

    # --- Subtask 3: Entrance Camera also needs 24/7 always recording ---
    # The task says ALL cameras must record continuously — entrance too.
    # setup_task.sh enables it with a non-always schedule; agent must reconfigure with 'always'.
    # Partial credit (enabled but wrong type) intentionally gives 0 to make do-nothing test pass.
    entrance = result.get("entrance_camera_recording", {})
    if is_fully_recording(entrance):
        score += 10
        feedback_parts.append("Entrance Camera: 24/7 continuous recording configured (10/10)")
    else:
        always_flag = entrance.get("has_always_type", False)
        enabled_flag = entrance.get("is_enabled", False)
        feedback_parts.append(
            f"Entrance Camera: not fully configured (enabled={enabled_flag}, always={always_flag}) (0/10)"
        )

    # --- Subtask 4: Layout 'Compliance Audit View' created ---
    layout_check = result.get("layout_check", {})
    layout_found = layout_check.get("layout_found", False)
    cameras_matched = layout_check.get("cameras_matched", 0)
    total_cameras = result.get("total_cameras", 3)

    if layout_found:
        score += 10
        feedback_parts.append("'Compliance Audit View' layout exists (10/10)")
    else:
        feedback_parts.append("'Compliance Audit View' layout NOT found (0/10)")

    # --- Subtask 5: Layout contains all cameras ---
    if layout_found and cameras_matched >= total_cameras:
        score += 30
        feedback_parts.append(f"Layout contains all {total_cameras} cameras (30/30)")
    elif layout_found and cameras_matched >= 2:
        score += 15
        feedback_parts.append(f"Layout contains {cameras_matched}/{total_cameras} cameras (15/30)")
    elif layout_found and cameras_matched >= 1:
        score += 7
        feedback_parts.append(f"Layout contains only {cameras_matched}/{total_cameras} cameras (7/30)")
    else:
        feedback_parts.append("Layout is empty or contains no recognized cameras (0/30)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
    }
