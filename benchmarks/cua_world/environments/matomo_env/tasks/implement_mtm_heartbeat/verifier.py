#!/usr/bin/env python3
"""
Verifier for MTM Heartbeat task.

Checks:
1. Container existence (20 pts)
2. Version published (20 pts)
3. Matomo Configuration Variable existence (20 pts)
4. Heartbeat enabled (20 pts)
5. Heartbeat interval == 15 (20 pts)

Pass threshold: 80 points (Must have heartbeat enabled in a published version).
"""

import json
import logging
import os
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_mtm_heartbeat(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_interval = metadata.get('expected_heartbeat_seconds', 15)

    # Retrieve result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/mtm_heartbeat_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve/parse result: {str(e)}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Container Exists
    if result.get('container_found'):
        score += 20
        feedback_parts.append("Container found")
    else:
        return {"passed": False, "score": 0, "feedback": "No container found for Site 1"}

    # 2. Version Published
    published_id = result.get('published_version_id')
    content = result.get('published_content', {})
    
    if published_id and published_id != "NULL" and content:
        score += 20
        feedback_parts.append(f"Version published (ID: {published_id})")
    else:
        feedback_parts.append("No version published (still in draft?)")
        # Critical failure if not published
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts) + ". Task requires PUBLISHING the container."
        }

    # 3. Analyze JSON Content for Variables
    variables = content.get('variables', [])
    matomo_config_var = None
    
    # Find variable of type 'MatomoConfiguration'
    for var in variables:
        if var.get('type') == 'MatomoConfiguration':
            matomo_config_var = var
            break
            
    if matomo_config_var:
        score += 20
        feedback_parts.append("Matomo Configuration variable found")
        
        # 4. Check Heartbeat
        # Parameters are usually in 'parameters' dict
        params = matomo_config_var.get('parameters', {})
        
        # The parameter name for heartbeat is 'heartbeatTimer'
        # It might be a string or int
        heartbeat_val = params.get('heartbeatTimer')
        
        if heartbeat_val:
            score += 20
            feedback_parts.append("Heartbeat timer enabled")
            
            # 5. Check Value
            try:
                val_int = int(float(heartbeat_val))
                if val_int == expected_interval:
                    score += 20
                    feedback_parts.append(f"Interval correct ({val_int}s)")
                else:
                    feedback_parts.append(f"Interval incorrect (found {val_int}s, expected {expected_interval}s)")
            except ValueError:
                feedback_parts.append(f"Invalid interval value: {heartbeat_val}")
        else:
            feedback_parts.append("Heartbeat timer NOT enabled in config")
            
    else:
        feedback_parts.append("Matomo Configuration variable NOT found in published version")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }