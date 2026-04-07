#!/usr/bin/env python3
"""
Verifier for PWA Workspace Provisioning task.

Criteria:
1. Photopea installed as PWA (30 points)
2. Excalidraw installed as PWA (30 points)
3. DevDocs installed as PWA (30 points)
4. Clean naming convention used (10 points)

Pass threshold: 65 points
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pwa_provisioning(traj, env_info, task_info):
    """
    Verify that the requested PWAs were installed correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available from framework"
        }

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read task result: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    apps = result.get("apps", {})
    
    # 1. Check Photopea (30 pts)
    photopea = apps.get("photopea", {})
    if photopea.get("installed") and photopea.get("is_valid_pwa"):
        score += 30
        feedback_parts.append("Photopea installed successfully")
    elif photopea.get("installed"):
        score += 15 # Partial credit if file exists but maybe not strictly PWA format
        feedback_parts.append("Photopea shortcut found but PWA config unclear")
    else:
        feedback_parts.append("Photopea not found")

    # 2. Check Excalidraw (30 pts)
    excalidraw = apps.get("excalidraw", {})
    if excalidraw.get("installed") and excalidraw.get("is_valid_pwa"):
        score += 30
        feedback_parts.append("Excalidraw installed successfully")
    elif excalidraw.get("installed"):
        score += 15
        feedback_parts.append("Excalidraw shortcut found but PWA config unclear")
    else:
        feedback_parts.append("Excalidraw not found")

    # 3. Check DevDocs (30 pts)
    devdocs = apps.get("devdocs", {})
    if devdocs.get("installed") and devdocs.get("is_valid_pwa"):
        score += 30
        feedback_parts.append("DevDocs installed successfully")
    elif devdocs.get("installed"):
        score += 15
        feedback_parts.append("DevDocs shortcut found but PWA config unclear")
    else:
        feedback_parts.append("DevDocs not found")

    # 4. Check Naming (10 pts)
    # Require at least 2 apps to be installed to check naming
    installed_count = sum(1 for a in [photopea, excalidraw, devdocs] if a.get("installed"))
    if installed_count >= 2:
        naming_score = 0
        clean_names = ["Photopea", "Excalidraw", "DevDocs"]
        
        # Check if names are reasonably clean (not full titles like "Photopea | Online Photo Editor")
        # We'll be lenient: pass if the name matches the short name exactly (case insensitive)
        p_name = photopea.get("name_found", "").strip()
        e_name = excalidraw.get("name_found", "").strip()
        d_name = devdocs.get("name_found", "").strip()
        
        clean_count = 0
        if photopea.get("installed") and p_name.lower() == "photopea": clean_count += 1
        if excalidraw.get("installed") and e_name.lower() == "excalidraw": clean_count += 1
        if devdocs.get("installed") and d_name.lower() == "devdocs": clean_count += 1
        
        if clean_count >= 2:
            score += 10
            feedback_parts.append("App naming convention followed")
        elif clean_count > 0:
            score += 5
            feedback_parts.append("Partial compliance with naming convention")
        else:
            feedback_parts.append("Default app names used (not cleaned)")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }