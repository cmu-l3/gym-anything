#!/usr/bin/env python3
"""Verifier for cleanup_unused_dependencies task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_cleanup_unused_dependencies(traj, env_info, task_info):
    """
    Verify that unused dependencies were removed and used ones kept.
    
    Scoring:
    - Unused deps removed (8 pts each x 5 = 40 pts)
    - Used deps kept (5 pts each x 4 = 20 pts)
    - Project compiles (20 pts)
    - Tests pass (15 pts)
    - File modified check (5 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    unused_deps = metadata.get('unused_dependencies', [])
    used_deps = metadata.get('used_dependencies', [])

    # Load result
    result = {}
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    pom_content = result.get('pom_content', '')
    compile_success = result.get('compile_success', False)
    test_success = result.get('test_success', False)
    pom_modified = result.get('pom_modified', False)
    sources_intact = result.get('sources_intact', True)

    score = 0
    feedback_parts = []
    
    if not sources_intact:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAILED: Source files were deleted or emptied. Do not modify source code."
        }

    # 1. Check Unused Dependencies (Should be GONE)
    # We look for artifactId in the pom content
    unused_removed_count = 0
    for dep in unused_deps:
        # Simple check: artifactId shouldn't be present as a dependency
        # Regex to ensure we are matching the artifactId tag
        pattern = rf"<artifactId>\s*{re.escape(dep)}\s*</artifactId>"
        if not re.search(pattern, pom_content):
            score += 8
            unused_removed_count += 1
        else:
            feedback_parts.append(f"Failed to remove unused dependency: {dep}")
    
    if unused_removed_count == len(unused_deps):
        feedback_parts.append(f"All {unused_removed_count} unused dependencies removed")
    else:
        feedback_parts.append(f"Removed {unused_removed_count}/{len(unused_deps)} unused dependencies")

    # 2. Check Used Dependencies (Should be PRESENT)
    used_kept_count = 0
    for dep in used_deps:
        pattern = rf"<artifactId>\s*{re.escape(dep)}\s*</artifactId>"
        if re.search(pattern, pom_content):
            score += 5
            used_kept_count += 1
        else:
            feedback_parts.append(f"Wrongly removed used dependency: {dep}")
    
    if used_kept_count == len(used_deps):
        feedback_parts.append(f"All {used_kept_count} used dependencies retained")
    else:
        feedback_parts.append(f"Retained {used_kept_count}/{len(used_deps)} used dependencies")

    # 3. Check Compilation (CRITICAL)
    if compile_success:
        score += 20
        feedback_parts.append("Project compiles successfully")
    else:
        feedback_parts.append("Project compilation FAILED")
        # If compilation fails, cap the score heavily because the project is broken
        # Even if they removed dependencies correctly, a broken build is a fail
        score = min(score, 40) 

    # 4. Check Tests
    if test_success:
        score += 15
        feedback_parts.append("All tests passed")
    else:
        feedback_parts.append("Tests FAILED")
    
    # 5. Check Modification
    if pom_modified:
        score += 5
    else:
        feedback_parts.append("pom.xml was not modified")

    passed = (score >= 70) and compile_success

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }