#!/usr/bin/env python3
"""
Verifier for implement_android12_splash_screen task.

Scoring Criteria (100 points total):
1. Dependency Added (20 pts): `androidx.core:core-splashscreen` in build.gradle.kts
2. Splash Theme Created (25 pts): 
   - Exists in themes.xml
   - Parent is `Theme.SplashScreen`
   - Attributes (icon, background, postTheme) set
3. Manifest Updated (15 pts): Uses the splash theme
4. Kotlin Code Updated (15 pts): `installSplashScreen()` called in MainActivity
5. Build Success (25 pts): Project compiles successfully

Pass Threshold: 70 points
"""

import json
import logging
import os
import re
import tempfile
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_android12_splash_screen(traj, env_info, task_info):
    """Verify that Android 12 Splash Screen implementation is correct."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed"}

    # Load result from export_result.sh
    result_data = {}
    tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            content = f.read()
            if content.strip():
                result_data = json.loads(content)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(tmp_result.name):
            os.unlink(tmp_result.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    build_success = result_data.get("build_success", False)
    build_gradle = result_data.get("build_gradle_content", "")
    themes_xml = result_data.get("themes_xml_content", "")
    manifest_xml = result_data.get("manifest_content", "")
    main_activity = result_data.get("main_activity_content", "")

    # Criterion 1: Dependency Check (20 pts)
    # Looking for implementation("androidx.core:core-splashscreen:...") or implementation "androidx.core:core-splashscreen:..."
    dep_pattern = r'implementation\s*\(?\s*["\']androidx\.core:core-splashscreen'
    if re.search(dep_pattern, build_gradle):
        score += 20
        feedback_parts.append("Dependency added (20/20)")
    else:
        feedback_parts.append("Dependency missing in build.gradle.kts (0/20)")

    # Criterion 2: Splash Theme Definition (25 pts)
    theme_valid = False
    attributes_found = []
    
    if themes_xml:
        try:
            # Simple XML parsing to find style
            root = ET.fromstring(themes_xml)
            # Handle potential namespaces
            namespaces = {'android': 'http://schemas.android.com/apk/res/android'}
            
            # Find the style
            splash_style = None
            for style in root.findall('style'):
                name = style.get('name', '')
                if 'Theme.App.Starting' in name:
                    splash_style = style
                    break
            
            if splash_style is not None:
                parent = splash_style.get('parent', '')
                if 'Theme.SplashScreen' in parent:
                    theme_valid = True
                    
                    # Check items
                    items = {item.get('name'): item.text for item in splash_style.findall('item')}
                    
                    if 'windowSplashScreenBackground' in items:
                        attributes_found.append("background")
                    if 'windowSplashScreenAnimatedIcon' in items:
                        attributes_found.append("icon")
                    if 'postSplashScreenTheme' in items:
                        attributes_found.append("postTheme")
            else:
                feedback_parts.append("Theme.App.Starting style not found")

        except ET.ParseError:
            feedback_parts.append("Error parsing themes.xml")

    if theme_valid:
        base_theme_score = 10
        attr_score = min(15, len(attributes_found) * 5)
        score += (base_theme_score + attr_score)
        feedback_parts.append(f"Splash theme valid with {len(attributes_found)} attributes ({base_theme_score + attr_score}/25)")
    else:
        feedback_parts.append("Splash theme definition invalid or missing parent (0/25)")

    # Criterion 3: Manifest Update (15 pts)
    # Check if android:theme points to Theme.App.Starting
    if 'android:theme="@style/Theme.App.Starting"' in manifest_xml:
        score += 15
        feedback_parts.append("Manifest theme updated (15/15)")
    else:
        feedback_parts.append("Manifest does not use Theme.App.Starting (0/15)")

    # Criterion 4: Kotlin Code (15 pts)
    # Check for installSplashScreen() import and call
    code_valid = False
    if 'installSplashScreen()' in main_activity:
        code_valid = True
    
    if code_valid:
        score += 15
        feedback_parts.append("installSplashScreen() called (15/15)")
    else:
        feedback_parts.append("installSplashScreen() call missing in MainActivity (0/15)")

    # Criterion 5: Build Success (25 pts)
    if build_success:
        score += 25
        feedback_parts.append("Build successful (25/25)")
    else:
        # Partial credit if code structure looks mostly correct but build failed?
        # No, strict on build for this task as XML errors are common
        feedback_parts.append("Build failed (0/25)")

    # Final result
    passed = score >= 70 and build_success
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }