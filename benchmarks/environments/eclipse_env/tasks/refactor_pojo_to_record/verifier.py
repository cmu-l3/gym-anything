#!/usr/bin/env python3
"""Verifier for refactor_pojo_to_record task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_pojo_to_record(traj, env_info, task_info):
    """
    Verify the refactoring of BeamSetup to a Java Record.
    
    Criteria:
    1.  Project compiles (30 pts)
    2.  Bytecode confirms it is a java.lang.Record (30 pts)
    3.  Validation logic preserved (Compact Constructor checks) (20 pts)
    4.  Tests pass (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Compilation Check (30 pts)
    if result.get('build_success', False):
        score += 30
        feedback_parts.append("Build success")
    else:
        feedback_parts.append("Build failed")

    # 2. Record Type Check (30 pts)
    # Using bytecode check from export script is most reliable
    if result.get('is_record_bytecode', False):
        score += 30
        feedback_parts.append("Converted to Record (bytecode verified)")
    else:
        # Fallback: Check source code if build failed but they tried
        src = result.get('beam_setup_src', '')
        if re.search(r'public\s+record\s+BeamSetup', src):
            score += 15
            feedback_parts.append("Source defines record (but build/bytecode failed)")
        else:
            feedback_parts.append("Not converted to Record")

    # 3. Validation Logic Preserved (20 pts)
    # We check the source code for the logic: if (gantryAngle < 0 || gantryAngle > 360)
    src = result.get('beam_setup_src', '')
    # Check for compact constructor or canonical constructor logic
    if 'gantryAngle < 0' in src and 'gantryAngle > 360' in src and 'throw new IllegalArgumentException' in src:
        score += 20
        feedback_parts.append("Validation logic preserved")
    else:
        feedback_parts.append("Validation logic missing or altered")

    # 4. Tests Pass (20 pts)
    tests_run = result.get('tests_run', 0)
    tests_failures = result.get('tests_failures', 0)
    tests_errors = result.get('tests_errors', 0)
    
    if tests_run > 0 and tests_failures == 0 and tests_errors == 0:
        score += 20
        feedback_parts.append(f"All {tests_run} tests passed")
    elif tests_run > 0:
        feedback_parts.append(f"Tests failed: {tests_failures} fail, {tests_errors} error")
    else:
        feedback_parts.append("Tests did not run")
    
    # Check for TreatmentPlan update (Implicit in build success, but let's be sure)
    tp_src = result.get('treatment_plan_src', '')
    if 'beam.gantryAngle()' in tp_src or 'beam.beamId()' in tp_src:
        feedback_parts.append("TreatmentPlan accessors updated")
    elif 'beam.getGantryAngle()' in tp_src and result.get('is_record_bytecode', False):
        feedback_parts.append("WARNING: TreatmentPlan still uses getters (might compile if record declared getters manually, but standard records don't)")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }