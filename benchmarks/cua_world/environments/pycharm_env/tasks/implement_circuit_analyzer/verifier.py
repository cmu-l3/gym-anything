#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_circuit_analyzer(traj, env_info, task_info):
    """
    Verify implementation of circuit analysis library.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/circuit_analyzer_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Scoring Criteria
    score = 0
    feedback = []

    # 1. Test Tampering (5 pts)
    if result.get("tests_tampered", False):
        feedback.append("⚠️ Test files were modified (tampering detected).")
    else:
        score += 5
        feedback.append("✅ Test files integrity verified.")

    # 2. Components Implementation (15 pts)
    # 5 tests total in test_components
    comp_pass = result.get("pass_breakdown", {}).get("components", 0)
    if comp_pass == 5:
        score += 15
        feedback.append("✅ Components implemented correctly (5/5 tests).")
    else:
        feedback.append(f"❌ Components issues: {comp_pass}/5 tests passed.")

    # 3. Networks Implementation (25 pts)
    # 7 tests total in test_networks
    net_pass = result.get("pass_breakdown", {}).get("networks", 0)
    if net_pass == 7:
        score += 25
        feedback.append("✅ Networks implemented correctly (7/7 tests).")
    else:
        feedback.append(f"❌ Networks issues: {net_pass}/7 tests passed.")

    # 4. AC Analysis Implementation (30 pts)
    # 8 tests total in test_ac_analysis
    ac_pass = result.get("pass_breakdown", {}).get("ac_analysis", 0)
    if ac_pass == 8:
        score += 30
        feedback.append("✅ AC Analysis implemented correctly (8/8 tests).")
    else:
        feedback.append(f"❌ AC Analysis issues: {ac_pass}/8 tests passed.")

    # 5. Analysis Implementation (20 pts)
    # 5 tests total in test_analysis
    analysis_pass = result.get("pass_breakdown", {}).get("analysis", 0)
    if analysis_pass == 5:
        score += 20
        feedback.append("✅ Analysis functions implemented correctly (5/5 tests).")
    else:
        feedback.append(f"❌ Analysis functions issues: {analysis_pass}/5 tests passed.")

    # 6. Hardcoding / Cheating check (5 pts reserved)
    # We'll award this if >0 tests passed overall and no tampering
    if result.get("tests_passed", 0) > 0 and not result.get("tests_tampered", False):
        score += 5
    
    # Calculate Pass/Fail
    # Max score: 5 + 15 + 25 + 30 + 20 + 5 = 100
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }