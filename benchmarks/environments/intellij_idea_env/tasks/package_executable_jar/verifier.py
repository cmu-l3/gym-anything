#!/usr/bin/env python3
"""Verifier for package_executable_jar task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_package_executable_jar(traj, env_info, task_info):
    """Verify that an executable JAR was correctly configured and built.

    Criteria:
    1. JAR exists and was created during task (15 pts)
    2. JAR size > 50KB (indicates shading of dependencies) (10 pts)
    3. Manifest contains 'Main-Class: com.csvstats.App' (20 pts)
    4. JAR contains bundled dependencies (Commons CSV) (15 pts)
    5. JAR executes successfully (exit code 0) (25 pts)
    6. Execution output contains correct statistics (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    score = 0
    feedback_parts = []
    
    # Read result from container
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

    # Criterion 1: JAR Exists & Timestamp (15 pts)
    jar_exists = result.get('jar_exists', False)
    created_fresh = result.get('file_created_during_task', False)
    
    if jar_exists and created_fresh:
        score += 15
        feedback_parts.append("JAR created during task")
    elif jar_exists:
        # Penalize if not created fresh (might be pre-existing, though setup clears it)
        score += 5 
        feedback_parts.append("JAR exists but timestamp doubtful")
    else:
        feedback_parts.append("JAR not found")
        # Critical failure
        return {"passed": False, "score": 0, "feedback": "JAR file not found in target directory"}

    # Criterion 2: JAR Size (10 pts)
    # Empty JARs are ~1-4KB. Commons CSV is ~50KB. So a shaded JAR should be >50KB.
    size = result.get('jar_size_bytes', 0)
    if size > 50000:
        score += 10
        feedback_parts.append(f"JAR size good ({size/1024:.1f}KB)")
    else:
        feedback_parts.append(f"JAR size too small ({size/1024:.1f}KB) - dependencies likely not bundled")

    # Criterion 3: Manifest (20 pts)
    has_main = result.get('has_main_class_manifest', False)
    if has_main:
        score += 20
        feedback_parts.append("Manifest contains Main-Class")
    else:
        feedback_parts.append("Manifest missing Main-Class attribute")

    # Criterion 4: Bundled Dependencies (15 pts)
    has_deps = result.get('has_bundled_dependencies', False)
    if has_deps:
        score += 15
        feedback_parts.append("Dependencies bundled (Shading verified)")
    else:
        feedback_parts.append("Commons CSV classes not found in JAR")

    # Criterion 5: Execution Success (25 pts)
    exec_success = result.get('execution_success', False)
    if exec_success:
        score += 25
        feedback_parts.append("JAR executes successfully")
    else:
        feedback_parts.append("JAR failed to execute (crashed or non-zero exit)")

    # Criterion 6: Output Verification (15 pts)
    output = result.get('execution_output', "")
    # Expect output from App.java: "Count:", "Min:", "Max:", "Mean:"
    if "Count:" in output and "Mean:" in output:
        score += 15
        feedback_parts.append("Output contains valid statistics")
    elif exec_success:
        feedback_parts.append("Execution output format incorrect")

    # Final check
    passed = score >= 60 and has_main and has_deps
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }