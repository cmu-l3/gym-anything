#!/usr/bin/env python3
"""Verifier for rsi_interpreter_session task.

Occupation: Interpreters and Translators (SOC 27-3091.00)
Scenario: Configure a secure RSI conference session in Jitsi Meet.

Scoring (100 points):
  - Report exists and modified after task start: 20 pts
  - Report file > 300 bytes:                    10 pts
  - Report contains meeting URL:                15 pts
  - Report contains 'lobby':                    20 pts
  - Report contains 'muted'/'microphone':       15 pts
  - Clipboard contains meeting URL:             20 pts

Pass threshold: 60 points
Gate: If no report exists, score=0 immediately.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_rsi_interpreter_session(traj, env_info, task_info):
    """Verify RSI interpreter session setup task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        # Copy result JSON from VM
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()

        try:
            copy_from_env("/tmp/rsi_interpreter_session_result.json", tmp_path)
            with open(tmp_path, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

        score = 0
        feedback_parts = []

        # GATE: If no report exists, no work was done
        if not result.get('report_exists', 0):
            return {
                "passed": False,
                "score": 0,
                "feedback": (
                    "No report file found at /home/ga/Desktop/rsi_conference_report.txt. "
                    "No evidence of task completion."
                )
            }

        task_start = int(result.get('task_start', 0))
        report_mtime = int(result.get('report_mtime', 0))
        report_size = int(result.get('report_size', 0))

        # Criterion 1: Report exists and was modified after task started (20 pts)
        try:
            if result.get('report_exists', 0) and report_mtime > task_start:
                score += 20
                feedback_parts.append("Report created after task start (20/20)")
            else:
                feedback_parts.append(
                    f"Report found but not modified after task start "
                    f"(mtime={report_mtime} vs start={task_start}) (0/20)"
                )
        except Exception as e:
            feedback_parts.append(f"Report timestamp check error: {e}")

        # Criterion 2: Report is substantial — > 300 bytes (10 pts)
        try:
            if report_size > 300:
                score += 10
                feedback_parts.append(f"Report is substantial ({report_size} bytes) (10/10)")
            else:
                feedback_parts.append(
                    f"Report too small ({report_size} bytes, need >300) (0/10)"
                )
        except Exception as e:
            feedback_parts.append(f"Report size check error: {e}")

        # Criterion 3: Report contains meeting URL (15 pts)
        try:
            if result.get('has_url', 0):
                score += 15
                feedback_parts.append("Report contains meeting URL (15/15)")
            else:
                feedback_parts.append(
                    "Report does not contain meeting URL (localhost:8080/RSI-IntlConf-2024) (0/15)"
                )
        except Exception as e:
            feedback_parts.append(f"URL check error: {e}")

        # Criterion 4: Report documents lobby feature (20 pts)
        # 'lobby' only appears in Jitsi UI after navigating Security Options and enabling it
        try:
            if result.get('has_lobby', 0):
                score += 20
                feedback_parts.append("Report documents lobby/waiting-room feature (20/20)")
            else:
                feedback_parts.append(
                    "Report does not mention lobby feature — was it enabled? (0/20)"
                )
        except Exception as e:
            feedback_parts.append(f"Lobby check error: {e}")

        # Criterion 5: Report documents mute policy (15 pts)
        # 'muted'/'microphone' only appear after configuring the everyone-starts-muted setting
        try:
            if result.get('has_muted', 0):
                score += 15
                feedback_parts.append("Report documents mute policy (15/15)")
            else:
                feedback_parts.append(
                    "Report does not mention mute policy — was everyone-starts-muted enabled? (0/15)"
                )
        except Exception as e:
            feedback_parts.append(f"Mute check error: {e}")

        # Criterion 6: Clipboard contains meeting URL (20 pts)
        # Verifies the agent actually copied the invite link
        try:
            if result.get('clipboard_has_url', 0):
                score += 20
                feedback_parts.append("Clipboard contains meeting URL (invite was copied) (20/20)")
            else:
                feedback_parts.append(
                    "Clipboard does not contain meeting URL — invite link not copied (0/20)"
                )
        except Exception as e:
            feedback_parts.append(f"Clipboard check error: {e}")

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
