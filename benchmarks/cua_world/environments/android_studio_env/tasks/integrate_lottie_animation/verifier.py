#!/usr/bin/env python3
"""
Verifier for integrate_lottie_animation task.

Criteria:
1. Lottie dependency added to build.gradle (20 pts)
2. JSON asset imported to res/raw/ (20 pts)
3. LottieAnimationView present in layout XML (20 pts)
4. Layout references the correct raw resource (15 pts)
5. Animation configured to loop (10 pts)
6. Project builds successfully (15 pts)

Total: 100 pts
Pass Threshold: 75 pts
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_integrate_lottie_animation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # Load result JSON
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Dependency Check
    build_gradle = result.get("build_gradle_content", "")
    # Check for com.airbnb.android:lottie
    if re.search(r'com\.airbnb\.android:lottie', build_gradle):
        score += 20
        feedback.append("Lottie dependency found.")
    else:
        feedback.append("Lottie dependency MISSING in build.gradle.")

    # 2. Asset Import Check
    if result.get("raw_asset_exists", False):
        score += 20
        feedback.append("Animation asset found in res/raw.")
    else:
        feedback.append("Animation asset MISSING in res/raw.")

    # 3. XML View Check
    layout_xml = result.get("layout_xml_content", "")
    if "com.airbnb.lottie.LottieAnimationView" in layout_xml:
        score += 20
        feedback.append("LottieAnimationView found in layout.")
        
        # 4. Resource Reference Check
        # Expecting app:lottie_rawRes="@raw/android_wave" or similar
        if re.search(r'lottie_rawRes="?@raw/android_wave"?', layout_xml):
            score += 15
            feedback.append("Correct raw resource referenced.")
        else:
            feedback.append("Incorrect or missing lottie_rawRes attribute.")
            
        # 5. Loop Configuration Check
        # Expecting lottie_loop="true" OR lottie_autoPlay="true" (often autoPlay implies loop intent in simple tasks, but let's stick to loop or check both)
        if re.search(r'lottie_loop="?true"?', layout_xml) or re.search(r'lottie_autoPlay="?true"?', layout_xml):
            score += 10
            feedback.append("Loop/AutoPlay enabled.")
        else:
            feedback.append("Loop/AutoPlay NOT enabled.")
            
    else:
        feedback.append("LottieAnimationView MISSING in layout.")

    # 6. Build Check
    if result.get("build_success", False):
        score += 15
        feedback.append("Project built successfully.")
    else:
        feedback.append("Project build FAILED.")

    # VLM Check (Secondary)
    # We'll rely on programmatic checks primarily, but could add VLM here if needed.
    # For now, sticking to robust file/build checks.

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " ".join(feedback)
    }