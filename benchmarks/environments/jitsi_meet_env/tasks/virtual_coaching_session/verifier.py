#!/usr/bin/env python3
"""Verifier for virtual_coaching_session task.

Occupation: Exercise Trainers and Group Fitness Instructors (SOC 39-9031.00)
Scenario: Set up a professional virtual fitness coaching session in Jitsi Meet.

Scoring (100 points):
  - Guide exists and modified after task start:       20 pts
  - Guide contains meeting URL:                       15 pts
  - Guide contains virtual background vocabulary:     25 pts
  - Guide contains mute policy vocabulary:            20 pts
  - Guide contains coaching/fitness vocabulary:       10 pts
  - Guide > 300 bytes:                                10 pts

Pass threshold: 60 points
Gate: If no guide exists, score=0 immediately.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_virtual_coaching_session(traj, env_info, task_info):
    """Verify virtual coaching session setup task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()

        try:
            copy_from_env("/tmp/virtual_coaching_session_result.json", tmp_path)
            with open(tmp_path, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

        score = 0
        feedback_parts = []

        # GATE: No guide = no work done
        if not result.get('report_exists', 0):
            return {
                "passed": False,
                "score": 0,
                "feedback": (
                    "No configuration guide found at /home/ga/Desktop/coaching_session_config.txt. "
                    "No evidence of task completion."
                )
            }

        task_start = int(result.get('task_start', 0))
        report_mtime = int(result.get('report_mtime', 0))
        report_size = int(result.get('report_size', 0))

        # Criterion 1: Guide exists and modified after task start (20 pts)
        try:
            if result.get('report_exists', 0) and report_mtime > task_start:
                score += 20
                feedback_parts.append("Configuration guide created after task start (20/20)")
            else:
                feedback_parts.append(
                    f"Guide found but not modified after task start "
                    f"(mtime={report_mtime} vs start={task_start}) (0/20)"
                )
        except Exception as e:
            feedback_parts.append(f"Timestamp check error: {e}")

        # Criterion 2: Guide contains meeting URL (15 pts)
        try:
            if result.get('has_url', 0):
                score += 15
                feedback_parts.append("Guide contains meeting URL (15/15)")
            else:
                feedback_parts.append(
                    "Guide does not contain meeting URL or room name (0/15)"
                )
        except Exception as e:
            feedback_parts.append(f"URL check error: {e}")

        # Criterion 3: Guide documents virtual background (25 pts)
        # 'virtual', 'background', 'blur' only appear after using Jitsi's background feature
        try:
            if result.get('has_background', 0):
                score += 25
                feedback_parts.append("Guide documents virtual background configuration (25/25)")
            else:
                feedback_parts.append(
                    "Guide does not mention virtual background/blur — was it configured? (0/25)"
                )
        except Exception as e:
            feedback_parts.append(f"Background check error: {e}")

        # Criterion 4: Guide documents mute policy (20 pts)
        try:
            if result.get('has_muted', 0):
                score += 20
                feedback_parts.append("Guide documents mute/audio policy (20/20)")
            else:
                feedback_parts.append(
                    "Guide does not mention mute policy — was everyone-starts-muted enabled? (0/20)"
                )
        except Exception as e:
            feedback_parts.append(f"Mute check error: {e}")

        # Criterion 5: Guide contains coaching/fitness vocabulary (10 pts)
        try:
            if result.get('has_coaching', 0):
                score += 10
                feedback_parts.append("Guide contains professional coaching vocabulary (10/10)")
            else:
                feedback_parts.append(
                    "Guide lacks fitness/coaching context (0/10)"
                )
        except Exception as e:
            feedback_parts.append(f"Coaching vocabulary check error: {e}")

        # Criterion 6: Guide is substantial — > 300 bytes (10 pts)
        try:
            if report_size > 300:
                score += 10
                feedback_parts.append(f"Guide is substantial ({report_size} bytes) (10/10)")
            else:
                feedback_parts.append(
                    f"Guide too small ({report_size} bytes, need >300) (0/10)"
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
