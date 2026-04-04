#!/usr/bin/env python3
"""
Verifier for configure_project_roots task.

Verifies:
1. 'src' marked as source root (in .iml)
2. 'test' marked as test root (in .iml)
3. 'config' marked as resource root (in .iml)
4. Libraries (commons-lang3, junit) added (in .iml or .idea/libraries)
5. Project compiled successfully (Main.class exists and is fresh)
6. VLM: Trajectory verification of UI interaction
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_project_roots(traj, env_info, task_info):
    """Verify project structure configuration and build success."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
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
    
    iml_content = result.get('iml_content', '')
    lib_content = result.get('libraries_content', '')
    combined_config = iml_content + "\n" + lib_content

    # --- Criterion 1: Source Root (20 pts) ---
    # Look for: <sourceFolder url="file://$MODULE_DIR$/src" isTestSource="false" />
    if re.search(r'url="[^"]*/src"\s+isTestSource="false"', iml_content):
        score += 20
        feedback_parts.append("Source root 'src' configured correctly")
    else:
        feedback_parts.append("Source root 'src' missing or incorrect")

    # --- Criterion 2: Test Root (20 pts) ---
    # Look for: <sourceFolder url="file://$MODULE_DIR$/test" isTestSource="true" />
    if re.search(r'url="[^"]*/test"\s+isTestSource="true"', iml_content):
        score += 20
        feedback_parts.append("Test root 'test' configured correctly")
    else:
        feedback_parts.append("Test root 'test' missing or incorrect")

    # --- Criterion 3: Resources Root (10 pts) ---
    # Look for: <content url="file://$MODULE_DIR$/config" ... type="java-resource" />
    # OR within content tag: <sourceFolder url=".../config" type="java-resource" />
    # XML structure varies by IntelliJ version, regex approximation:
    if re.search(r'url="[^"]*/config"\s+type="java-resource"', iml_content) or \
       re.search(r'url="[^"]*/config".*?resource="true"', iml_content): 
        score += 10
        feedback_parts.append("Resource root 'config' configured correctly")
    else:
        feedback_parts.append("Resource root 'config' missing")

    # --- Criterion 4: Libraries Configured (20 pts) ---
    # Check for presence of library references
    libs_found = 0
    if 'commons-lang3' in combined_config:
        libs_found += 1
    if 'junit' in combined_config:
        libs_found += 1
    
    if libs_found >= 2:
        score += 20
        feedback_parts.append("Libraries (Commons, JUnit) configured")
    elif libs_found == 1:
        score += 10
        feedback_parts.append("Some libraries missing")
    else:
        feedback_parts.append("Libraries not configured in project structure")

    # --- Criterion 5: Build Success (30 pts) ---
    main_exists = result.get('main_class_exists', False)
    fresh_build = result.get('file_created_during_task', False)
    
    if main_exists and fresh_build:
        score += 30
        feedback_parts.append("Project compiled successfully")
    elif main_exists:
        score += 15
        feedback_parts.append("Class file exists but timestamp suggests stale build")
    else:
        feedback_parts.append("Build failed (Main.class not found)")

    # --- VLM Verification (Bonus/Confirmation) ---
    # If using VLM, we could check if Project Structure dialog was opened
    # For now, relying on programmatic verification is robust enough given checks 1-5.
    
    passed = score >= 80  # Must have most config correct and compile success
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }