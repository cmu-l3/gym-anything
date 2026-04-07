#!/usr/bin/env python3
"""
Stub verifier for complete_base_transfer_setup task.

Actual verification is done externally via VLM checklist evaluator.
This stub pulls the export JSON and returns a basic programmatic score
for framework compatibility.

Scoring breakdown (100 points):
  - Display name "Capt. Rodriguez | LAX": 20 pts
  - Position set to Captain: 15 pts
  - Home airport LAX: 10 pts
  - Base airport LAX: 10 pts
  - Battery set to Unrestricted: 15 pts
  - DND enabled: 10 pts
  - App is DND exception: 10 pts
  - Crew chat message sent: 10 pts

Pass threshold: 60 points
"""
import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_complete_base_transfer_setup(traj, env_info, task_info):
    """Stub verifier - real verification is done via external VLM evaluation."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    task_name = "complete_base_transfer_setup"
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env(f"/sdcard/{task_name}_result.json", tmp.name)
            with open(tmp.name, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)

        score = 0
        parts = []

        # Profile checks
        if result.get("display_name_found"):
            score += 20
            parts.append("Display name set (20/20)")
        else:
            parts.append("Display name not set (0/20)")

        if result.get("position_found"):
            score += 15
            parts.append("Position Captain (15/15)")
        else:
            parts.append("Position not Captain (0/15)")

        if result.get("home_airport_found"):
            score += 10
            parts.append("Home airport LAX (10/10)")
        else:
            parts.append("Home airport not LAX (0/10)")

        if result.get("base_airport_found"):
            score += 10
            parts.append("Base airport LAX (10/10)")
        else:
            parts.append("Base airport not LAX (0/10)")

        # System hardening checks
        if result.get("battery_whitelisted"):
            score += 15
            parts.append("Battery unrestricted (15/15)")
        else:
            parts.append("Battery not unrestricted (0/15)")

        if result.get("dnd_enabled"):
            score += 10
            parts.append("DND enabled (10/10)")
        else:
            parts.append("DND not enabled (0/10)")

        if result.get("dnd_exception") or result.get("dnd_channel_bypass"):
            score += 10
            parts.append("DND exception set (10/10)")
        else:
            parts.append("DND exception not set (0/10)")

        # Chat check
        if result.get("chat_message_found"):
            score += 10
            parts.append("Chat message sent (10/10)")
        else:
            parts.append("Chat message not found (0/10)")

        passed = score >= 60
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(parts),
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found",
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
        }
