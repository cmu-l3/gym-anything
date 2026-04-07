#!/usr/bin/env python3
"""
Verifier for implement_log_analyzer task.

Evaluates the Python modules implemented by the agent against the original pytest suite.
Verifies via programmatic output and VLM trajectory checks (TDD workflow).
"""

import os
import json
import tempfile
import logging
import re

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are verifying if a developer actively completed a coding task in VS Code.

Look at these screenshots sampled from the session trajectory. Determine:
1. Did the agent write/edit actual Python code (other than just raising NotImplementedError)?
2. Did the agent use the integrated terminal to run tests (e.g., executing `pytest`)?

Respond in JSON format exactly like this:
{
    "edited_code": true/false,
    "ran_tests": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_log_analyzer(traj, env_info, task_info):
    """
    Verify the log_analyzer implementation task.
    Score breakdown:
      - 80 points: Pytest results (16 pts per module: parser, analyzer, filter, alerter, reporter)
      - 20 points: VLM trajectory check (Did they actively edit and test?)
    Pass threshold: >= 60 total score, AND at least some tests passing.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/log_analyzer_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    pytest_out = result.get('pytest_output', '')
    files = result.get('files', {})
    mtimes = result.get('mtimes', {})
    task_start = result.get('task_start_time', 0)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Anti-Gaming: Check File Modifications
    # ---------------------------------------------------------
    files_modified = 0
    for mod, mtime in mtimes.items():
        if mtime > task_start + 5:  # Adding small buffer
            files_modified += 1
            
    if files_modified == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ No source files were modified. Task was skipped."
        }

    # ---------------------------------------------------------
    # 2. Programmatic Verification: Pytest Outputs (80 points)
    # ---------------------------------------------------------
    test_mappings = {
        'test_parser': 3,
        'test_analyzer': 2,
        'test_filter': 2,
        'test_alerter': 2,
        'test_reporter': 1
    }
    
    test_score = 0
    passed_counts = {}
    
    for module, total in test_mappings.items():
        # Match lines like "tests/test_parser.py::test_parse_valid_line PASSED"
        passes = len(re.findall(f"{module}\\.py.*PASSED", pytest_out))
        # Handle case where file might have failed compilation/import
        if passes > total: passes = total  
        
        passed_counts[module] = passes
        module_pts = (passes / total) * 16.0
        test_score += module_pts
        
        if passes == total:
            feedback_parts.append(f"✅ {module}: All passing ({passes}/{total})")
        else:
            feedback_parts.append(f"⚠️ {module}: {passes}/{total} passing")

    score += test_score

    # Check for obvious AST hardcoding via remaining NotImplementedErrors
    stubs_left = sum(1 for src in files.values() if 'NotImplementedError' in src)
    if stubs_left > 0:
        feedback_parts.append(f"⚠️ Warning: {stubs_left} modules still contain NotImplementedError stubs.")

    # ---------------------------------------------------------
    # 3. VLM Verification: Workflow Analysis (20 points)
    # ---------------------------------------------------------
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            vlm_res = query_vlm(prompt=VERIFICATION_PROMPT, images=images)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                edited_code = parsed.get('edited_code', False)
                ran_tests = parsed.get('ran_tests', False)
                
                if edited_code:
                    vlm_score += 10
                    feedback_parts.append("✅ VLM confirmed code editing")
                if ran_tests:
                    vlm_score += 10
                    feedback_parts.append("✅ VLM confirmed TDD workflow (ran tests)")
            else:
                feedback_parts.append("⚠️ VLM verification failed to process")
        else:
            feedback_parts.append("⚠️ No images available for VLM verification")
            
    score += vlm_score

    # ---------------------------------------------------------
    # Final Decision
    # ---------------------------------------------------------
    total_score = int(score)
    # Agent must pass at least 4 tests programmatically to be considered passing
    total_passed_tests = sum(passed_counts.values())
    
    is_passing = total_score >= 60 and total_passed_tests >= 4
    
    status_icon = "🟢" if is_passing else "🔴"
    feedback = f"{status_icon} Score: {total_score}/100 | " + " | ".join(feedback_parts)

    return {
        "passed": is_passing,
        "score": total_score,
        "feedback": feedback,
        "details": {
            "test_passes": passed_counts,
            "files_modified": files_modified,
            "vlm_score": vlm_score,
            "pytest_log_excerpt": pytest_out[-500:] if pytest_out else "No output"
        }
    }