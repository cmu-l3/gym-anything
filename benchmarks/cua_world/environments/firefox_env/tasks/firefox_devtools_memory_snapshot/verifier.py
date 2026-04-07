#!/usr/bin/env python3
"""
Verifier for firefox_devtools_memory_snapshot task.

Verification Strategy:
1. File Existence: Check if heap_analysis.fxsnapshot was created.
2. File Timestamps: Check if it was created during the task run (Anti-Gaming).
3. File Size: A genuine heap snapshot is > 1MB. Empty or text files will fail.
4. Engine Signature: Scan for Firefox SpiderMonkey heap dump internals.
5. Leak Signature: Scan for 'LEAKED_STRING_DATA_' to prove the agent correctly triggered the leak BEFORE taking the snapshot.
6. VLM Trajectory Check: Visually verify the agent navigated to the Firefox DevTools Memory tab.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_memory_snapshot(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_size_bytes = metadata.get('min_file_size_bytes', 1048576)

    # 1. Retrieve programmatic results from the environment
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result JSON: {e}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    score = 0
    feedback = []

    # 2. Evaluate Programmatic Checks
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    output_size_bytes = int(result.get('output_size_bytes', 0))
    contains_engine_sig = result.get('contains_engine_sig', False)
    contains_leak_sig = result.get('contains_leak_sig', False)

    if output_exists:
        score += 10
        feedback.append("Snapshot file exists.")
    else:
        feedback.append("Snapshot file was NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    if file_created_during_task:
        score += 10
        feedback.append("File created during the task run.")
    else:
        feedback.append("Warning: File timestamp predates task start.")

    if output_size_bytes >= min_size_bytes:
        score += 10
        feedback.append(f"File size is valid ({output_size_bytes / 1024 / 1024:.2f} MB).")
    else:
        feedback.append(f"File size too small ({output_size_bytes} bytes).")

    if contains_engine_sig:
        score += 20
        feedback.append("Valid Firefox SpiderMonkey engine signature found.")
    else:
        feedback.append("Missing engine signatures (not a real snapshot).")

    if contains_leak_sig:
        score += 20
        feedback.append("Leak signature found (Agent triggered leak before snapshot).")
    else:
        feedback.append("Leak signature missing! Agent took snapshot BEFORE clicking the button.")

    # 3. Evaluate VLM (Visual Trajectory)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        if frames:
            prompt = """
            You are verifying a web developer task in Firefox.
            Look at these frames from the agent's workflow.
            
            Did the agent open the Firefox Developer Tools (Inspector/Console pane) AND navigate to the 'Memory' tab?
            We are looking for evidence that the DevTools panel is open at the bottom or side of the browser, and the 'Memory' tool is active.
            
            Return a JSON response with:
            {
                "devtools_opened": true/false,
                "memory_tab_active": true/false,
                "reasoning": "Brief explanation"
            }
            """
            
            vlm_response = query_vlm(images=frames, prompt=prompt)
            if vlm_response and vlm_response.get("parsed"):
                parsed = vlm_response["parsed"]
                if parsed.get("devtools_opened") and parsed.get("memory_tab_active"):
                    score += 30
                    feedback.append("VLM confirmed DevTools Memory tab was used.")
                else:
                    feedback.append(f"VLM verification failed: {parsed.get('reasoning')}")
            else:
                feedback.append("VLM check did not return expected format.")
    except ImportError:
        logger.warning("VLM module unavailable, skipping visual check.")
        # Re-weight score if VLM is completely unavailable so 100 is still possible
        score = int(score / 70 * 100)
    except Exception as e:
        logger.error(f"VLM verification error: {e}")

    # 4. Final Verification Logic
    # CRITICAL: File must exist, and MUST contain the leak signature (proves they followed workflow order)
    key_criteria_met = output_exists and file_created_during_task and contains_leak_sig and contains_engine_sig
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "output_exists": output_exists,
            "created_during_task": file_created_during_task,
            "size_bytes": output_size_bytes,
            "contains_engine_sig": contains_engine_sig,
            "contains_leak_sig": contains_leak_sig
        }
    }