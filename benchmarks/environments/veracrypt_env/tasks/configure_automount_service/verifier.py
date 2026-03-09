#!/usr/bin/env python3
"""Verifier for configure_automount_service task."""

import json
import tempfile
import os
import logging
import base64

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_automount_service(traj, env_info, task_info):
    """
    Verify that the systemd service for VeraCrypt automounting was configured correctly.

    Checks:
    1. Service file exists at /etc/systemd/system/veracrypt-media.service (20 pts)
    2. Service is active (systemctl is-active) (20 pts)
    3. Volume is successfully mounted at /mnt/media_vault (30 pts)
    4. Data inside volume is readable (proof of correct decryption/keyfile usage) (20 pts)
    5. Service includes ExecStop for clean dismount (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying result: {e}")
            return {"passed": False, "score": 0, "feedback": f"Error copying result: {e}"}

        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        # Criterion 1: Service File Existence (20 pts)
        if result.get('service_exists'):
            score += 20
            feedback_parts.append("Service file created")
            
            # Analyze content if available
            try:
                content_b64 = result.get('service_content_b64', '')
                if content_b64:
                    content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
                    if "veracrypt" not in content.lower():
                        feedback_parts.append("WARNING: Service file content seems suspicious (no 'veracrypt' found)")
            except Exception:
                pass
        else:
            feedback_parts.append("Service file MISSING")

        # Criterion 2: Service Active (20 pts)
        if result.get('service_active'):
            score += 20
            feedback_parts.append("Service is active")
        else:
            feedback_parts.append("Service is NOT active")

        # Criterion 3: Volume Mounted (30 pts)
        if result.get('volume_mounted'):
            score += 30
            feedback_parts.append("Volume mounted successfully")
        else:
            feedback_parts.append("Volume NOT mounted at target")

        # Criterion 4: Data Accessible (20 pts)
        if result.get('data_accessible'):
            score += 20
            feedback_parts.append("Data verified readable")
        else:
            feedback_parts.append("Data NOT readable (decryption failed or wrong mount)")

        # Criterion 5: Dismount Configured (10 pts)
        if result.get('has_exec_stop'):
            score += 10
            feedback_parts.append("Dismount (ExecStop) configured")
        else:
            feedback_parts.append("Dismount command missing from service")

        # Bonus info
        if result.get('service_enabled'):
            feedback_parts.append("(Service is enabled for boot)")

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    passed = score >= 70
    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }