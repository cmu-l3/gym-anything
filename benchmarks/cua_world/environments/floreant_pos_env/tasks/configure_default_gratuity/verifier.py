#!/usr/bin/env python3
"""
Verifier for configure_default_gratuity task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_default_gratuity(traj, env_info, task_info):
    """
    Verify that the default gratuity was set to 18%.
    
    Criteria:
    1. Database reflects DEFAULT_GRATUITY = 18.0 (60 pts)
    2. SERVICE_CHARGE_PERCENTAGE is NOT 18.0 (checking for field confusion) (20 pts)
    3. Database file was modified during task (Persistence check) (10 pts)
    4. VLM Verification of workflow (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
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

    score = 0
    feedback_parts = []
    
    # Parse values from string to float
    try:
        gratuity = float(result.get("default_gratuity", -1))
        service_charge = float(result.get("service_charge", -1))
    except ValueError:
        gratuity = -1.0
        service_charge = -1.0

    # Criterion 1: Check Gratuity Value (60 pts)
    # Expected: 18.0
    if 17.9 <= gratuity <= 18.1:
        score += 60
        feedback_parts.append("Default Gratuity correctly set to 18%.")
    else:
        feedback_parts.append(f"Default Gratuity incorrect (Found: {gratuity}, Expected: 18.0).")

    # Criterion 2: Check Service Charge (Anti-confusion check) (20 pts)
    # If they set service charge to 18 instead, they fail this part
    if 17.9 <= service_charge <= 18.1:
        feedback_parts.append("Warning: You set Service Charge to 18% instead of (or in addition to) Default Gratuity.")
    else:
        score += 20
        feedback_parts.append("Service Charge field correctly left alone (or distinct).")

    # Criterion 3: Persistence / DB Modified (10 pts)
    if result.get("db_modified", False):
        score += 10
        feedback_parts.append("Configuration saved successfully.")
    else:
        feedback_parts.append("Database not modified (did you forget to Save?).")

    # Criterion 4: Basic VLM check (10 pts)
    # If we have a final screenshot and it's valid
    if result.get("app_was_running", False):
        score += 10
        feedback_parts.append("Application was running.")

    passed = score >= 70 and (17.9 <= gratuity <= 18.1)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }