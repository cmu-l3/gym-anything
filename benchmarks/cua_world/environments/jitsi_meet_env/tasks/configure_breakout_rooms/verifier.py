#!/usr/bin/env python3
"""
Verifier for configure_breakout_rooms task.

Strategy:
1. File Verification (20 pts): Check if evidence screenshot exists and was created during task.
2. VLM Evidence Verification (40 pts): Analyze the user-saved screenshot for specific room names.
3. VLM Trajectory Verification (40 pts): Analyze agent workflow (joining, opening panel, typing).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_breakout_rooms(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    expected_rooms = metadata.get('expected_rooms', ["Revenue Strategy", "Operations Review", "Product Roadmap"])
    
    # 1. Load result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # ------------------------------------------------------------------
    # CRITERION 1: Evidence File Checks (Max 20 pts)
    # ------------------------------------------------------------------
    evidence_exists = result_data.get('evidence_exists', False)
    evidence_fresh = result_data.get('evidence_created_during_task', False)
    evidence_size = result_data.get('evidence_size_bytes', 0)

    if evidence_exists and evidence_fresh and evidence_size > 5000: # >5KB
        score += 20
        feedback.append("Evidence screenshot saved correctly.")
    elif evidence_exists:
        score += 10
        feedback.append("Evidence screenshot exists but timestamp/size check warning.")
    else:
        feedback.append("Evidence screenshot not found.")

    # ------------------------------------------------------------------
    # CRITERION 2: VLM Evidence Analysis (Max 40 pts)
    # ------------------------------------------------------------------
    # We need to analyze the specific screenshot the agent saved: ~/breakout_rooms_evidence.png
    # We must copy it out of the container first.
    
    evidence_valid = False
    
    if evidence_exists:
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(result_data['evidence_path'], temp_img.name)
            
            prompt = f"""
            Analyze this screenshot of a Jitsi Meet interface.
            
            Goal: Verify that specific breakout rooms were created.
            
            Look for a "Breakout Rooms" panel or list.
            Check if EXACTLY these room names are visible:
            1. "{expected_rooms[0]}"
            2. "{expected_rooms[1]}"
            3. "{expected_rooms[2]}"
            
            Return JSON:
            {{
                "breakout_panel_visible": true/false,
                "room_1_visible": true/false,
                "room_2_visible": true/false,
                "room_3_visible": true/false,
                "total_rooms_count": int,
                "all_names_correct": true/false
            }}
            """
            
            vlm_out = query_vlm(prompt=prompt, image=temp_img.name)
            
            if vlm_out.get('success'):
                parsed = vlm_out.get('parsed', {})
                if parsed.get('breakout_panel_visible'):
                    score += 10
                    
                    rooms_found = 0
                    if parsed.get('room_1_visible'): rooms_found += 1
                    if parsed.get('room_2_visible'): rooms_found += 1
                    if parsed.get('room_3_visible'): rooms_found += 1
                    
                    score += (rooms_found * 10) # Max 30
                    
                    if rooms_found == 3:
                        evidence_valid = True
                        feedback.append(f"VLM confirmed all 3 rooms: {expected_rooms}")
                    else:
                        feedback.append(f"VLM found {rooms_found}/3 expected rooms.")
                else:
                    feedback.append("VLM did not detect breakout rooms panel in evidence.")
            else:
                feedback.append("VLM analysis of evidence failed.")
                
        except Exception as e:
            feedback.append(f"Error analyzing evidence image: {str(e)}")
        finally:
            if os.path.exists(temp_img.name):
                os.unlink(temp_img.name)
    
    # ------------------------------------------------------------------
    # CRITERION 3: VLM Trajectory Verification (Max 40 pts)
    # ------------------------------------------------------------------
    # Analyze the workflow using trajectory frames
    frames = sample_trajectory_frames(traj, n=5)
    
    traj_prompt = """
    Analyze these frames of a user interacting with Jitsi Meet.
    
    Look for this workflow:
    1. Joining a meeting (entering name, clicking join).
    2. Opening a side panel (likely Breakout Rooms).
    3. Clicking "Add" or "Create" buttons for rooms.
    4. Typing or renaming rooms.
    
    Return JSON:
    {
        "joined_meeting": true/false,
        "opened_panel": true/false,
        "interacted_with_rooms": true/false,
        "confidence": "low/medium/high"
    }
    """
    
    traj_out = query_vlm(prompt=traj_prompt, images=frames)
    
    if traj_out.get('success'):
        parsed = traj_out.get('parsed', {})
        if parsed.get('joined_meeting'):
            score += 10
            feedback.append("Workflow: Joined meeting.")
        if parsed.get('opened_panel'):
            score += 15
            feedback.append("Workflow: Opened side panel.")
        if parsed.get('interacted_with_rooms'):
            score += 15
            feedback.append("Workflow: Interacted with room creation.")
    else:
        feedback.append("VLM trajectory analysis failed.")

    # ------------------------------------------------------------------
    # Final Scoring
    # ------------------------------------------------------------------
    # Pass threshold: 60 points AND valid evidence
    passed = (score >= 60) and evidence_valid

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }