#!/usr/bin/env python3
"""Verifier for refactor_infer_generics task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_infer_generics(traj, env_info, task_info):
    """
    Verify that AdmissionQueue.java was refactored to use Generics.
    
    Criteria:
    1. File was modified during task (20 pts)
    2. 'List<Patient>' is present (40 pts)
    3. Explicit casts '(Patient)' are removed (30 pts)
    4. Code still compiles/builds (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    result = {}
    try:
        tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_result.close()
        copy_from_env("/tmp/task_result.json", tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback_parts = []
    
    content = result.get("file_content", "")
    file_modified = result.get("file_modified", False)
    build_success = result.get("build_success", False)

    # 1. Check Modification (20 pts)
    if file_modified:
        score += 20
        feedback_parts.append("File modified")
    else:
        feedback_parts.append("File NOT modified (did you save?)")

    # 2. Check for Generics (40 pts)
    # We expect List<Patient>, ArrayList<Patient>, or Iterator<Patient>
    # Regex to handle spacing variations
    has_generics = re.search(r'List\s*<\s*Patient\s*>', content) or \
                   re.search(r'ArrayList\s*<\s*Patient\s*>', content) or \
                   re.search(r'Iterator\s*<\s*Patient\s*>', content)
                   
    if has_generics:
        score += 40
        feedback_parts.append("Generics detected")
    else:
        feedback_parts.append("Generics NOT detected (expected List<Patient>)")

    # 3. Check for Removed Casts (30 pts)
    # We want to ensure (Patient) casts are GONE.
    # The original code had: (Patient) waitingList.remove(0) and (Patient) it.next()
    
    # We search for the cast pattern. If found, points are NOT awarded.
    # Note: Regex needs to be careful not to match other things, but (Patient) is specific.
    has_cast = re.search(r'\(\s*Patient\s*\)', content)
    
    if not has_cast and has_generics:
        score += 30
        feedback_parts.append("Explicit casts removed")
    elif has_cast:
        feedback_parts.append("Explicit casts still present")
    else:
        # If no generics were added, removing casts would just break the code, 
        # so we don't award points for "no casts" if the code isn't genericized.
        feedback_parts.append("Casts not removed (or code invalid)")

    # 4. Check Build Success (10 pts)
    if build_success:
        score += 10
        feedback_parts.append("Build updated")
    else:
        feedback_parts.append("Build not updated")

    # VLM Check (Bonus/Validation)
    # Using VLM to verify the refactoring dialog was used would be robust, 
    # but for this specific code task, file content is definitive evidence.
    # We will assume code evidence is sufficient.

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }