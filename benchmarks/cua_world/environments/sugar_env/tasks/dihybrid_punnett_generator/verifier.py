#!/usr/bin/env python3
"""Verifier for dihybrid_punnett_generator task."""

import json
import os
import tempfile

def verify_dihybrid_punnett(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/punnett_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    if result.get("error"):
        feedback.append(f"Export script error: {result['error']}")

    # Criterion 1: Script File Exists (10)
    if result.get("script_exists"):
        score += 10
        feedback.append("Script file created")
    else:
        feedback.append("FAIL: Script punnett_generator.py not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: Base HTML Exists (5)
    if result.get("html_exists"):
        score += 5
        feedback.append("HTML file generated")
    else:
        feedback.append("HTML file punnett_square.html not found")

    # Criterion 3: HTML Structure (10)
    if result.get("html_structure"):
        score += 10
        feedback.append("HTML structure valid")
    else:
        feedback.append("Missing table elements in HTML")

    # Criterion 4: Base Cross Frequencies (10)
    rrYy_count = result.get("initial_RrYy_count", 0)
    rryy_count = result.get("initial_rryy_count", 0)
    if rrYy_count >= 4 and rryy_count >= 1:
        score += 10
        feedback.append(f"Base cross accurate (RrYy: {rrYy_count}, rryy: {rryy_count})")
    elif rrYy_count > 0:
        score += 5
        feedback.append(f"Base cross partial (RrYy: {rrYy_count})")
    else:
        feedback.append("Base cross genotypes not found in HTML")

    # Criterion 5: Base Convention Accuracy (15)
    invalid_alleles = result.get("initial_invalid_alleles", 0)
    if invalid_alleles == 0 and (rrYy_count > 0 or rryy_count > 0):
        score += 15
        feedback.append("Allele conventions correct (Dominant first)")
    else:
        feedback.append(f"Convention errors detected ({invalid_alleles} invalid strings)")

    # Criterion 6: Dynamic Execution Success (10)
    if result.get("dynamic_execution_success"):
        score += 10
        feedback.append("Dynamic execution succeeded")
    else:
        feedback.append("FAIL: Dynamic execution failed (script crashed or didn't output HTML)")

    # Criteria 7-9: Dynamic Accuracy (30)
    dyn_TtGg = result.get("dynamic_TtGg_count", 0)
    dyn_ttgg = result.get("dynamic_ttgg_count", 0)
    dyn_ttGg = result.get("dynamic_ttGg_count", 0)
    
    dyn_score = 0
    if dyn_TtGg >= 4: dyn_score += 10
    if dyn_ttgg >= 4: dyn_score += 10
    if dyn_ttGg >= 4: dyn_score += 10
    
    score += dyn_score
    if dyn_score == 30:
        feedback.append("Dynamic cross 100% accurate")
    elif dyn_score > 0:
        feedback.append(f"Dynamic cross partial ({dyn_score}/30)")
    elif result.get("dynamic_execution_success"):
        feedback.append("Dynamic cross inaccurate (wrong cell counts)")

    # Criterion 10: Dynamic Absence check (10)
    dyn_invalid_TT = result.get("dynamic_invalid_TT_count", 0)
    if result.get("dynamic_execution_success") and dyn_invalid_TT == 0 and dyn_score > 0:
        score += 10
        feedback.append("Logic isolation confirmed (no impossible genotypes)")
    elif result.get("dynamic_execution_success") and dyn_invalid_TT > 0:
        feedback.append(f"Impossible genotypes found in dynamic run ({dyn_invalid_TT} errors)")

    passed = (score >= 75 and result.get("dynamic_execution_success"))
    
    if passed:
        feedback.append("Task successfully passed!")
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "html_structure": result.get("html_structure", False),
            "dynamic_success": result.get("dynamic_execution_success", False),
            "dynamic_score": dyn_score
        }
    }