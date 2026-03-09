#!/usr/bin/env python3
"""Verifier for generate_delegate_methods task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_delegate_methods(traj, env_info, task_info):
    """
    Verify that the agent generated delegate methods and added logging.
    
    Scoring Criteria:
    1. File modified during task (5 pts)
    2. All 6 interface methods present (20 pts)
    3. Delegation calls present in methods (15 pts)
    4. Custom logging in sendMessage (15 pts)
    5. Custom logging in getMessageCount (15 pts)
    6. Project compiles successfully (15 pts)
    7. Runtime output verifies logic (10 pts)
    8. VLM: Used Generate Delegate Methods dialog (5 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 1. File Modification (5 pts)
    if result.get('file_modified'):
        score += 5
        feedback.append("File was modified.")
    else:
        feedback.append("File was NOT modified.")

    # Content Analysis
    content = result.get('target_content', '')
    
    # 2. Check for Methods (20 pts)
    required_methods = [
        r'void\s+sendMessage\s*\(',
        r'boolean\s+deleteMessage\s*\(',
        r'String\s+getMessage\s*\(',
        r'int\s+getMessageCount\s*\(',
        r'boolean\s+isConnected\s*\(',
        r'void\s+connect\s*\('
    ]
    methods_found = 0
    for pattern in required_methods:
        if re.search(pattern, content):
            methods_found += 1
    
    method_score = int((methods_found / 6) * 20)
    score += method_score
    feedback.append(f"Methods implemented: {methods_found}/6 (+{method_score} pts)")

    # 3. Check for Delegation (15 pts)
    # Look for calls like 'delegate.methodName(' or 'this.delegate.methodName('
    # We check if 'delegate.' appears frequently
    delegation_count = len(re.findall(r'\bdelegate\.', content))
    if delegation_count >= 6:
        score += 15
        feedback.append("Delegation logic detected (+15 pts)")
    elif delegation_count > 0:
        score += 5
        feedback.append("Partial delegation logic detected (+5 pts)")
    else:
        feedback.append("No delegation calls found (expected 'delegate.method()')")

    # 4 & 5. Check for Custom Logging (30 pts)
    # "[LOG] Sending message to:"
    if '[LOG] Sending message to:' in content and 'System.out.println' in content:
        score += 15
        feedback.append("sendMessage logging added (+15 pts)")
    else:
        feedback.append("Missing or incorrect logging in sendMessage")

    # "[LOG] Getting message count"
    if '[LOG] Getting message count' in content and 'System.out.println' in content:
        score += 15
        feedback.append("getMessageCount logging added (+15 pts)")
    else:
        feedback.append("Missing or incorrect logging in getMessageCount")

    # 6. Compilation (15 pts)
    if result.get('compilation_success'):
        score += 15
        feedback.append("Project compiles successfully (+15 pts)")
    else:
        feedback.append("Compilation FAILED")
        if 'compile_errors' in result:
            feedback.append(f"Errors: {result['compile_errors'][:100]}...")

    # 7. Runtime Verification (10 pts)
    output = result.get('runtime_output', '')
    if "[LOG]" in output and "Email sent to" in output:
        score += 10
        feedback.append("Runtime output verifies correct behavior (+10 pts)")
    else:
        feedback.append("Runtime output missing or incorrect")

    # 8. VLM Verification (5 pts)
    try:
        from eclipse_verification_utils import vlm_verify_eclipse_task
        vlm_res = vlm_verify_eclipse_task(
            traj, env_info,
            "Generate delegate methods in Eclipse and add logging",
            [
                "Generate Delegate Methods dialog visible",
                "Source menu or context menu opened",
                "LoggingMessageService.java editor visible"
            ]
        )
        if vlm_res and vlm_res.get('vlm_passed'):
            score += 5
            feedback.append("VLM: UI interaction verified (+5 pts)")
    except ImportError:
        pass

    passed = score >= 60 and result.get('compilation_success')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }