#!/usr/bin/env python3
import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_firefox_memory_leak_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_diff_bytes = metadata.get('expected_diff_bytes', 1000000)  # 1 MB

    # Retrieve task result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    baseline_exists = result.get('baseline_exists', False)
    baseline_created = result.get('baseline_created_during_task', False)
    baseline_size = result.get('baseline_size', 0)

    leaked_exists = result.get('leaked_exists', False)
    leaked_created = result.get('leaked_created_during_task', False)
    leaked_size = result.get('leaked_size', 0)

    # 1. Baseline Snapshot (20 points)
    if baseline_exists and baseline_created:
        if baseline_size > 0:
            score += 20
            feedback_parts.append("Baseline snapshot created correctly.")
        else:
            score += 5
            feedback_parts.append("Baseline snapshot is empty.")
    elif baseline_exists:
        feedback_parts.append("Baseline snapshot exists but was not created during task.")
    else:
        feedback_parts.append("Baseline snapshot missing.")

    # 2. Leaked Snapshot (20 points)
    if leaked_exists and leaked_created:
        if leaked_size > 0:
            score += 20
            feedback_parts.append("Leaked snapshot created correctly.")
        else:
            score += 5
            feedback_parts.append("Leaked snapshot is empty.")
    elif leaked_exists:
        feedback_parts.append("Leaked snapshot exists but was not created during task.")
    else:
        feedback_parts.append("Leaked snapshot missing.")

    # 3. Leak Verification (Size) (30 points)
    size_diff = leaked_size - baseline_size
    leak_triggered = False
    if baseline_exists and leaked_exists and baseline_size > 0:
        if size_diff > expected_diff_bytes:
            score += 30
            leak_triggered = True
            feedback_parts.append(f"Memory leak verified: leaked snapshot is {size_diff / 1024 / 1024:.2f} MB larger.")
        elif size_diff > 0:
            score += 10
            feedback_parts.append(f"Slight memory increase detected ({size_diff / 1024:.2f} KB), but below expected leak size.")
        else:
            feedback_parts.append("No memory increase detected between snapshots. Leak was not triggered.")
    
    # 4. VLM Trajectory Verification (30 points)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=8)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            vlm_prompt = """
            Review these screenshots from a browser session. Did the user:
            1. Open the Developer Tools and navigate to the "Memory" tab?
            2. Interact with the web page by clicking buttons like "Load High-Res Gallery" and "Destroy Gallery"?
            
            Respond with JSON:
            {
                "devtools_memory_used": true/false,
                "page_interacted": true/false,
                "reasoning": "Explain what you see"
            }
            """
            
            vlm_response = query_vlm(images=images, prompt=vlm_prompt)
            
            # Safe JSON extraction
            parsed = {}
            if isinstance(vlm_response, dict):
                if "parsed" in vlm_response:
                    parsed = vlm_response["parsed"]
                else:
                    parsed = vlm_response
            elif isinstance(vlm_response, str):
                json_match = re.search(r'\{.*\}', vlm_response, re.DOTALL)
                if json_match:
                    try:
                        parsed = json.loads(json_match.group(0))
                    except Exception:
                        pass
            
            devtools_used = parsed.get("devtools_memory_used", False)
            page_interacted = parsed.get("page_interacted", False)
            
            if devtools_used:
                score += 15
                feedback_parts.append("VLM confirms DevTools Memory panel was used.")
            else:
                feedback_parts.append("VLM did not detect DevTools Memory panel usage.")
                
            if page_interacted:
                score += 15
                feedback_parts.append("VLM confirms page interaction.")
            else:
                feedback_parts.append("VLM did not detect expected page interactions.")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        feedback_parts.append(f"VLM check unavailable: {e}")
        # Give partial credit if we can't run VLM but files were created successfully
        if baseline_exists and leaked_exists and leak_triggered:
            score += 30

    key_criteria_met = (baseline_exists and leaked_exists and leak_triggered)
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }