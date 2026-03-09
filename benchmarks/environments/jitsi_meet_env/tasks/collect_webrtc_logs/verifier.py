#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_collect_webrtc_logs(traj, env_info, task_info):
    """
    Verify the collect_webrtc_logs task.
    
    Criteria:
    1. Log file exists and was created during task.
    2. Log file contains valid Jitsi Meet keywords (e.g., JitsiMeetJS, conference).
    3. Evidence screenshot was created by agent.
    4. VLM verifies DevTools Console is open and meeting room is correct.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_keywords = metadata.get('required_keywords', ["JitsiMeetJS", "conference", "xmpp"])
    
    score = 0
    feedback_parts = []
    
    # 1. Load result JSON
    result_data = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check Log File Existence & Timing (20 pts)
    log_exists = result_data.get("log_file_exists", False)
    log_created = result_data.get("log_file_created_during_task", False)
    log_size = result_data.get("log_file_size", 0)
    
    if log_exists and log_created and log_size > 100:
        score += 20
        feedback_parts.append("Log file created successfully")
    elif log_exists:
        score += 5
        feedback_parts.append("Log file exists but timing/size issues")
    else:
        feedback_parts.append("Log file missing")

    # 3. Check Log Content (30 pts)
    # We need to copy the log file out to verify its content matches a real Jitsi log
    keywords_found = 0
    if log_exists:
        temp_log = tempfile.NamedTemporaryFile(delete=False, suffix='.log')
        try:
            copy_from_env(result_data.get("log_file_path", "/home/ga/jitsi_debug.log"), temp_log.name)
            with open(temp_log.name, 'r', errors='ignore') as f:
                content = f.read()
                
                # Check for keywords
                found_list = []
                for kw in required_keywords:
                    if kw.lower() in content.lower():
                        keywords_found += 1
                        found_list.append(kw)
                
                if keywords_found >= 2:
                    score += 30
                    feedback_parts.append(f"Valid log content verified ({', '.join(found_list)})")
                elif keywords_found == 1:
                    score += 15
                    feedback_parts.append(f"Weak log content verified ({', '.join(found_list)})")
                else:
                    feedback_parts.append("Log file content does not look like Jitsi logs")
                    
        except Exception as e:
            feedback_parts.append(f"Failed to verify log content: {str(e)}")
        finally:
            if os.path.exists(temp_log.name):
                os.unlink(temp_log.name)
    
    # 4. Check Agent's Evidence Screenshot (10 pts)
    evidence_exists = result_data.get("evidence_screenshot_exists", False)
    if evidence_exists:
        score += 10
        feedback_parts.append("Evidence screenshot saved")
    
    # 5. VLM Verification (40 pts)
    # We verify the system-captured final screenshot or trajectory frames to confirm DevTools was used.
    # We do NOT rely solely on the agent's screenshot as that could be spoofed.
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    # Add final screen to frames if not None
    if final_screen:
        frames.append(final_screen)
        
    if not frames:
        feedback_parts.append("No screenshots available for VLM verification")
    else:
        prompt = (
            "Analyze these screenshots of a Jitsi Meet session in Firefox. "
            "I am looking for two things:\n"
            "1. Are the Firefox Developer Tools (specifically the Console tab) visible? "
            "Look for a split pane with text logs, usually at the bottom or side.\n"
            "2. Is the user in a meeting room named 'FinanceTroubleshoot'? "
            "Look for the room name in the URL bar (e.g., .../FinanceTroubleshoot) or on the meeting screen.\n\n"
            "Return JSON with keys: 'devtools_visible' (bool), 'console_tab_active' (bool), "
            "'room_name_correct' (bool), 'reasoning' (str)."
        )
        
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            parsed = vlm_res.get('parsed', {})
            
            # Score VLM findings
            if parsed.get('devtools_visible', False):
                score += 20
                feedback_parts.append("VLM confirmed DevTools visible")
                if parsed.get('console_tab_active', False):
                    score += 10
                    feedback_parts.append("VLM confirmed Console tab active")
                else:
                    feedback_parts.append("VLM could not confirm Console tab specifically")
            else:
                feedback_parts.append("VLM did not see Developer Tools")
                
            if parsed.get('room_name_correct', False):
                score += 10
                feedback_parts.append("VLM confirmed correct room")
            else:
                feedback_parts.append("VLM could not confirm room name")
                
        except Exception as e:
            logger.error(f"VLM error: {e}")
            feedback_parts.append("VLM verification failed due to error")

    # Pass logic: Must have log file with valid content (hard requirement)
    passed = (score >= 60) and (keywords_found >= 1)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }