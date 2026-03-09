#!/usr/bin/env python3
"""
Verifier for migrate_kapt_to_ksp task.

Verification Criteria:
1. Project-level build.gradle.kts has KSP plugin declared (id + version).
2. App-level build.gradle.kts applies KSP plugin.
3. App-level build.gradle.kts removes KAPT plugin.
4. App-level dependencies use ksp(...) for Room.
5. App-level kapt {...} block is removed.
6. Project builds successfully.
7. Anti-gaming: Files must have changed.
"""

import json
import logging
import re
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_migrate_kapt_to_ksp(traj, env_info, task_info):
    """Verify migration from KAPT to KSP."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp_result.name):
            os.unlink(tmp_result.name)

    project_gradle = result.get('project_gradle_content', '')
    app_gradle = result.get('app_gradle_content', '')
    build_success = result.get('build_success', False)
    checksums_changed = result.get('checksums_changed', False)
    ksp_tasks_ran = result.get('ksp_tasks_ran', False)
    kapt_tasks_ran = result.get('kapt_tasks_ran', False)

    score = 0
    feedback_parts = []
    
    if not checksums_changed:
        return {"passed": False, "score": 0, "feedback": "No changes detected in build files."}

    # Criterion 1: KSP Plugin Declared at Project Level (15 pts)
    # Looking for: id("com.google.devtools.ksp") version "..." apply false
    # Regex allows for variation in quotes and spacing
    ksp_declared = re.search(r'id\s*\(\s*["\']com\.google\.devtools\.ksp["\']\s*\)\s*version', project_gradle)
    if ksp_declared:
        score += 15
        feedback_parts.append("KSP plugin declared in root build.gradle.kts (+15)")
    else:
        feedback_parts.append("KSP plugin NOT declared in root build.gradle.kts")

    # Criterion 2: KSP Plugin Applied at App Level (15 pts)
    ksp_applied = re.search(r'id\s*\(\s*["\']com\.google\.devtools\.ksp["\']\s*\)', app_gradle)
    if ksp_applied:
        score += 15
        feedback_parts.append("KSP plugin applied in app build.gradle.kts (+15)")
    else:
        feedback_parts.append("KSP plugin NOT applied in app build.gradle.kts")

    # Criterion 3: KAPT Plugin Removed (15 pts)
    kapt_plugin_present = re.search(r'id\s*\(\s*["\']org\.jetbrains\.kotlin\.kapt["\']\s*\)', app_gradle) or \
                          re.search(r'id\s*\(\s*["\']kotlin-kapt["\']\s*\)', app_gradle)
    if not kapt_plugin_present:
        score += 15
        feedback_parts.append("KAPT plugin removed from app build.gradle.kts (+15)")
    else:
        feedback_parts.append("KAPT plugin still present in app build.gradle.kts")

    # Criterion 4: Room Compiler Uses KSP (20 pts)
    # Looking for: ksp("androidx.room:room-compiler:...")
    room_ksp = re.search(r'ksp\s*\(\s*["\']androidx\.room:room-compiler', app_gradle)
    room_kapt = re.search(r'kapt\s*\(\s*["\']androidx\.room:room-compiler', app_gradle)
    
    if room_ksp and not room_kapt:
        score += 20
        feedback_parts.append("Room compiler dependency migrated to KSP (+20)")
    elif room_ksp and room_kapt:
        score += 10
        feedback_parts.append("Room compiler uses KSP but KAPT dependency still present (+10)")
    else:
        feedback_parts.append("Room compiler not migrated to KSP")

    # Criterion 5: KAPT Config Block Removed (10 pts)
    kapt_block = re.search(r'kapt\s*\{', app_gradle)
    if not kapt_block:
        score += 10
        feedback_parts.append("Residual kapt configuration block removed (+10)")
    else:
        feedback_parts.append("Residual kapt configuration block found")

    # Criterion 6: Build Success (25 pts)
    if build_success:
        score += 25
        feedback_parts.append("Project build successful (+25)")
    else:
        feedback_parts.append("Project build failed")

    # Bonus consistency check
    if ksp_tasks_ran and not kapt_tasks_ran:
        feedback_parts.append("(Build logs confirm KSP ran and KAPT did not)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }