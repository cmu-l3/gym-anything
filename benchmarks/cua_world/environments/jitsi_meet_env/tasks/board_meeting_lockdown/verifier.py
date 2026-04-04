#!/usr/bin/env python3
"""Verifier for board_meeting_lockdown task.

Occupation: General and Operations Managers (SOC 11-1021.00)
Scenario: Secure a Q4 executive board meeting with Lobby + Password, copy invite, write summary.

Scoring (100 points):
  - Summary exists and modified after task start:   20 pts
  - Summary contains room name/URL:                 20 pts
  - Summary contains 'lobby':                       25 pts
  - Summary contains 'password'/'Board2024'/lock:   20 pts
  - Summary > 200 bytes:                            15 pts

Pass threshold: 60 points
Gate: If no summary file, score=0 immediately.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_board_meeting_lockdown(traj, env_info, task_info):
    """Verify board meeting security lockdown task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()

        try:
            copy_from_env("/tmp/board_meeting_lockdown_result.json", tmp_path)
            with open(tmp_path, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

        score = 0
        feedback_parts = []

        # GATE: No summary = no work done
        if not result.get('report_exists', 0):
            return {
                "passed": False,
                "score": 0,
                "feedback": (
                    "No summary file found at /home/ga/Desktop/board_security_summary.txt. "
                    "No evidence of task completion."
                )
            }

        task_start = int(result.get('task_start', 0))
        report_mtime = int(result.get('report_mtime', 0))
        report_size = int(result.get('report_size', 0))

        # Criterion 1: Summary exists and modified after task start (20 pts)
        try:
            if result.get('report_exists', 0) and report_mtime > task_start:
                score += 20
                feedback_parts.append("Summary created after task start (20/20)")
            else:
                feedback_parts.append(
                    f"Summary found but not modified after task start "
                    f"(mtime={report_mtime} vs start={task_start}) (0/20)"
                )
        except Exception as e:
            feedback_parts.append(f"Timestamp check error: {e}")

        # Criterion 2: Summary contains room name or URL (20 pts)
        try:
            if result.get('has_room_name', 0):
                score += 20
                feedback_parts.append("Summary references meeting room (20/20)")
            else:
                feedback_parts.append(
                    "Summary does not reference Q4ExecutiveBoard or meeting URL (0/20)"
                )
        except Exception as e:
            feedback_parts.append(f"Room name check error: {e}")

        # Criterion 3: Summary contains 'lobby' (25 pts)
        # 'lobby' only appears in Jitsi UI after navigating Security Options and enabling it
        try:
            if result.get('has_lobby', 0):
                score += 25
                feedback_parts.append("Summary documents lobby security feature (25/25)")
            else:
                feedback_parts.append(
                    "Summary does not mention lobby — was lobby enabled? (0/25)"
                )
        except Exception as e:
            feedback_parts.append(f"Lobby check error: {e}")

        # Criterion 4: Summary contains password vocabulary (20 pts)
        try:
            if result.get('has_password', 0):
                score += 20
                feedback_parts.append("Summary documents meeting password/lock (20/20)")
            else:
                feedback_parts.append(
                    "Summary does not mention password or room lock — was it set? (0/20)"
                )
        except Exception as e:
            feedback_parts.append(f"Password check error: {e}")

        # Criterion 5: Summary is substantial — > 200 bytes (15 pts)
        try:
            if report_size > 200:
                score += 15
                feedback_parts.append(f"Summary is substantial ({report_size} bytes) (15/15)")
            else:
                feedback_parts.append(
                    f"Summary too small ({report_size} bytes, need >200) (0/15)"
                )
        except Exception as e:
            feedback_parts.append(f"Size check error: {e}")

        passed = score >= 60
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria evaluated"
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export script may not have run"
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
