#!/usr/bin/env python3
"""
Verifier for implement_runtime_permission task.

Checks:
1. Manifest contains <uses-permission android:name="android.permission.CAMERA" />
2. MainActivity uses ActivityResultContracts.RequestPermission (Modern API)
3. MainActivity uses registerForActivityResult
4. MainActivity checks permission (checkSelfPermission)
5. Project compiles successfully
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_runtime_permission(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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
    
    # Extract data
    manifest_content = result.get('manifest_content', '')
    activity_content = result.get('activity_content', '')
    build_success = result.get('build_success', False)
    
    # 1. Manifest Verification (20 pts)
    # Check for CAMERA permission
    if re.search(r'uses-permission.*android\.permission\.CAMERA', manifest_content):
        score += 20
        feedback_parts.append("Manifest: Camera permission declared (+20)")
    else:
        feedback_parts.append("Manifest: Camera permission MISSING (0)")

    # 2. Modern API Usage (25 pts)
    # Check for ActivityResultContracts.RequestPermission
    if 'ActivityResultContracts.RequestPermission' in activity_content:
        score += 25
        feedback_parts.append("Activity: Modern RequestPermission contract used (+25)")
    else:
        feedback_parts.append("Activity: Modern RequestPermission contract NOT found (0)")

    # 3. Registration Check (10 pts)
    if 'registerForActivityResult' in activity_content:
        score += 10
        feedback_parts.append("Activity: registerForActivityResult used (+10)")
    else:
        feedback_parts.append("Activity: registerForActivityResult NOT found (0)")

    # 4. Permission Check Logic (15 pts)
    # Check if checkSelfPermission is used or ContextCompat.checkSelfPermission
    if 'checkSelfPermission' in activity_content:
        score += 15
        feedback_parts.append("Activity: Permission check logic found (+15)")
    else:
        feedback_parts.append("Activity: Permission check logic (checkSelfPermission) NOT found (0)")

    # 5. Build Success (30 pts)
    if build_success:
        score += 30
        feedback_parts.append("Build: Compilation successful (+30)")
    else:
        feedback_parts.append("Build: Compilation FAILED (0)")

    # Final logic
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }