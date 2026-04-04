#!/usr/bin/env python3
"""Verifier for connection_quality_diagnostics task.

Occupation: General and Operations Managers / IT Management (SOC 11-1021.00)
Scenario: Benchmark a self-hosted Jitsi deployment by documenting connection stats,
          video quality settings, tile view, and speaker statistics.

Scoring (100 points):
  - Report exists and modified after task start:                20 pts
  - Report contains room URL/name:                             15 pts
  - Report contains connection stats vocabulary (RTT/jitter):  25 pts
  - Report contains video quality vocabulary:                  20 pts
  - Report contains tile view or speaker stats vocabulary:     10 pts
  - Report > 300 bytes:                                        10 pts

Pass threshold: 60 points
Gate: If no report exists, score=0 immediately.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_connection_quality_diagnostics(traj, env_info, task_info):
    """Verify connection quality diagnostics task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()

        try:
            copy_from_env("/tmp/connection_quality_diagnostics_result.json", tmp_path)
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
                    "No diagnostic report found at /home/ga/Desktop/meeting_quality_report.txt. "
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
                feedback_parts.append("Diagnostic report created after task start (20/20)")
            else:
                feedback_parts.append(
                    f"Report found but not modified after task start "
                    f"(mtime={report_mtime} vs start={task_start}) (0/20)"
                )
        except Exception as e:
            feedback_parts.append(f"Timestamp check error: {e}")

        # Criterion 2: Report contains meeting URL or room name (15 pts)
        try:
            if result.get('has_url', 0):
                score += 15
                feedback_parts.append("Report references meeting room URL/name (15/15)")
            else:
                feedback_parts.append(
                    "Report does not reference QualityTestRoom or its URL (0/15)"
                )
        except Exception as e:
            feedback_parts.append(f"URL check error: {e}")

        # Criterion 3: Report contains connection statistics vocabulary (25 pts)
        # RTT, packet loss, jitter, bitrate — only appear in Jitsi's connection stats panel
        try:
            if result.get('has_stats', 0):
                score += 25
                feedback_parts.append(
                    "Report contains connection statistics (RTT/jitter/packet loss/bitrate) (25/25)"
                )
            else:
                feedback_parts.append(
                    "Report lacks connection stats vocabulary — was the stats panel opened? (0/25)"
                )
        except Exception as e:
            feedback_parts.append(f"Stats vocabulary check error: {e}")

        # Criterion 4: Report contains video quality vocabulary (20 pts)
        # 'Low/Standard/High Definition' only appear in Jitsi's video quality dialog
        try:
            if result.get('has_quality', 0):
                score += 20
                feedback_parts.append(
                    "Report documents video quality settings (20/20)"
                )
            else:
                feedback_parts.append(
                    "Report lacks video quality vocabulary — was the quality dialog opened? (0/20)"
                )
        except Exception as e:
            feedback_parts.append(f"Quality vocabulary check error: {e}")

        # Criterion 5: Report contains tile view or speaker stats vocabulary (10 pts)
        try:
            if result.get('has_tile_or_speaker', 0):
                score += 10
                feedback_parts.append("Report documents tile view or speaker statistics (10/10)")
            else:
                feedback_parts.append(
                    "Report lacks tile view/speaker stats vocabulary (0/10)"
                )
        except Exception as e:
            feedback_parts.append(f"Tile/speaker check error: {e}")

        # Criterion 6: Report is substantial — > 300 bytes (10 pts)
        try:
            if report_size > 300:
                score += 10
                feedback_parts.append(f"Report is substantial ({report_size} bytes) (10/10)")
            else:
                feedback_parts.append(
                    f"Report too small ({report_size} bytes, need >300) (0/10)"
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
