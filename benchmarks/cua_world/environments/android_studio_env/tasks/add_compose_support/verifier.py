#!/usr/bin/env python3
"""
Verifier for add_compose_support task.

Checks:
1. app/build.gradle.kts configuration (30 pts)
   - buildFeatures { compose = true }
   - composeOptions { ... }
   - dependencies (bom, ui, material3, activity-compose)
2. ProfileScreen.kt created and valid (20 pts)
   - @Composable
   - @Preview
3. ProfileActivity.kt created and valid (20 pts)
   - ComponentActivity
   - setContent { ProfileScreen() }
4. AndroidManifest.xml (10 pts)
   - ProfileActivity registered
5. Build Success (20 pts)
   - ./gradlew assembleDebug returns 0
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_compose_support(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result JSON
    result = {}
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to load task result"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []

    # 1. Check Build Configuration (30 pts)
    bg_content = result.get("build_gradle_content", "")
    bg_points = 0
    
    # Check buildFeatures { compose = true }
    if re.search(r'buildFeatures\s*\{[^}]*compose\s*=\s*true', bg_content, re.DOTALL):
        bg_points += 10
        feedback.append("Build features: compose enabled (10/10)")
    else:
        feedback.append("Build features: compose NOT enabled (0/10)")

    # Check composeOptions
    if "composeOptions" in bg_content and "kotlinCompilerExtensionVersion" in bg_content:
        bg_points += 5
        feedback.append("Compose options configured (5/5)")
    else:
        feedback.append("Compose options missing (0/5)")

    # Check dependencies
    deps_found = 0
    required_deps = ["compose-bom", "ui", "material3", "activity-compose", "ui-tooling"]
    for dep in required_deps:
        if dep in bg_content:
            deps_found += 1
    
    if deps_found >= 4:
        bg_points += 15
        feedback.append(f"Dependencies found: {deps_found}/{len(required_deps)} (15/15)")
    else:
        bg_points += int((deps_found / 5) * 15)
        feedback.append(f"Dependencies incomplete: {deps_found}/{len(required_deps)}")
    
    score += bg_points

    # 2. Check ProfileScreen.kt (20 pts)
    ps_content = result.get("profile_screen_content", "")
    if ps_content:
        ps_points = 0
        if "@Composable" in ps_content:
            ps_points += 10
            feedback.append("ProfileScreen: @Composable found (10/10)")
        else:
            feedback.append("ProfileScreen: @Composable missing")
            
        if "fun ProfileScreen" in ps_content:
            ps_points += 5
        
        if "@Preview" in ps_content:
            ps_points += 5
            feedback.append("ProfileScreen: @Preview found (5/5)")
            
        score += ps_points
    else:
        feedback.append("ProfileScreen.kt not created (0/20)")

    # 3. Check ProfileActivity.kt (20 pts)
    pa_content = result.get("profile_activity_content", "")
    if pa_content:
        pa_points = 0
        if "ComponentActivity" in pa_content:
            pa_points += 10
            feedback.append("ProfileActivity: Extends ComponentActivity (10/10)")
        
        if "setContent" in pa_content and "ProfileScreen" in pa_content:
            pa_points += 10
            feedback.append("ProfileActivity: Calls setContent with ProfileScreen (10/10)")
        else:
            feedback.append("ProfileActivity: setContent/ProfileScreen call missing")
            
        score += pa_points
    else:
        feedback.append("ProfileActivity.kt not created (0/20)")

    # 4. Check AndroidManifest.xml (10 pts)
    manifest = result.get("manifest_content", "")
    if "ProfileActivity" in manifest:
        score += 10
        feedback.append("Manifest: ProfileActivity registered (10/10)")
    else:
        feedback.append("Manifest: ProfileActivity NOT registered (0/10)")

    # 5. Build Success (20 pts)
    if result.get("build_success", False):
        score += 20
        feedback.append("Build: SUCCESS (20/20)")
    else:
        feedback.append("Build: FAILED (0/20)")
        # Check if we should award partial credit if config looks good but maybe a tiny syntax error?
        # Anti-gaming: strict build success is safer. If it doesn't compile, it's not a valid app.

    return {
        "passed": score >= 60 and result.get("build_success", False),
        "score": score,
        "feedback": "\n".join(feedback)
    }