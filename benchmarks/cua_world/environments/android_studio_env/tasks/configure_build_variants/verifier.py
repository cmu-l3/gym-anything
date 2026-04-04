#!/usr/bin/env python3
"""
Verifier for configure_build_variants task.

The agent must configure build variants for CalculatorApp:
1. Add flavorDimensions "tier" with "free" and "premium" flavors
2. Add "staging" build type
3. Set applicationIdSuffix per flavor
4. Create flavor-specific resource directories and strings.xml
5. Project compiles

Scoring (100 points total):
- flavorDimensions and productFlavors in build.gradle.kts: 20 pts
- staging build type in build.gradle.kts: 10 pts
- applicationIdSuffix for flavors: 10 pts
- free flavor source set with strings.xml: 10 pts
- premium flavor source set with strings.xml: 10 pts
- Different app_name per flavor: 10 pts
- Project compiles: 30 pts

Pass threshold: 70/100
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _read_text(copy_from_env, path):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
    try:
        copy_from_env(path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    except Exception:
        return ""
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)


def _read_json(copy_from_env, path):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)


def verify_configure_build_variants(traj, env_info, task_info):
    """Verify build variants are properly configured."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/AndroidStudioProjects/CalculatorApp')

    build_gradle = _read_text(copy_from_env, f"{project_dir}/app/build.gradle.kts")
    free_strings = _read_text(copy_from_env, f"{project_dir}/app/src/free/res/values/strings.xml")
    premium_strings = _read_text(copy_from_env, f"{project_dir}/app/src/premium/res/values/strings.xml")

    result = _read_json(copy_from_env, "/tmp/task_result.json")
    if not build_gradle: build_gradle = result.get('build_gradle_content', '')
    if not free_strings: free_strings = result.get('free_strings_content', '')
    if not premium_strings: premium_strings = result.get('premium_strings_content', '')

    score = 0
    feedback = []

    # GATE: if build.gradle not changed, no work done
    if not result.get('build_gradle_changed', False) and 'flavorDimensions' not in build_gradle:
        return {"passed": False, "score": 0, "feedback": "No changes to build configuration"}

    # ================================================================
    # Criterion 1: flavorDimensions and productFlavors (20 pts)
    # ================================================================
    try:
        has_flavor_dimensions = bool(re.search(r'flavorDimensions', build_gradle))
        has_tier = bool(re.search(r'["\']tier["\']', build_gradle))
        has_free = bool(re.search(r'free\s*\{', build_gradle) or re.search(r'create\s*\(\s*["\']free["\']', build_gradle))
        has_premium = bool(re.search(r'premium\s*\{', build_gradle) or re.search(r'create\s*\(\s*["\']premium["\']', build_gradle))
        has_product_flavors = bool(re.search(r'productFlavors', build_gradle))

        f_score = 0
        if has_flavor_dimensions and has_tier: f_score += 8
        if has_product_flavors: f_score += 2
        if has_free: f_score += 5
        if has_premium: f_score += 5

        score += min(f_score, 20)
        feedback.append(f"Flavors: ({min(f_score, 20)}/20)")
    except Exception as e:
        feedback.append(f"Flavors: error ({e}) (0/20)")

    # ================================================================
    # Criterion 2: staging build type (10 pts)
    # ================================================================
    try:
        has_staging = bool(
            re.search(r'staging\s*\{', build_gradle) or
            re.search(r'create\s*\(\s*["\']staging["\']', build_gradle)
        )
        has_build_types = bool(re.search(r'buildTypes', build_gradle))

        if has_staging:
            score += 10
            feedback.append("Staging: found (10/10)")
        elif has_build_types and result.get('build_gradle_changed', False):
            score += 3
            feedback.append("Staging: buildTypes modified but no staging (3/10)")
        else:
            feedback.append("Staging: not found (0/10)")
    except Exception as e:
        feedback.append(f"Staging: error ({e}) (0/10)")

    # ================================================================
    # Criterion 3: applicationIdSuffix per flavor (10 pts)
    # ================================================================
    try:
        has_free_suffix = bool(re.search(r'applicationIdSuffix\s*=\s*["\']\.free["\']', build_gradle))
        has_premium_suffix = bool(re.search(r'applicationIdSuffix\s*=\s*["\']\.premium["\']', build_gradle))

        if has_free_suffix and has_premium_suffix:
            score += 10
            feedback.append("AppIdSuffix: both flavors (10/10)")
        elif has_free_suffix or has_premium_suffix:
            score += 5
            feedback.append("AppIdSuffix: one flavor (5/10)")
        else:
            feedback.append("AppIdSuffix: not found (0/10)")
    except Exception as e:
        feedback.append(f"AppIdSuffix: error ({e}) (0/10)")

    # ================================================================
    # Criterion 4: free source set (10 pts)
    # ================================================================
    try:
        if free_strings:
            has_app_name = bool(re.search(r'app_name', free_strings))
            if has_app_name:
                score += 10
                feedback.append("Free res: strings.xml with app_name (10/10)")
            else:
                score += 5
                feedback.append("Free res: strings.xml but no app_name (5/10)")
        elif result.get('free_res_exists', False):
            score += 3
            feedback.append("Free res: directory exists (3/10)")
        else:
            feedback.append("Free res: not found (0/10)")
    except Exception as e:
        feedback.append(f"Free res: error ({e}) (0/10)")

    # ================================================================
    # Criterion 5: premium source set (10 pts)
    # ================================================================
    try:
        if premium_strings:
            has_app_name = bool(re.search(r'app_name', premium_strings))
            if has_app_name:
                score += 10
                feedback.append("Premium res: strings.xml with app_name (10/10)")
            else:
                score += 5
                feedback.append("Premium res: strings.xml but no app_name (5/10)")
        elif result.get('premium_res_exists', False):
            score += 3
            feedback.append("Premium res: directory exists (3/10)")
        else:
            feedback.append("Premium res: not found (0/10)")
    except Exception as e:
        feedback.append(f"Premium res: error ({e}) (0/10)")

    # ================================================================
    # Criterion 6: different app_name per flavor (10 pts)
    # ================================================================
    try:
        free_name = ""
        premium_name = ""
        if free_strings:
            m = re.search(r'<string\s+name="app_name">(.*?)</string>', free_strings)
            if m: free_name = m.group(1)
        if premium_strings:
            m = re.search(r'<string\s+name="app_name">(.*?)</string>', premium_strings)
            if m: premium_name = m.group(1)

        if free_name and premium_name and free_name != premium_name:
            score += 10
            feedback.append(f"App names differ: '{free_name}' vs '{premium_name}' (10/10)")
        elif free_name or premium_name:
            score += 5
            feedback.append("App names: only one flavor has custom name (5/10)")
        else:
            feedback.append("App names: no custom names (0/10)")
    except Exception as e:
        feedback.append(f"App names: error ({e}) (0/10)")

    # ================================================================
    # Criterion 7: Project compiles (30 pts)
    # ================================================================
    try:
        build_success = result.get('build_success', False)
        if not build_success:
            gradle_log = _read_text(copy_from_env, "/tmp/gradle_output.log")
            if gradle_log and "BUILD SUCCESSFUL" in gradle_log:
                build_success = True

        if build_success:
            score += 30
            feedback.append("Build: succeeded (30/30)")
        else:
            feedback.append("Build: failed (0/30)")
    except Exception as e:
        feedback.append(f"Build: error ({e}) (0/30)")

    passed = score >= 70

    return {
        "passed": bool(passed),
        "score": int(score),
        "feedback": " | ".join(feedback)
    }
