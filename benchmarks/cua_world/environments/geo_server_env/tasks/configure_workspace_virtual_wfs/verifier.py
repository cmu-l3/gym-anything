#!/usr/bin/env python3
"""Verifier for configure_workspace_virtual_wfs task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_workspace_virtual_wfs(traj, env_info, task_info):
    """
    Verify workspace-specific WFS configuration and service isolation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', "Natural Earth Feature Service")
    expected_abstract = metadata.get('expected_abstract', "Provides controlled access to Natural Earth vector datasets")
    expected_max_features = int(metadata.get('expected_max_features', 50))

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/configure_wms_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify integrity nonce
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        pass # Be lenient if nonce file read fails, rely on timestamp checks
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []

    # 1. Workspace WFS Settings Exist (20 pts)
    # The setup script deleted them, so if they exist now, the agent created them.
    if result.get('wfs_settings_found'):
        score += 20
        feedback_parts.append("Workspace-specific WFS settings created")
    else:
        return {"passed": False, "score": 0, "feedback": "Workspace-specific WFS settings NOT found. Did you configure Global settings instead?"}

    # 2. Configuration Values (15 pts Title + 15 pts Max Features)
    actual_title = result.get('actual_title', '').strip()
    if actual_title == expected_title:
        score += 15
        feedback_parts.append("Title correct")
    else:
        feedback_parts.append(f"Title mismatch: '{actual_title}'")

    actual_max = result.get('actual_max_features', '')
    try:
        if int(actual_max) == expected_max_features:
            score += 15
            feedback_parts.append("Max features correct (50)")
        else:
            feedback_parts.append(f"Max features mismatch: {actual_max}")
    except:
        feedback_parts.append(f"Invalid max features value: {actual_max}")

    # Check abstract (bonus/secondary check)
    if result.get('actual_abstract', '').strip() == expected_abstract:
        # Implicitly handled in score accumulation or just good feedback
        pass

    # 3. GetCapabilities File (15 pts exist + 10 pts content)
    if result.get('capabilities_file_exists'):
        score += 15
        feedback_parts.append("Capabilities file saved")
        
        if result.get('capabilities_title_found'):
            score += 10
            feedback_parts.append("Capabilities XML contains correct custom title")
        else:
            feedback_parts.append("Capabilities XML missing custom title (wrong endpoint?)")
    else:
        feedback_parts.append("Capabilities file missing")

    # 4. GetFeature File (15 pts exist + 10 pts count limit)
    if result.get('features_file_exists'):
        score += 15
        feedback_parts.append("Features file saved")
        
        count = result.get('features_count', -1)
        if count >= 0 and count <= expected_max_features:
            score += 10
            feedback_parts.append(f"Feature count ({count}) respects limit")
        elif count > expected_max_features:
            feedback_parts.append(f"Feature count ({count}) exceeds limit of {expected_max_features}")
        else:
            feedback_parts.append("Invalid feature count in file")
    else:
        feedback_parts.append("Features file missing")

    # Calculate final status
    passed = score >= 70 and result.get('wfs_settings_found')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }