#!/usr/bin/env python3
"""
Verifier for visualize_bone_skin_overlay task.

Scoring (100 points total):
  - Project file saved at correct path:           10 pts
  - Project file created/modified during task:    10 pts
  - Valid InVesalius project format:              10 pts
  - Two distinct surfaces exist:                  30 pts
  - Opaque surface present (Bone):                20 pts
  - Transparent surface present (Skin):           20 pts

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_visualize_bone_skin_overlay(traj, env_info, task_info):
    """Verify that the agent created an overlay visualization with bone and skin."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    
    # Read result file
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}",
        }

    # --- Criterion 1: File Existence (10 pts) ---
    if result.get("file_exists"):
        score += 10
        feedback_parts.append("Project file exists")
    else:
        feedback_parts.append("Project file not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # --- Criterion 2: Anti-Gaming / Timestamp (10 pts) ---
    if result.get("created_during_task"):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp invalid (pre-existing?)")

    # --- Criterion 3: Valid Format (10 pts) ---
    if result.get("valid_inv3"):
        score += 10
        feedback_parts.append("Valid .inv3 format")
    else:
        feedback_parts.append(f"Invalid format: {result.get('error')}")
        # Stop here if invalid format
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # --- Criterion 4: Surface Count (30 pts) ---
    surf_count = result.get("surface_count", 0)
    if surf_count >= 2:
        score += 30
        feedback_parts.append(f"Found {surf_count} surfaces")
    elif surf_count == 1:
        score += 5 # Partial credit
        feedback_parts.append("Found only 1 surface (need 2: bone + skin)")
    else:
        feedback_parts.append("No surfaces found in project")

    # --- Criterion 5: Opaque Surface (20 pts) ---
    if result.get("has_opaque"):
        score += 20
        feedback_parts.append("Opaque surface present")
    else:
        feedback_parts.append("Missing opaque surface (transparency < 0.1)")

    # --- Criterion 6: Transparent Surface (20 pts) ---
    if result.get("has_transparent"):
        score += 20
        feedback_parts.append("Transparent surface present")
    else:
        feedback_parts.append("Missing transparent surface (0.2 < transparency < 0.9)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "detail": {
            "surfaces": result.get("surfaces", [])
        }
    }