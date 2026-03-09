#!/usr/bin/env python3
"""Verifier for reverse_engineer_legacy_jar task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reverse_engineer_legacy_jar(traj, env_info, task_info):
    """
    Verify that the agent successfully identified the secret format from the JAR
    and updated the test to pass.
    
    Scoring Criteria:
    1. Test file modified (10 pts)
    2. Maven build/test execution successful (50 pts)
    3. Test file contains correct prefix "SEC-V2-" (25 pts)
    4. Test file contains string of correct length 16 (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata values (from task.json)
    metadata = task_info.get('metadata', {})
    secret_prefix = metadata.get('secret_prefix', "SEC-V2-")
    required_length = metadata.get('required_length', 16)

    score = 0
    feedback_parts = []
    
    # --------------------------------------------------------------
    # Load result data from container
    # --------------------------------------------------------------
    def load_result_json():
        try:
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
            tmp.close()
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Failed to load result JSON: {e}")
            return {}
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    result = load_result_json()
    test_content = result.get('test_content', '')
    test_output = result.get('test_output', '')
    test_result = result.get('test_result', 'unknown')
    file_modified = result.get('file_modified', False)

    # --------------------------------------------------------------
    # Criterion 1: Test file modified (10 pts)
    # --------------------------------------------------------------
    if file_modified:
        score += 10
        feedback_parts.append("Test file modified")
    else:
        feedback_parts.append("Test file was NOT modified")

    # --------------------------------------------------------------
    # Criterion 2: Maven test execution passed (50 pts)
    # --------------------------------------------------------------
    # We rely on the export_result.sh running 'mvn test'
    if test_result == 'pass':
        score += 50
        feedback_parts.append("Unit tests passed successfully")
    else:
        feedback_parts.append("Unit tests FAILED")
        # Check output for common errors
        if "Compilation failure" in test_output:
            feedback_parts.append("(Compilation error)")
        elif "AssertionError" in test_output:
            feedback_parts.append("(Assertion failed - ID still invalid)")

    # --------------------------------------------------------------
    # Criterion 3: Correct Prefix Usage (25 pts)
    # --------------------------------------------------------------
    # The agent MUST have found "SEC-V2-" inside the JAR
    if secret_prefix in test_content:
        score += 25
        feedback_parts.append(f"Correct prefix '{secret_prefix}' found in code")
    else:
        feedback_parts.append(f"Correct prefix '{secret_prefix}' NOT found in code")

    # --------------------------------------------------------------
    # Criterion 4: Correct Length Usage (15 pts)
    # --------------------------------------------------------------
    # Find the transaction ID string used in the test
    # Regex looks for: String transactionId = "..."
    match = re.search(r'String\s+transactionId\s*=\s*"([^"]+)"', test_content)
    if match:
        used_id = match.group(1)
        if len(used_id) == required_length:
            score += 15
            feedback_parts.append(f"Transaction ID length is correct ({len(used_id)})")
        else:
            feedback_parts.append(f"Transaction ID length is {len(used_id)} (expected {required_length})")
            
        # Anti-gaming: Ensure they didn't just delete the assertion or logic
        if "assertTrue" not in test_content and "LegacyValidator.validate" not in test_content:
            score = 0
            feedback_parts.append("CRITICAL: Test logic/assertion removed!")
    else:
        feedback_parts.append("Could not parse transaction ID string from code")

    # --------------------------------------------------------------
    # Final Result
    # --------------------------------------------------------------
    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }