#!/usr/bin/env python3
"""
Verifier for Open DICOM task
"""

import sys
import os
import json
import logging
import tempfile

# Add utils to path (relative to this file, for host execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

try:
    from weasis_verification_utils import (
        setup_verification_environment,
        cleanup_verification_environment,
        calculate_task_score
    )
except ImportError:
    # Fallback if utils not available
    pass

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_open_dicom(traj, env_info, task_info):
    """
    Verify that a DICOM file was opened in Weasis.

    Checks:
    1. Result file exists and is valid JSON
    2. DICOM was detected as loaded (window title changed or logs show loading)
    3. A DICOM file was recently accessed
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    criteria_met = 0
    total_criteria = 3
    feedback_parts = []

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Criterion 1: Result file is valid
    criteria_met += 1
    feedback_parts.append("Result file valid")

    # Criterion 2: DICOM was detected as loaded
    if result.get('found', False):
        criteria_met += 1
        window_title = result.get('window_title', '')
        feedback_parts.append(f"DICOM loaded (window: {window_title[:50]}...)" if len(window_title) > 50 else f"DICOM loaded (window: {window_title})")
    else:
        # Check alternative indicators
        recent_dicom = result.get('recent_dicom_accessed', '')
        dicom_info = result.get('dicom_info', '')

        if recent_dicom or dicom_info:
            criteria_met += 1
            feedback_parts.append(f"DICOM activity detected")
        else:
            feedback_parts.append("No DICOM loading detected")

    # Criterion 3: Specific DICOM file was accessed
    recent_dicom = result.get('recent_dicom_accessed', '')
    if recent_dicom:
        criteria_met += 1
        filename = os.path.basename(recent_dicom)
        feedback_parts.append(f"File accessed: {filename}")
    else:
        # Check dicom_info for alternative evidence
        dicom_info = result.get('dicom_info', '')
        if dicom_info and dicom_info != '{}':
            criteria_met += 1
            feedback_parts.append("DICOM metadata found")
        else:
            feedback_parts.append("No specific DICOM file identified")

    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 66  # Pass if 2 out of 3 criteria met

    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
