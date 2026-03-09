#!/usr/bin/env python3
"""
Verifier for create_jpms_module task.

Verifies:
1. module-info.java creation and content (correct requires/exports).
2. Compilation success.
3. Report file content.
4. VLM verification of the process.
"""

import json
import re
import tempfile
import os
import logging
import sys

# Import VLM utils
sys.path.insert(0, '/workspace/utils')
try:
    from eclipse_verification_utils import vlm_verify_eclipse_task
except ImportError:
    vlm_verify_eclipse_task = None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_jpms_module(traj, env_info, task_info):
    """
    Verify the JPMS module creation task.
    
    Scoring Breakdown (Total 100):
    - module-info.java exists & created during task: 10 pts
    - Module name 'com.appcore': 10 pts
    - Required modules (java.net.http, java.sql, java.logging): 15 pts (5 each)
    - Exported packages (api, model): 10 pts (5 each)
    - Internal packages NOT exported (data, logging): 10 pts (5 each)
    - Project Compiles: 25 pts
    - Report file correct: 10 pts
    - VLM Verification: 10 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Copy result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Check file existence and creation time (10 pts)
    if result.get('module_info_exists', False):
        if result.get('file_created_during_task', False):
            score += 10
            feedback.append("module-info.java created during task.")
        else:
            score += 5
            feedback.append("module-info.java exists but timestamp check failed (pre-existing?).")
    else:
        feedback.append("FAIL: module-info.java not found.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    content = result.get('module_info_content', '')
    
    # 2. Check Module Name (10 pts)
    # Regex for 'module com.appcore {' allowing for whitespace
    if re.search(r'module\s+com\.appcore\s*\{', content):
        score += 10
        feedback.append("Correct module name.")
    else:
        feedback.append("FAIL: Module name incorrect or syntax invalid.")

    # 3. Check Requires (15 pts)
    required_modules = metadata.get('required_modules', [])
    for mod in required_modules:
        if re.search(rf'requires\s+{re.escape(mod)}\s*;', content):
            score += 5
            feedback.append(f"Requirement '{mod}' found.")
        else:
            feedback.append(f"FAIL: Missing requirement '{mod}'.")

    # 4. Check Exports (10 pts)
    exported_packages = metadata.get('exported_packages', [])
    for pkg in exported_packages:
        if re.search(rf'exports\s+{re.escape(pkg)}\s*;', content):
            score += 5
            feedback.append(f"Export '{pkg}' found.")
        else:
            feedback.append(f"FAIL: Missing export '{pkg}'.")

    # 5. Check Internal Encapsulation (10 pts)
    internal_packages = metadata.get('internal_packages', [])
    for pkg in internal_packages:
        if re.search(rf'exports\s+{re.escape(pkg)}\s*;', content):
            feedback.append(f"FAIL: Internal package '{pkg}' was exported (should be hidden).")
        else:
            score += 5
            feedback.append(f"Internal package '{pkg}' correctly hidden.")

    # 6. Compilation Success (25 pts)
    if result.get('compile_success', False):
        score += 25
        feedback.append("Project compiles successfully.")
    else:
        feedback.append("FAIL: Project compilation failed.")
        # Add compile output to feedback for debugging (truncated)
        compile_out = result.get('compile_output', '')
        if compile_out:
            feedback.append(f"Compiler output: {compile_out[:200]}...")

    # 7. Report File (10 pts)
    if result.get('report_exists', False):
        report_content = result.get('report_content', '').strip().split('\n')
        # Simple check: 3 lines, contains module name, requires, exports
        if len(report_content) >= 3:
            pts = 0
            if "com.appcore" in report_content[0]: pts += 3
            if "java.net.http" in report_content[1] and "java.sql" in report_content[1]: pts += 4
            if "com.appcore.api" in report_content[2] and "com.appcore.model" in report_content[2]: pts += 3
            score += pts
            feedback.append(f"Report file content valid ({pts}/10 pts).")
        else:
            feedback.append("Report file exists but format is incorrect (needs 3 lines).")
    else:
        feedback.append("Report file not found.")

    # 8. VLM Verification (10 pts)
    if vlm_verify_eclipse_task:
        vlm_res = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Create JPMS module-info.java for 'ModularApp'",
            checklist_items=[
                "Eclipse IDE is open with 'ModularApp' in Package Explorer",
                "User created 'module-info.java' in 'src'",
                "Editor shows 'module com.appcore'",
                "No red error markers on the project after changes"
            ]
        )
        if vlm_res and vlm_res.get('vlm_passed'):
            score += 10
            feedback.append("VLM: Workflow verified visually.")
        else:
            feedback.append(f"VLM: Visual verification failed or unavailable. {vlm_res.get('vlm_feedback','') if vlm_res else ''}")
    else:
        # Fallback if VLM not available, give points if compilation passed
        if result.get('compile_success', False):
            score += 10
            feedback.append("VLM unavailable, awarding points based on compilation.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }