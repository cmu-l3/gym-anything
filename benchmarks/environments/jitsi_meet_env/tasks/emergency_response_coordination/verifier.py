#!/usr/bin/env python3
"""Verifier for emergency_response_coordination task.

Occupation: General and Operations Managers / IT Incident Response (SOC 11-1021.00)
Scenario: Deploy and fully configure an emergency incident response meeting in Jitsi Meet.

Scoring (100 points):
  - Report exists and modified after task start:                         15 pts
  - Report contains correct room URL/name (Incident-Response-CRIT001):  15 pts
  - Report contains 'lobby':                                             20 pts
  - Report contains 'password'/'lock':                                   15 pts
  - Report references chat message or 'INCIDENT RESPONSE':              15 pts
  - Clipboard contains meeting URL:                                      10 pts
  - Report > 400 bytes:                                                  10 pts

Pass threshold: 65 points
Gate: If no report exists, score=0 immediately.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_emergency_response_coordination(traj, env_info, task_info):
    """Verify emergency response coordination task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()

        try:
            copy_from_env("/tmp/emergency_response_coordination_result.json", tmp_path)
            with open(tmp_path, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

        score = 0
        feedback_parts = []

        # GATE: No report = no work done
        if not result.get('report_exists', 0):
            return {
                "passed": False,
                "score": 0,
                "feedback": (
                    "No incident report found at /home/ga/Desktop/incident_response_meeting_report.txt. "
                    "No evidence of task completion."
                )
            }

        task_start = int(result.get('task_start', 0))
        report_mtime = int(result.get('report_mtime', 0))
        report_size = int(result.get('report_size', 0))

        # Criterion 1: Report exists and was modified after task started (15 pts)
        try:
            if result.get('report_exists', 0) and report_mtime > task_start:
                score += 15
                feedback_parts.append("Incident report created after task start (15/15)")
            else:
                feedback_parts.append(
                    f"Report found but not modified after task start "
                    f"(mtime={report_mtime} vs start={task_start}) (0/15)"
                )
        except Exception as e:
            feedback_parts.append(f"Timestamp check error: {e}")

        # Criterion 2: Report contains correct room URL or name (15 pts)
        try:
            if result.get('has_room_url', 0):
                score += 15
                feedback_parts.append(
                    "Report references Incident-Response-CRIT001 room (15/15)"
                )
            else:
                feedback_parts.append(
                    "Report does not reference the correct room name (Incident-Response-CRIT001) (0/15)"
                )
        except Exception as e:
            feedback_parts.append(f"Room URL check error: {e}")

        # Criterion 3: Report documents lobby feature (20 pts)
        # 'lobby' only appears after navigating Security Options and enabling it
        try:
            if result.get('has_lobby', 0):
                score += 20
                feedback_parts.append("Report documents lobby security feature (20/20)")
            else:
                feedback_parts.append(
                    "Report does not mention lobby — was the lobby enabled? (0/20)"
                )
        except Exception as e:
            feedback_parts.append(f"Lobby check error: {e}")

        # Criterion 4: Report documents password/room lock (15 pts)
        try:
            if result.get('has_password', 0):
                score += 15
                feedback_parts.append("Report documents meeting password/lock (15/15)")
            else:
                feedback_parts.append(
                    "Report does not mention meeting password or room lock (0/15)"
                )
        except Exception as e:
            feedback_parts.append(f"Password check error: {e}")

        # Criterion 5: Report references the chat message or incident activation (15 pts)
        # 'INCIDENT RESPONSE ACTIVE' only appears after the agent sent the chat message and documented it
        try:
            if result.get('has_chat_msg', 0):
                score += 15
                feedback_parts.append(
                    "Report references chat message or incident response notification (15/15)"
                )
            else:
                feedback_parts.append(
                    "Report does not reference chat message 'INCIDENT RESPONSE ACTIVE...' (0/15)"
                )
        except Exception as e:
            feedback_parts.append(f"Chat message check error: {e}")

        # Criterion 6: Clipboard contains meeting URL (10 pts)
        try:
            if result.get('clipboard_has_url', 0):
                score += 10
                feedback_parts.append("Clipboard contains meeting URL (invite was copied) (10/10)")
            else:
                feedback_parts.append(
                    "Clipboard does not contain meeting URL (0/10)"
                )
        except Exception as e:
            feedback_parts.append(f"Clipboard check error: {e}")

        # Criterion 7: Report is substantial — > 400 bytes (10 pts)
        try:
            if report_size > 400:
                score += 10
                feedback_parts.append(f"Incident report is comprehensive ({report_size} bytes) (10/10)")
            else:
                feedback_parts.append(
                    f"Incident report too small ({report_size} bytes, need >400) (0/10)"
                )
        except Exception as e:
            feedback_parts.append(f"Size check error: {e}")

        passed = score >= 65
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
