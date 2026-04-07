#!/usr/bin/env python3
"""
Verifier for esc_burn_in_jump_mission task.

Verification Strategy:
1. File exists & modified during task (10 pts)
2. WPNAV_SPEED parameter configured to 1200 on the live vehicle (15 pts)
3. Plan File Structural Verification:
   - Contains >= 4 NAV_WAYPOINT items (15 pts)
   - Contains a DO_JUMP item (command=177) (15 pts)
   - DO_JUMP repeat count (param 2) is exactly 25 (10 pts)
   - DO_JUMP target (param 1) points to a valid sequence number/waypoint (10 pts)
   - Contains an RTL item (command=20) (10 pts)
4. VLM Verification of trajectory (15 pts): Proves the agent actually interacted
   with the QGC UI, drawing the mission path.

Pass threshold: 75 points.
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# MAVLink Command ID mappings
CMD_WAYPOINT = 16
CMD_RTL = 20
CMD_DO_JUMP = 177

VERIFICATION_PROMPT = """You are verifying if an agent successfully planned a drone mission in QGroundControl.
Examine these screenshots from the agent's trajectory.

Look for the following:
1. Is the QGroundControl application open?
2. Did the agent navigate to the "Plan" view (the map interface with mission tools on the left/top)?
3. Is there a visible flight path drawn on the map (lines connecting numbered waypoints)?

Respond ONLY in JSON format:
{
    "qgc_visible": true/false,
    "plan_view_used": true/false,
    "flight_path_drawn": true/false,
    "confidence": "high/medium/low",
    "reasoning": "brief explanation"
}
"""


def verify_esc_burn_in_jump_mission(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')

    # 1. Read exported results from environment
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_file, tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f'Could not read export result: {e}'}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    details = {}

    # Check 1: File Existence & Timestamps (10 pts)
    file_found = result.get('file_found', False)
    modified = result.get('modified_during_task', False)
    
    if file_found and modified:
        score += 10
        feedback.append('Plan file exists and was created/modified during task (+10)')
    elif file_found:
        feedback.append('Plan file exists but was NOT modified during the task (+0/10)')
    else:
        feedback.append('Plan file not found at the expected path (+0/10)')

    # Check 2: WPNAV_SPEED Parameter (15 pts)
    params = result.get('params', {})
    wpnav_speed = params.get('WPNAV_SPEED')
    details['WPNAV_SPEED'] = wpnav_speed

    if wpnav_speed is not None:
        try:
            val = float(wpnav_speed)
            if abs(val - 1200.0) <= 5.0:
                score += 15
                feedback.append(f'WPNAV_SPEED={val:.0f} configured correctly (+15)')
            else:
                feedback.append(f'WPNAV_SPEED={val:.0f} (Expected 1200) (+0/15)')
        except ValueError:
            feedback.append(f'WPNAV_SPEED read invalid value (+0/15)')
    else:
        feedback.append('WPNAV_SPEED parameter could not be read from SITL (+0/15)')

    # Check 3-7: Parse Plan JSON Structure
    plan_content_raw = result.get('plan_content', '')
    if isinstance(plan_content_raw, str):
        plan_content_raw = plan_content_raw.replace('\\n', '\n').replace('\\t', '\t')
    
    try:
        plan = json.loads(plan_content_raw)
        items = plan.get('mission', {}).get('items', [])
        details['mission_item_count'] = len(items)
    except Exception as e:
        items = []
        feedback.append(f'Could not parse mission JSON: {e} (+0 for mission logic checks)')
    
    if items:
        # Check 3: Waypoint Count (15 pts)
        waypoints = [it for it in items if it.get('command') == CMD_WAYPOINT]
        wp_count = len(waypoints)
        details['waypoint_count'] = wp_count
        
        if wp_count >= 4:
            score += 15
            feedback.append(f'Found {wp_count} NAV_WAYPOINT items (+15)')
        elif wp_count > 0:
            score += 5
            feedback.append(f'Found only {wp_count} NAV_WAYPOINT items (need >= 4) (+5 partial)')
        else:
            feedback.append('No NAV_WAYPOINT items found (+0/15)')

        # Identify jump items and RTL items
        jump_items = [it for it in items if it.get('command') == CMD_DO_JUMP]
        rtl_items = [it for it in items if it.get('command') == CMD_RTL]
        
        # Check 4: DO_JUMP Present (15 pts)
        if jump_items:
            score += 15
            feedback.append('DO_JUMP command found in mission (+15)')
            
            # Check 5 & 6: DO_JUMP Configuration
            jump_item = jump_items[-1] # evaluate the last one if multiple exist
            j_params = jump_item.get('params', [])
            
            # DO_JUMP MAVLink mapping: param 1 = Sequence #, param 2 = Repeat Count
            # In QGC JSON plan: param[0] is Target seq, param[1] is Repeat count
            target_seq = j_params[0] if len(j_params) > 0 else None
            repeat_cnt = j_params[1] if len(j_params) > 1 else None
            
            details['do_jump_target'] = target_seq
            details['do_jump_repeat'] = repeat_cnt
            
            # Check Repeat Count (10 pts)
            if repeat_cnt is not None and abs(float(repeat_cnt) - 25.0) < 0.1:
                score += 10
                feedback.append('DO_JUMP repeat count is exactly 25 (+10)')
            else:
                feedback.append(f'DO_JUMP repeat count is {repeat_cnt} (Expected 25) (+0/10)')
                
            # Check Target Index Validity (10 pts)
            if target_seq is not None:
                seq_val = int(float(target_seq))
                # Validate that the targeted sequence number actually exists in the plan
                # Sequence numbers map to item indices generally, or at least must be > 0 and < current index
                if seq_val > 0 and seq_val < len(items):
                    score += 10
                    feedback.append(f'DO_JUMP target sequence ({seq_val}) is valid (+10)')
                else:
                    feedback.append(f'DO_JUMP target sequence ({seq_val}) seems out of bounds (+0/10)')
            else:
                feedback.append('DO_JUMP target sequence is missing (+0/10)')
        else:
            feedback.append('No DO_JUMP command found in mission (+0/15 for jump structure)')

        # Check 7: RTL Present (10 pts)
        if rtl_items:
            score += 10
            feedback.append('NAV_RETURN_TO_LAUNCH command found in mission (+10)')
        else:
            feedback.append('NAV_RETURN_TO_LAUNCH command missing (+0/10)')
    else:
        # If no items were parsed, make sure to penalize
        pass

    # Check 8: VLM Verification of Trajectory (15 pts)
    vlm_score = 0
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=3)
            final_frame = get_final_screenshot(traj)
            if final_frame:
                frames.append(final_frame)
                
            vlm_response = query_vlm(
                images=frames,
                prompt=VERIFICATION_PROMPT
            )
            
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                
                if parsed.get("qgc_visible") and parsed.get("plan_view_used"):
                    vlm_score += 5
                    if parsed.get("flight_path_drawn"):
                        vlm_score += 10
                        feedback.append('VLM: Agent successfully drew mission flight path (+15)')
                    else:
                        feedback.append('VLM: Agent used Plan view but flight path not clearly drawn (+5/15)')
                else:
                    feedback.append('VLM: Did not detect active use of QGC Plan view (+0/15)')
            else:
                feedback.append('VLM Error: Could not verify trajectory visual evidence (+0/15)')
                
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback.append('VLM Exception occurred (+0/15)')
    else:
        feedback.append('VLM not available, granting default partial credit for visual trajectory (+7/15)')
        vlm_score = 7
        
    score += vlm_score

    passed = score >= 75
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }