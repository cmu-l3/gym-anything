#!/usr/bin/env python3
"""Verifier for debug_fix_deadlock task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_debug_fix_deadlock(traj, env_info, task_info):
    """
    Verify that the deadlock was diagnosed and fixed.
    
    Criteria:
    1. Simulation Execution (40 pts): Code compiles and runs without hanging.
    2. Analysis Report (20 pts): 'analysis.txt' correctly names threads.
    3. Code Logic (30 pts): 'TransferService.java' uses ID-based ordering.
    4. VLM Verification (10 pts): Visual evidence of Debugger usage.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # --- Load Result JSON ---
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # --- Criterion 1: Simulation Execution (40 pts) ---
    exec_status = result.get("execution_status", "unknown")
    output = result.get("execution_output", "")
    
    if exec_status == "success":
        if "SIMULATION COMPLETED" in output:
            score += 40
            feedback_parts.append("Simulation execution successful (Deadlock fixed)")
        else:
            score += 20
            feedback_parts.append("Simulation ran but output was unexpected")
    elif exec_status == "timeout_deadlock":
        feedback_parts.append("FAIL: Simulation timed out (Deadlock still present)")
    elif exec_status == "compile_failed":
        feedback_parts.append("FAIL: Code did not compile")
    else:
        feedback_parts.append(f"FAIL: Execution error ({exec_status})")

    # --- Criterion 2: Analysis Report (20 pts) ---
    analysis_content = result.get("analysis_content", "").lower()
    if result.get("analysis_exists"):
        # Check for thread names "Transfer-Worker-A" and "Transfer-Worker-B"
        # The user might write "Worker-A", "Thread-A", etc. Be slightly flexible but require "A" and "B"
        has_a = "worker-a" in analysis_content or "thread-0" in analysis_content or "transfer-worker-a" in analysis_content
        has_b = "worker-b" in analysis_content or "thread-1" in analysis_content or "transfer-worker-b" in analysis_content
        
        if has_a and has_b:
            score += 20
            feedback_parts.append("Analysis report correctly identifies threads")
        else:
            score += 10
            feedback_parts.append("Analysis report exists but thread names unclear")
    else:
        feedback_parts.append("No analysis.txt found")

    # --- Criterion 3: Code Logic (30 pts) ---
    code = result.get("code_content", "")
    
    # Check 1: Still uses synchronization (didn't just delete locks)
    if "synchronized" in code:
        # Check 2: Uses ID-based ordering
        # Look for pattern where they compare IDs or order locks
        # Common patterns: 
        #   if (from.getId() < to.getId()) ...
        #   first = (from.id < to.id) ? from : to;
        uses_ordering = False
        
        if "getId()" in code or ".id" in code:
            if "<" in code or ">" in code or "compareTo" in code:
                uses_ordering = True
        
        if uses_ordering:
            score += 30
            feedback_parts.append("Code uses ID-based lock ordering")
        else:
            # If they solved it by running successfully but we can't statically detect ordering,
            # we rely on the execution score. But if execution failed, this confirms why.
            feedback_parts.append("Could not detect explicit ordering logic in code")
    else:
        feedback_parts.append("FAIL: 'synchronized' keyword removed (not thread safe)")

    # --- Criterion 4: VLM Verification (10 pts) ---
    # Import VLM utils
    try:
        from eclipse_verification_utils import vlm_verify_eclipse_task
        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Debug a deadlock and identify stuck threads",
            checklist_items=[
                "Debug perspective is open",
                "Debug view shows suspended threads",
                "Threads named 'Transfer-Worker' are visible",
                "Editor shows TransferService.java being modified"
            ]
        )
        
        if vlm_result and vlm_result.get("vlm_passed"):
            score += 10
            feedback_parts.append("VLM: Debugger usage verified")
        else:
            feedback_parts.append("VLM: Debugger usage not clearly seen")
            
    except ImportError:
        pass # Skip VLM if dependencies missing

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }