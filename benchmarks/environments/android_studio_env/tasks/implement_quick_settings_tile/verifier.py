#!/usr/bin/env python3
"""
Verifier for implement_quick_settings_tile task.

Scoring System (100 pts):
- Service Class Created (10 pts)
- Manifest Permission (20 pts)
- Manifest Intent Filter (20 pts)
- Manifest Metadata (10 pts)
- onClick Implementation (20 pts)
- State Management (10 pts)
- Build Success (10 pts)
"""

import json
import logging
import os
import re
import tempfile
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_quick_settings_tile(traj, env_info, task_info):
    """Verify the Quick Settings Tile implementation."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result data
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Extract data
    service_exists = result.get("service_exists", False)
    service_content = result.get("service_content", "")
    manifest_content = result.get("manifest_content", "")
    build_success = result.get("build_success", False)

    score = 0
    feedback_parts = []

    # 1. Service Class Created (10 pts)
    if service_exists and "class DemoModeTileService" in service_content and "TileService" in service_content:
        score += 10
        feedback_parts.append("Service class created (10/10)")
    elif service_exists:
        score += 5
        feedback_parts.append("Service file exists but class definition issues (5/10)")
    else:
        feedback_parts.append("Service file missing (0/10)")

    # 2. Manifest Verification
    if manifest_content:
        # Check permission (20 pts)
        if 'android.permission.BIND_QUICK_SETTINGS_TILE' in manifest_content:
            score += 20
            feedback_parts.append("Manifest permission correct (20/20)")
        else:
            feedback_parts.append("Missing BIND_QUICK_SETTINGS_TILE permission (0/20)")

        # Check intent filter (20 pts)
        if 'android.service.quicksettings.action.QS_TILE' in manifest_content:
            score += 20
            feedback_parts.append("Manifest intent filter correct (20/20)")
        else:
            feedback_parts.append("Missing QS_TILE intent filter (0/20)")

        # Check metadata (10 pts)
        # Look for the service tag being closed properly and containing label/icon attributes
        # Regex to find the specific service block is complex, simple string search for attributes near the service name is approximation
        # We'll just check if the service is defined and has attributes in the file generally, assuming mostly valid XML
        service_def_regex = r'<service[^>]*android:name="\.DemoModeTileService"[^>]*>'
        has_service_tag = re.search(service_def_regex, manifest_content)
        
        has_label = 'android:label="Demo Mode"' in manifest_content or 'android:label="@string' in manifest_content
        has_icon = 'android:icon=' in manifest_content
        
        if has_service_tag or ('DemoModeTileService' in manifest_content):
            if has_label and has_icon:
                score += 10
                feedback_parts.append("Manifest label/icon configured (10/10)")
            else:
                score += 5
                feedback_parts.append("Manifest service present but missing label/icon (5/10)")
        else:
            feedback_parts.append("Service not registered in Manifest (0/10)")
    else:
        feedback_parts.append("Manifest content empty (0/50)")

    # 3. Code Implementation Logic
    if service_content:
        # Check onClick (20 pts)
        has_onclick = 'override fun onClick' in service_content or 'override fun onClick' in service_content
        calls_update = 'updateTile()' in service_content
        toggles_prefs = 'PrefsManager' in service_content or 'getSharedPreferences' in service_content
        
        if has_onclick and calls_update and toggles_prefs:
            score += 20
            feedback_parts.append("onClick implementation correct (20/20)")
        elif has_onclick:
            score += 10
            feedback_parts.append("onClick exists but logic incomplete (10/20)")
        else:
            feedback_parts.append("onClick not overridden (0/20)")

        # Check State Management (10 pts)
        sets_active = 'STATE_ACTIVE' in service_content
        sets_inactive = 'STATE_INACTIVE' in service_content
        has_start_listening = 'onStartListening' in service_content
        
        if (sets_active or sets_inactive) and has_start_listening:
            score += 10
            feedback_parts.append("State management logic found (10/10)")
        else:
            feedback_parts.append("Missing state management or onStartListening (0/10)")
    
    # 4. Build Success (10 pts)
    if build_success:
        score += 10
        feedback_parts.append("Project builds successfully (10/10)")
    else:
        feedback_parts.append("Project build failed (0/10)")

    # 5. VLM / Anti-Gaming Check (Using Trajectory)
    # This is implicit in the "Service Exists" check which validates the file was created during the task
    # We could add VLM here to verify the IDE state, but code verification is robust enough for this coding task.
    # We will enforce a pass threshold.
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }