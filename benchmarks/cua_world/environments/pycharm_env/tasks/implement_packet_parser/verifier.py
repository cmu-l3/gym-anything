#!/usr/bin/env python3
"""
Verifier for implement_packet_parser task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_packet_parser(traj, env_info, task_info):
    """
    Verify packet parser implementation.
    
    Scoring:
    - Ethernet tests passed: 15 pts
    - IPv4 tests passed: 20 pts
    - TCP tests passed: 20 pts
    - UDP tests passed: 15 pts
    - Integration tests passed: 20 pts
    - Integrity Check (Tests unmodified): 10 pts
    
    Total: 100
    Threshold: 65
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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
    
    # Check integrity first
    integrity = result.get('integrity_check', False)
    if integrity:
        score += 10
        feedback_parts.append("Test integrity verified (+10)")
    else:
        feedback_parts.append("WARNING: Test files modified (0/10)")

    # Check implementation quality (anti-gaming)
    files_mod = result.get('files_modified_during_task', False)
    code_check = result.get('code_uses_struct_or_bits', False)
    
    if not files_mod:
        return {"passed": False, "score": 0, "feedback": "No source files were modified."}
    
    if not code_check:
        feedback_parts.append("WARNING: Code does not appear to use 'struct' or bitwise operations.")

    # Score sections
    # Note: These boolean flags from the shell script rely on pytest output containing "100%"
    # which implies all tests in that file passed.
    
    if result.get('ethernet_pass', False):
        score += 15
        feedback_parts.append("Ethernet tests passed (+15)")
    else:
        feedback_parts.append("Ethernet tests failed")

    if result.get('ipv4_pass', False):
        score += 20
        feedback_parts.append("IPv4 tests passed (+20)")
    else:
        feedback_parts.append("IPv4 tests failed")

    if result.get('tcp_pass', False):
        score += 20
        feedback_parts.append("TCP tests passed (+20)")
    else:
        feedback_parts.append("TCP tests failed")

    if result.get('udp_pass', False):
        score += 15
        feedback_parts.append("UDP tests passed (+15)")
    else:
        feedback_parts.append("UDP tests failed")

    if result.get('integration_pass', False):
        score += 20
        feedback_parts.append("Integration tests passed (+20)")
    else:
        feedback_parts.append("Integration tests failed")
        
    # Validation against total test count
    passed_count = result.get('tests_passed', 0)
    total_tests = result.get('tests_total', 29)
    
    feedback_parts.append(f"Total Tests Passed: {passed_count}/{total_tests}")

    # Determine pass/fail
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }