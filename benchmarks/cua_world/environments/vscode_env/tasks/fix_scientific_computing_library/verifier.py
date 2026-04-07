#!/usr/bin/env python3
"""
Verifier for the fix_scientific_computing_library task.

Checks whether the agent fixed the 5 algorithmic bugs in the `numlib` library.
The `export_result.sh` script runs the test suite in the container and exports 
a JSON report along with file timestamps and source content for anti-gaming checks.

Criteria:
1. Integration test passing (Simpson's rule fixed) -> 20 pts
2. ODE solver test passing (RK4 k3 assignment fixed) -> 20 pts
3. Linear algebra test passing (LU partial pivoting implemented) -> 20 pts
4. Interpolation test passing (Cubic spline matrix off-by-one fixed) -> 20 pts
5. Root finder test passing (Bisection interval logic fixed) -> 20 pts

Anti-gaming:
- Ensure files were actually modified.
- Reject solutions that bypass scratch implementations by importing `scipy` or `numpy`.
- VLM check ensures interaction with the editor.
"""

import sys
import os
import json
import re
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# =============================================================================
# VLM PROMPT
# =============================================================================

VERIFICATION_PROMPT = """You are verifying if an AI agent successfully interacted with VS Code to edit Python source code.

Look at these trajectory screenshots. Determine:
1. Did the agent open and edit Python files inside VS Code?
2. Did the agent navigate through different files (e.g. integration.py, ode_solver.py, linear_algebra.py)?
3. Did the agent execute the test script in the terminal?

We are not verifying if the code is correct here (that is done programmatically), but ONLY verifying that the agent actively attempted the task using the IDE.

Respond in JSON format:
{
    "edited_files": true/false,
    "executed_tests": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""


def check_anti_gaming(file_info, module_name):
    """
    Check if the file content imports scipy or numpy.linalg to bypass the algorithm.
    """
    content = file_info.get("content", "")
    
    # Check for restricted library imports
    if re.search(r'^\s*import\s+scipy', content, re.MULTILINE) or \
       re.search(r'^\s*from\s+scipy\s+import', content, re.MULTILINE):
        return False, f"{module_name} illegally imports scipy"
        
    if re.search(r'^\s*import\s+numpy\.linalg', content, re.MULTILINE) or \
       re.search(r'^\s*from\s+numpy\.linalg\s+import', content, re.MULTILINE):
        return False, f"{module_name} illegally imports numpy.linalg"
        
    # Make sure the code wasn't just replaced with a trivial hardcoded return
    # A basic numerical algorithm implementation should have multiple lines.
    if len(content.split('\n')) < 10:
        return False, f"{module_name} implementation is too short, suspected hardcoding"

    return True, "Passed"


def verify_scientific_library(traj, env_info, task_info):
    """
    Verify the scientific library task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve and parse the result JSON exported from the container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/scientific_library_result.json", temp_result.name)
        if not os.path.exists(temp_result.name) or os.path.getsize(temp_result.name) == 0:
            return {"passed": False, "score": 0, "feedback": "Result JSON not found or empty."}
            
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed reading results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    test_report = result.get("test_report", {})
    files = result.get("files", {})
    task_start = result.get("task_start_time", 0)

    score = 0
    feedback_parts = []
    
    modules_to_test = [
        ("integration", "numlib/integration.py"),
        ("ode_solver", "numlib/ode_solver.py"),
        ("linear_algebra", "numlib/linear_algebra.py"),
        ("interpolation", "numlib/interpolation.py"),
        ("root_finder", "numlib/root_finder.py")
    ]

    for test_key, file_path in modules_to_test:
        file_info = files.get(file_path, {})
        mtime = file_info.get("mtime", 0)
        
        # Did the agent modify the file?
        if mtime <= task_start and task_start > 0:
            feedback_parts.append(f"[-] {test_key}: File was not modified")
            continue
            
        # Is the test passing?
        test_status = test_report.get(test_key, {})
        if test_status.get("passed", False):
            # Anti-gaming checks (scipy imports, hardcoded returns)
            ag_passed, ag_reason = check_anti_gaming(file_info, file_path)
            if ag_passed:
                score += 20
                feedback_parts.append(f"[+] {test_key}: Fixed successfully (20/20)")
            else:
                feedback_parts.append(f"[-] {test_key}: Anti-gaming violation ({ag_reason}) (0/20)")
        else:
            error_msg = test_status.get("error", "Unknown error").split('\n')[-1]
            feedback_parts.append(f"[-] {test_key}: Still failing ({error_msg[:40]}...) (0/20)")

    # -------------------------------------------------------------------------
    # VLM Verification of Trajectory
    # -------------------------------------------------------------------------
    vlm_feedback = ""
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            vlm_res = query_vlm(
                prompt=VERIFICATION_PROMPT,
                images=frames
            )
            
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if not parsed.get("edited_files"):
                    vlm_feedback = " (VLM Note: Agent did not appear to actively edit files in VS Code)"
                elif not parsed.get("executed_tests"):
                    vlm_feedback = " (VLM Note: Tests were not seen executed in terminal)"
                else:
                    vlm_feedback = " (VLM verified IDE interaction)"

    final_feedback = " | ".join(feedback_parts) + vlm_feedback
    pass_threshold = task_info.get("metadata", {}).get("pass_threshold", 60)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }