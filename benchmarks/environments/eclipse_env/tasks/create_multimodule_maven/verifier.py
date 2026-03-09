#!/usr/bin/env python3
"""
Verifier for create_multimodule_maven task.

Verifies:
1. Maven Reactor Structure (Parent POM, Modules)
2. Dependency Configuration (App depends on Core)
3. Code Implementation (StringUtils, MathUtils, Main)
4. Build Success (mvn package)
5. Runtime Correctness (Output of Main)
6. VLM Trajectory (Eclipse usage)
"""

import json
import tempfile
import os
import xml.etree.ElementTree as ET
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_multimodule_maven(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_root = metadata.get('project_root', "/home/ga/eclipse-workspace/toolkit-parent")
    
    score = 0
    feedback_parts = []
    
    # 1. Load execution result from container
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}

    # Helper to read file content from container
    def read_remote_file(path):
        try:
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.tmp')
            tmp.close()
            copy_from_env(path, tmp.name)
            with open(tmp.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            os.unlink(tmp.name)
            return content
        except Exception:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
            return None

    # --- Criterion 1: Structure & Maven Build (30 pts) ---
    build_success = result.get('build_success', False)
    
    if build_success:
        score += 30
        feedback_parts.append("Maven build succeeded")
    elif result.get('parent_pom_exists'):
        # Partial credit if structure exists but build failed
        score += 10
        feedback_parts.append("Structure exists but build failed")
    else:
        feedback_parts.append("Project structure missing")

    # --- Criterion 2: Parent POM Analysis (15 pts) ---
    parent_pom_content = read_remote_file(f"{project_root}/pom.xml")
    if parent_pom_content:
        try:
            # Simple check for packaging pom and modules
            if "<packaging>pom</packaging>" in parent_pom_content:
                score += 5
                feedback_parts.append("Parent packaging is POM")
            if "<module>toolkit-core</module>" in parent_pom_content and "<module>toolkit-app</module>" in parent_pom_content:
                score += 10
                feedback_parts.append("Parent lists both modules")
            else:
                feedback_parts.append("Parent modules configuration incomplete")
        except Exception:
            pass

    # --- Criterion 3: App Dependency Analysis (10 pts) ---
    app_pom_content = read_remote_file(f"{project_root}/toolkit-app/pom.xml")
    if app_pom_content:
        if "toolkit-core" in app_pom_content and "<artifactId>toolkit-core</artifactId>" in app_pom_content:
            score += 10
            feedback_parts.append("App module depends on Core module")
        else:
            feedback_parts.append("App module missing dependency on Core")

    # --- Criterion 4: Java Code Content (25 pts) ---
    # Check StringUtils
    string_utils = None
    # Find file path blindly since package structure might vary slightly if user made a mistake
    # But we know it's in toolkit-core/src/main/java...
    # We'll try the expected path
    string_utils = read_remote_file(f"{project_root}/toolkit-core/src/main/java/com/startup/toolkit/core/StringUtils.java")
    
    if string_utils and "capitalize" in string_utils:
        score += 8
        feedback_parts.append("StringUtils implementation found")
    
    # Check MathUtils
    math_utils = read_remote_file(f"{project_root}/toolkit-core/src/main/java/com/startup/toolkit/core/MathUtils.java")
    if math_utils and "factorial" in math_utils:
        score += 8
        feedback_parts.append("MathUtils implementation found")

    # Check Main
    main_class = read_remote_file(f"{project_root}/toolkit-app/src/main/java/com/startup/toolkit/app/Main.java")
    if main_class and "main" in main_class:
        if "StringUtils.capitalize" in main_class and "MathUtils.factorial" in main_class:
            score += 9
            feedback_parts.append("Main class uses utils correctly")
        else:
            score += 4
            feedback_parts.append("Main class exists but might not use all utils")

    # --- Criterion 5: Runtime Output (10 pts) ---
    runtime_success = result.get('runtime_success', False)
    runtime_output = result.get('runtime_output', "")
    
    if runtime_success:
        # Check for expected output values (case insensitive)
        if "hello" in runtime_output.lower() and "3628800" in runtime_output:
            score += 10
            feedback_parts.append("Runtime output correct")
        elif "3628800" in runtime_output:
            score += 5
            feedback_parts.append("Runtime output partially correct (factorial found)")
        else:
            feedback_parts.append(f"Runtime output incorrect: {runtime_output[:100]}...")

    # --- Criterion 6: VLM Verification (10 pts) ---
    # Use trajectory frames to verify Eclipse usage
    from eclipse_verification_utils import vlm_verify_eclipse_task
    
    vlm_result = vlm_verify_eclipse_task(
        traj, env_info,
        task_description="Create a multi-module Maven project in Eclipse",
        checklist_items=[
            "Eclipse IDE is open",
            "Project Explorer shows toolkit-parent with sub-modules",
            "User is editing Java files or POM files in Eclipse",
            "Console view or Problems view is visible (optional)"
        ]
    )
    
    if vlm_result:
        if vlm_result.get('vlm_passed', False):
            score += 10
            feedback_parts.append("VLM verified Eclipse usage")
        else:
            feedback_parts.append(f"VLM verification failed: {vlm_result.get('vlm_feedback', '')}")
    else:
        # Fallback if VLM not available
        feedback_parts.append("VLM skipped")
        score += 10 # Give benefit of doubt if VLM is offline to avoid unfair fail on tools

    # --- Final Scoring ---
    # Cap score at 100
    score = min(score, 100)
    
    # Pass threshold: Must build successfully AND have reasonable score
    passed = build_success and score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }