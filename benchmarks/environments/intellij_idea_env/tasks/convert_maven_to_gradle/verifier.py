#!/usr/bin/env python3
"""
Verifier for convert_maven_to_gradle task.

Criteria:
1. Files exist (build.gradle, settings.gradle)
2. settings.gradle contains project name
3. build.gradle contains correct plugins, repositories, and java version
4. build.gradle contains all 5 required dependencies with correct scopes
5. Gradle build actually succeeds (compiled, tested, jarred)
6. Anti-gaming: File created during task
7. VLM: Agent verified using IntelliJ
"""

import json
import tempfile
import os
import re
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_convert_maven_to_gradle(traj, env_info, task_info):
    """Verify conversion from Maven to Gradle."""
    
    # 1. Setup & Read Result
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    metadata = task_info.get('metadata', {})
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Files Exist (10 pts) ---
    if result.get('build_gradle_exists'):
        score += 5
    else:
        feedback_parts.append("Missing build.gradle")
        
    if result.get('settings_gradle_exists'):
        score += 5
    else:
        feedback_parts.append("Missing settings.gradle")

    bg_content = result.get('build_gradle_content', '')
    sg_content = result.get('settings_gradle_content', '')

    # --- Criterion 2: settings.gradle content (5 pts) ---
    expected_name = metadata.get('expected_project_name', 'data-utils')
    if f"rootProject.name" in sg_content and expected_name in sg_content:
        score += 5
    elif expected_name in sg_content:
        score += 3
        feedback_parts.append("Project name in settings.gradle format issue")
    else:
        feedback_parts.append("Project name not found in settings.gradle")

    # --- Criterion 3: build.gradle basics (15 pts) ---
    # Java Plugin
    if "plugin" in bg_content and "java" in bg_content:
        score += 5
    else:
        feedback_parts.append("Java plugin not applied")

    # Repositories
    if "mavenCentral" in bg_content:
        score += 5
    else:
        feedback_parts.append("mavenCentral repository missing")

    # Java Version
    if "17" in bg_content and ("sourceCompatibility" in bg_content or "toolchain" in bg_content):
        score += 5
    else:
        feedback_parts.append("Java 17 compatibility missing")

    # --- Criterion 4: Dependencies (25 pts) ---
    # We check for the presence of specific artifact names and their scopes
    deps_score = 0
    required_deps = metadata.get('dependencies', [])
    
    for dep in required_deps:
        name = dep['name']
        scope = dep['scope']
        
        # Regex to match: scope ... name ...
        # Simplified check: check if scope and name appear on the same line or strictly associated
        # Because gradle syntax varies, we look for the artifact string
        
        if name in bg_content:
            deps_score += 3 # Found artifact
            
            # Check scope
            # "implementation '...guava...'"
            # "testImplementation '...junit...'"
            pattern = re.compile(rf"{scope}.*{name}", re.IGNORECASE)
            if pattern.search(bg_content):
                deps_score += 2 # Correct scope
            else:
                feedback_parts.append(f"Wrong scope for {name}")
        else:
            feedback_parts.append(f"Missing dependency: {name}")

    score += deps_score

    # --- Criterion 5: Functional Build (30 pts) ---
    if result.get('gradle_build_success'):
        score += 15
        feedback_parts.append("Gradle build succeeded")
    else:
        feedback_parts.append("Gradle build failed")

    if result.get('gradle_test_success'):
        score += 10
        feedback_parts.append("Tests passed")
    
    if result.get('jar_created'):
        score += 5
        feedback_parts.append("JAR created")

    # --- Criterion 6: Anti-Gaming (10 pts) ---
    if result.get('file_created_during_task'):
        score += 10
    else:
        feedback_parts.append("File timestamp suspicious (predates task)")
        score = 0 # Fail immediately if pre-dated

    # --- Criterion 7: VLM Verification (5 pts) ---
    # Ensure they used IntelliJ, not just command line
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, 4)
        final = get_final_screenshot(traj)
        if final:
            frames.append(final)
            
        prompt = """
        Did the user interact with the IntelliJ IDEA interface to create or edit the Gradle files?
        Look for:
        1. Editing build.gradle or settings.gradle in the IDE editor.
        2. The Gradle tool window being active.
        3. Project structure / file tree showing Gradle files.
        
        Answer YES only if you see the IDE being used for these tasks. Answer NO if you only see a terminal.
        """
        
        vlm_result = query_vlm(images=frames, prompt=prompt)
        
        if vlm_result and vlm_result.get('success'):
            resp = vlm_result.get('response', '').upper()
            if "YES" in resp:
                vlm_score = 5
            else:
                feedback_parts.append("VLM: No IDE interaction detected")
    
    score += vlm_score

    # Final check
    passed = score >= 60 and result.get('gradle_build_success')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }