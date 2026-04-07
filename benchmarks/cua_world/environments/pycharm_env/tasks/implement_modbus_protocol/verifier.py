#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_modbus_protocol(traj, env_info, task_info):
    """
    Verify the Modbus protocol implementation task.
    
    Scoring Criteria:
    1. CRC Implementation (20pts): Tests passed + Poly present
    2. Frame Construction (20pts): Tests passed
    3. Function Codes (25pts): Tests passed
    4. Exception Handling (15pts): Tests passed + 0x80 check present
    5. Test Integrity (10pts): Test files not modified
    6. All Tests Pass (10pts): 100% pass rate
    
    Pass Threshold: 60/100
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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

    # Extract metrics
    tests_passed = result.get('tests_passed', 0)
    tests_modified = result.get('tests_modified', True) # Default fail if unknown
    has_crc_poly = result.get('has_crc_poly', False)
    has_exception_check = result.get('has_exception_check', False)
    
    score = 0
    feedback_parts = []
    
    # 1. Test Integrity (Critical)
    if not tests_modified:
        score += 10
        feedback_parts.append("Tests integrity verified (10/10)")
    else:
        feedback_parts.append("PENALTY: Test files modified (0/10)")
        # Serious infraction, potentially limit max score
    
    # 2. General Test Success
    # We estimate category success based on total passing tests.
    # Total tests = 20.
    # We allocate points proportionally to pass rate, but strictly grouped.
    
    pass_ratio = tests_passed / 20.0 if result.get('total_tests', 20) > 0 else 0
    
    # Heuristic scoring based on pass count:
    # CRC Tests (5) -> ~25% of tests
    # Frame Tests (5) -> ~25% of tests
    # Func Tests (6) -> ~30% of tests
    # Exc Tests (4) -> ~20% of tests
    
    # Score Calculation
    
    # CRC Implementation (20 pts)
    # If > 3 tests pass and poly is found
    if pass_ratio > 0.15 and has_crc_poly:
        score += 20
        feedback_parts.append("CRC implemented correctly (20/20)")
    elif pass_ratio > 0.15:
        score += 10
        feedback_parts.append("CRC tests passing but polynomial not explicitly found (10/20)")
    else:
        feedback_parts.append("CRC implementation failed (0/20)")
        
    # Frame Construction (20 pts)
    if pass_ratio > 0.4: # Implies CRC + Framing likely working
        score += 20
        feedback_parts.append("Framing logic working (20/20)")
    else:
        feedback_parts.append("Framing logic failed (0/20)")
        
    # Function Codes (25 pts)
    if pass_ratio > 0.7:
        score += 25
        feedback_parts.append("Function codes implemented (25/25)")
    elif pass_ratio > 0.5:
        score += 10
        feedback_parts.append("Partial function codes (10/25)")
    else:
        feedback_parts.append("Function codes failed (0/25)")
        
    # Exception Handling (15 pts)
    if pass_ratio > 0.9 and has_exception_check:
        score += 15
        feedback_parts.append("Exceptions handled (15/15)")
    elif pass_ratio > 0.9:
        score += 10
        feedback_parts.append("Exception tests pass (10/15)")
    else:
        feedback_parts.append("Exception handling failed (0/15)")
        
    # Completion Bonus (10 pts)
    if tests_passed == 20:
        score += 10
        feedback_parts.append("All tests passed (10/10)")
        
    # Final check
    passed = score >= 60 and (not tests_modified)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }