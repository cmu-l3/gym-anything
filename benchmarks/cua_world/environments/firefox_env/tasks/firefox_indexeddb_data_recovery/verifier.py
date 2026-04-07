#!/usr/bin/env python3
"""
Verifier for firefox_indexeddb_data_recovery task.

Checks:
1. Valid JSON file was exported to ~/Documents/MDR-3042119_report.json
2. File was created *during* the task (anti-gaming).
3. JSON contains correct report_number and device_name.
4. JSON contains the exact event_narrative from the hidden DB (anti-hallucination).
5. VLM trajectory verification: confirms DevTools/Web Console usage.
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_data_recovery(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/MDR-3042119_report.json')
    target_report_number = metadata.get('target_report_number', 'MDR-3042119')
    target_narrative_snippet = metadata.get('target_narrative_snippet', 'exhibited premature battery depletion')
    
    feedback_parts = []
    score = 0
    max_score = 100

    # 1. Read the framework's export manifest
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check if output file exists and was created during the task
    output_exists = export_result.get('output_exists', False)
    file_created_during_task = export_result.get('file_created_during_task', False)

    if not output_exists:
        feedback_parts.append("Output file NOT found")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
    
    score += 10
    feedback_parts.append("Output file exists")

    if file_created_during_task:
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("WARNING: File created before task start (possible gaming attempt)")
        # Penalty for gaming attempt, but proceed to check contents
        score -= 10

    # 3. Read the agent's extracted JSON file
    temp_json_dump = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    agent_data = None
    try:
        copy_from_env(expected_output_path, temp_json_dump.name)
        with open(temp_json_dump.name, 'r') as f:
            agent_data = json.load(f)
        score += 10
        feedback_parts.append("Valid JSON format")
    except json.JSONDecodeError:
        feedback_parts.append("Extracted file is not valid JSON")
    except Exception as e:
        feedback_parts.append(f"Failed to read extracted JSON: {e}")
    finally:
        if os.path.exists(temp_json_dump.name):
            os.unlink(temp_json_dump.name)

    # 4. Check JSON Integrity and Content (Anti-hallucination)
    content_matches = False
    if agent_data and isinstance(agent_data, dict):
        extracted_report_number = agent_data.get("report_number", "")
        extracted_narrative = agent_data.get("event_narrative", "")
        
        if extracted_report_number == target_report_number:
            score += 20
            feedback_parts.append("Correct Report ID found")
        else:
            feedback_parts.append(f"Incorrect Report ID: expected {target_report_number}, got {extracted_report_number}")

        if target_narrative_snippet in extracted_narrative:
            score += 30
            content_matches = True
            feedback_parts.append("Narrative text matches ground truth")
        else:
            feedback_parts.append("Narrative text missing or incorrect (Hallucination detected)")
    elif agent_data:
        feedback_parts.append("JSON is valid but not a single object dict (maybe exported an array or raw string)")

    # 5. VLM Trajectory Verification
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        if frames:
            prompt = (
                "You are evaluating an agent performing a web debugging task in Firefox. "
                "The user is supposed to extract a record from IndexedDB. "
                "Look closely at these trajectory screenshots. "
                "Did the agent at any point open the Firefox Developer Tools (F12, Inspect Element) AND "
                "either view the 'Storage' / 'IndexedDB' tab, OR execute JavaScript in the 'Web Console'? "
                "Answer clearly YES or NO at the very beginning of your response."
            )
            vlm_response = query_vlm(images=frames, prompt=prompt)
            
            if vlm_response:
                response_text = vlm_response.upper()
                if "YES" in response_text[:10]:
                    vlm_score = 30
                    feedback_parts.append("VLM confirms DevTools usage")
                else:
                    feedback_parts.append("VLM did not detect DevTools usage")
            else:
                feedback_parts.append("VLM verification failed to return a response")
        else:
            feedback_parts.append("No trajectory frames available for VLM")
    except Exception as e:
        feedback_parts.append(f"VLM verification error: {e}")

    score += vlm_score

    # Determine pass/fail
    key_criteria_met = file_created_during_task and content_matches and (vlm_score > 0)
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }