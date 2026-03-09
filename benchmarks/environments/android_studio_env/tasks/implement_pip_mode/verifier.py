#!/usr/bin/env python3
"""
Verifier for implement_pip_mode task.

Requirements to pass:
1. AndroidManifest.xml:
   - supportsPictureInPicture="true"
   - configChanges includes: screenSize, smallestScreenSize, screenLayout, orientation
2. PlayerActivity.kt:
   - Overrides onUserLeaveHint
   - Calls enterPictureInPictureMode
   - Sets aspect ratio (Rational)
   - Overrides onPictureInPictureModeChanged (or onConfigurationChanged)
   - Toggles visibility of closeButton
3. Project compiles successfully.
"""

import json
import logging
import re
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_pip_mode(traj, env_info, task_info):
    """Verify implementation of PiP mode in Android Studio."""
    
    # Setup copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment error: copy_from_env missing"}

    # Load result JSON
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # Extract data
    manifest_content = result.get("manifest_content", "")
    activity_content = result.get("activity_content", "")
    build_success = result.get("build_success", False)
    manifest_modified = result.get("manifest_modified", False)
    activity_modified = result.get("activity_modified", False)

    score = 0
    feedback = []

    # --- 1. Manifest Verification (40 pts) ---
    
    # Check supportsPictureInPicture
    if 'android:supportsPictureInPicture="true"' in manifest_content:
        score += 20
        feedback.append("Manifest: PiP support enabled (20/20)")
    else:
        feedback.append("Manifest: PiP support missing or false (0/20)")

    # Check configChanges
    # Must contain at least the 4 critical ones to prevent restart
    required_configs = ["screenSize", "smallestScreenSize", "screenLayout", "orientation"]
    
    # Regex to find configChanges attribute inside PlayerActivity tag
    # Simplified check: just look for the string in the file, assuming it's applied to the correct activity 
    # (since there's only one main editable activity)
    config_match = re.search(r'android:configChanges="([^"]+)"', manifest_content)
    
    if config_match:
        configs = config_match.group(1)
        missing_configs = [c for c in required_configs if c not in configs]
        if not missing_configs:
            score += 20
            feedback.append("Manifest: configChanges correct (20/20)")
        else:
            score += 5 # Partial credit for having attribute
            feedback.append(f"Manifest: configChanges missing {missing_configs} (5/20)")
    else:
        feedback.append("Manifest: configChanges attribute missing (0/20)")

    # --- 2. Activity Logic Verification (50 pts) ---

    # Check onUserLeaveHint
    if "onUserLeaveHint" in activity_content:
        score += 10
        feedback.append("Activity: onUserLeaveHint overridden (10/10)")
    else:
        feedback.append("Activity: onUserLeaveHint missing (0/10)")

    # Check enterPictureInPictureMode call
    if "enterPictureInPictureMode" in activity_content:
        score += 15
        feedback.append("Activity: enterPictureInPictureMode called (15/15)")
    else:
        feedback.append("Activity: enterPictureInPictureMode call missing (0/15)")

    # Check Aspect Ratio (Rational)
    if "Rational" in activity_content or "PictureInPictureParams.Builder" in activity_content:
        score += 10
        feedback.append("Activity: Aspect ratio/Params builder usage detected (10/10)")
    else:
        feedback.append("Activity: Aspect ratio configuration not detected (0/10)")

    # Check UI Adaptation (onPictureInPictureModeChanged + View visibility)
    # Looking for onPictureInPictureModeChanged OR onConfigurationChanged
    has_pip_change = "onPictureInPictureModeChanged" in activity_content
    has_config_change = "onConfigurationChanged" in activity_content
    
    # Looking for visibility toggles (GONE/VISIBLE or INVISIBLE)
    has_visibility = re.search(r'visibility\s*=\s*(View\.)?(GONE|INVISIBLE|VISIBLE)', activity_content)
    
    if (has_pip_change or has_config_change) and has_visibility:
        score += 15
        feedback.append("Activity: UI adaptation logic detected (15/15)")
    elif (has_pip_change or has_config_change):
        score += 5
        feedback.append("Activity: Lifecycle method present but visibility change unclear (5/15)")
    else:
        feedback.append("Activity: PiP mode change listener missing (0/15)")

    # --- 3. Build Verification (10 pts) ---
    if build_success:
        score += 10
        feedback.append("Build: Success (10/10)")
    else:
        feedback.append("Build: Failed or not attempted (0/10)")

    # --- Anti-gaming check ---
    if not manifest_modified or not activity_modified:
        feedback.append("WARNING: Files not modified. 'Do Nothing' detected.")
        if score > 0:
            score = 0 # Fail if no work done

    passed = score >= 75 and build_success
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }