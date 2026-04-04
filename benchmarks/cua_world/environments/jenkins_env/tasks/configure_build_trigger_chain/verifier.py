#!/usr/bin/env python3
"""
Verifier for configure_build_trigger_chain task.

Checks that three Jenkins jobs are properly chained with build triggers:
  inventory-build -> inventory-test -> inventory-deploy

Accepts either post-build action triggers or reverse build triggers.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_build_trigger_chain(traj, env_info, task_info):
    """
    Verify the build trigger chain configuration.
    
    Scoring:
    - Jobs exist: 10 pts
    - Link 1 (Build->Test) configured: 25 pts
    - Link 2 (Test->Deploy) configured: 25 pts
    - Thresholds correct (Success/Stable): 15 pts
    - Execution Chain Verified: 25 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/trigger_chain_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result file: {e}",
            "details": str(e)
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check jobs existence
    jobs = result.get("jobs_exist", {})
    if all(jobs.values()):
        score += 10
        feedback_parts.append("All jobs exist")
    else:
        feedback_parts.append(f"Missing jobs: {[k for k,v in jobs.items() if not v]}")

    # Anti-gaming check
    configs_changed = result.get("configs_changed", {})
    if not any(configs_changed.values()):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No job configurations were modified from baseline (Anti-gaming)"
        }

    # 2. Check Build -> Test Link
    link1_active = result.get("trigger_build_to_test", False)
    if link1_active:
        score += 25
        feedback_parts.append("Link Build->Test configured")
    else:
        feedback_parts.append("Link Build->Test MISSING")

    # 3. Check Test -> Deploy Link
    link2_active = result.get("trigger_test_to_deploy", False)
    if link2_active:
        score += 25
        feedback_parts.append("Link Test->Deploy configured")
    else:
        feedback_parts.append("Link Test->Deploy MISSING")

    # 4. Check Thresholds (Must be SUCCESS or STABLE, not FAILURE/UNSTABLE unless permitted)
    # UNSTABLE is arguably okay for some chains, but prompt asked for success.
    # Usually "SUCCESS" or "STABLE" in XML.
    th1 = result.get("trigger_threshold_build_test", "unknown").upper()
    th2 = result.get("trigger_threshold_test_deploy", "unknown").upper()
    
    thresholds_ok = True
    if link1_active and th1 not in ["SUCCESS", "STABLE"]:
        thresholds_ok = False
        feedback_parts.append(f"Link 1 threshold bad: {th1}")
    if link2_active and th2 not in ["SUCCESS", "STABLE"]:
        thresholds_ok = False
        feedback_parts.append(f"Link 2 threshold bad: {th2}")
        
    if thresholds_ok and (link1_active or link2_active):
        score += 15
        feedback_parts.append("Trigger thresholds correct")
    elif not (link1_active or link2_active):
        feedback_parts.append("No triggers to check thresholds")

    # 5. Chain Execution
    execution = result.get("chain_execution", {})
    all_success = execution.get("all_success", False)
    
    if all_success:
        score += 25
        feedback_parts.append("Chain execution verified successfully")
    elif execution.get("build_ran") and execution.get("test_ran") and execution.get("deploy_ran"):
        score += 20 # Ran but maybe not success status
        feedback_parts.append("Chain executed but status not fully success")
    elif execution.get("build_ran") and execution.get("test_ran"):
        score += 10 # Partial chain
        feedback_parts.append("Partial chain execution (Build->Test)")
    else:
        feedback_parts.append("Chain execution failed")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }