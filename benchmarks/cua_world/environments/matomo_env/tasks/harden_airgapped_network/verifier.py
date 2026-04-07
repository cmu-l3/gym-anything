#!/usr/bin/env python3
"""
Verifier for Harden Air-gapped Network task.

Task: Disable internet features, marketplace, and update checks in Matomo config.

Scoring (100 points):
- enable_internet_features = 0 (30 pts)
- enable_marketplace = 0 (30 pts)
- enable_update_communication = 0 (30 pts)
- File modified during task (10 pts)

Pass threshold: 90 points (Strict adherence required for security tasks)
"""

import json
import logging
import os
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_harden_airgapped_network(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/harden_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback_parts = []
    
    config_values = result.get('config_values', {})
    modified_during_task = result.get('modified_during_task', False)
    file_exists = result.get('file_exists', False)

    if not file_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Configuration file not found. Ensure you didn't delete config.ini.php."
        }

    # Helper to check value is "0"
    def is_disabled(val):
        return str(val).strip() == "0"

    # Criterion 1: enable_internet_features (30 pts)
    val_internet = config_values.get('enable_internet_features', '1') # Default is 1
    if is_disabled(val_internet):
        score += 30
        feedback_parts.append("Internet features disabled correctly")
    else:
        feedback_parts.append(f"enable_internet_features is '{val_internet}' (expected 0)")

    # Criterion 2: enable_marketplace (30 pts)
    val_market = config_values.get('enable_marketplace', '1')
    if is_disabled(val_market):
        score += 30
        feedback_parts.append("Marketplace disabled correctly")
    else:
        feedback_parts.append(f"enable_marketplace is '{val_market}' (expected 0)")

    # Criterion 3: enable_update_communication (30 pts)
    # Also accept enable_auto_update as a partial credit fallback if strictly needed, 
    # but the task specified "communication", so prefer that.
    val_update = config_values.get('enable_update_communication', '1')
    if is_disabled(val_update):
        score += 30
        feedback_parts.append("Update communication disabled correctly")
    else:
        feedback_parts.append(f"enable_update_communication is '{val_update}' (expected 0)")

    # Criterion 4: Anti-gaming check (10 pts)
    if modified_during_task:
        score += 10
        feedback_parts.append("File modified during task")
    else:
        feedback_parts.append("File NOT modified during task (timestamps match start time)")

    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }