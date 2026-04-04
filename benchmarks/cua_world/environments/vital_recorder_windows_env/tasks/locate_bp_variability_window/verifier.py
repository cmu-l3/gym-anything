#!/usr/bin/env python3
"""
Verifier for locate_bp_variability_window task.

Verification Strategy:
1. Programmatic: Check if screenshot and report files exist and were created during the task.
2. Content Analysis: Parse the agent's text report for time window and MAP values.
3. Ground Truth: Compare reported time window with pre-calculated ground truth window.
4. VLM: Verify trajectory (zoom sequence) and final screenshot content (BP waveforms visible).
"""

import json
import os
import re
import tempfile
import logging
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import VLM utils if available in the environment
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
except ImportError:
    # Fallback/Mock for local testing
    def query_vlm(images, prompt):
        return {"success": False, "error": "VLM not available"}
    def get_final_screenshot(traj):
        return None
    def sample_trajectory_frames(traj, n):
        return []

def verify_locate_bp_variability_window(traj, env_info, task_info):
    """
    Verify the agent correctly identified and captured the BP variability window.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths in the guest (Windows)
    guest_result_path = "C:\\workspace\\tasks\\locate_bp_variability_window\\task_result.json"
    guest_gt_path = "C:\\workspace\\data\\ground_truth\\bp_variability_ground_truth.json"

    # Temporary files for host analysis
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name

    score = 0
    feedback_parts = []
    
    try:
        # 1. Fetch Result and Ground Truth
        try:
            copy_from_env(guest_result_path, temp_result)
            with open(temp_result, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        try:
            copy_from_env(guest_gt_path, temp_gt)
            with open(temp_gt, 'r') as f:
                gt_data = json.load(f)
        except Exception as e:
            logger.warning(f"Could not load ground truth: {e}")
            gt_data = {}

        # 2. Check File Existence & Anti-Gaming (20 pts)
        if result_data.get('screenshot_created_during_task'):
            score += 10
            feedback_parts.append("Screenshot created.")
        elif result_data.get('screenshot_exists'):
            feedback_parts.append("Screenshot exists but old timestamp (anti-gaming fail).")
        else:
            feedback_parts.append("Screenshot missing.")

        if result_data.get('report_created_during_task'):
            score += 10
            feedback_parts.append("Report created.")
        else:
            feedback_parts.append("Report missing.")

        # 3. Parse Report Content (30 pts)
        report_text = result_data.get('report_content', "")
        parsed_report = parse_report(report_text)
        
        if parsed_report['has_times']:
            score += 10
            feedback_parts.append("Report contains time window.")
        
        if parsed_report['has_map']:
            score += 10
            feedback_parts.append("Report contains MAP values.")

        if parsed_report['has_interpretation']:
            score += 10
            feedback_parts.append("Report contains interpretation.")

        # 4. Compare with Ground Truth (20 pts)
        # GT: Start 8, End 13 (Window center ~10.5)
        gt_start = gt_data.get('variability_window_start_min', 8)
        gt_end = gt_data.get('variability_window_end_min', 13)
        gt_center = (gt_start + gt_end) / 2
        
        agent_start = parsed_report.get('start_min')
        agent_end = parsed_report.get('end_min')

        overlap_score = 0
        if agent_start is not None and agent_end is not None:
            agent_center = (agent_start + agent_end) / 2
            # Allow +/- 5 minutes deviation on center
            if abs(agent_center - gt_center) <= 5.0:
                overlap_score = 20
                feedback_parts.append("Identified window matches ground truth.")
            elif abs(agent_center - gt_center) <= 10.0:
                overlap_score = 10
                feedback_parts.append("Identified window is close to ground truth.")
            else:
                feedback_parts.append(f"Window off target (Agent: {agent_center}, GT: {gt_center}).")
        
        score += overlap_score

        # 5. VLM Verification (30 pts)
        vlm_score = 0
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        if frames and final_img:
            prompt = """
            Analyze these screenshots of Vital Recorder software.
            1. Do the earlier frames show a 'zoomed out' view where a long timeline is visible?
            2. Does the final screenshot show a 'zoomed in' view of specific waveforms?
            3. Are Arterial Blood Pressure (ART/ABP/BP) waveforms visible in the final view?
            
            Return JSON: {"zoomed_out_seen": bool, "zoomed_in_final": bool, "bp_visible": bool}
            """
            vlm_res = query_vlm(images=frames + [final_img], prompt=prompt)
            
            if vlm_res.get('success'):
                parsed_vlm = vlm_res.get('parsed', {})
                if parsed_vlm.get('zoomed_out_seen'):
                    vlm_score += 10
                if parsed_vlm.get('zoomed_in_final'):
                    vlm_score += 10
                if parsed_vlm.get('bp_visible'):
                    vlm_score += 10
                feedback_parts.append(f"VLM verification: {vlm_score}/30 pts.")
            else:
                feedback_parts.append("VLM verification failed.")
        
        score += vlm_score

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_result): os.unlink(temp_result)
        if os.path.exists(temp_gt): os.unlink(temp_gt)

    passed = score >= 55 and result_data.get('screenshot_created_during_task') and result_data.get('report_created_during_task')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }

def parse_report(text: str) -> Dict[str, Any]:
    """
    Heuristic parsing of the agent's report.
    Expected: Start Time: X, End Time: Y, MAP Range: A-B
    """
    info = {
        "has_times": False,
        "has_map": False,
        "has_interpretation": False,
        "start_min": None,
        "end_min": None
    }
    
    if not text:
        return info

    lower_text = text.lower()
    
    # Simple regex for times (e.g., "Start: 10", "10 min")
    # Looks for numbers near "start" or "begin"
    start_match = re.search(r'(start|begin).*?(\d+(\.\d+)?)', lower_text)
    end_match = re.search(r'(end|finish).*?(\d+(\.\d+)?)', lower_text)
    
    if start_match:
        try:
            info['start_min'] = float(start_match.group(2))
        except: pass
    
    if end_match:
        try:
            info['end_min'] = float(end_match.group(2))
        except: pass

    if info['start_min'] is not None and info['end_min'] is not None:
        info['has_times'] = True

    # Check for MAP/BP range numbers
    if re.search(r'\d+\s*-\s*\d+', lower_text) or re.search(r'\d+\s*to\s*\d+', lower_text):
        info['has_map'] = True
    
    # Check for text that looks like a sentence (interpretation)
    lines = [l.strip() for l in text.split('\n') if len(l.strip()) > 10]
    # If there's text that isn't just numbers/labels
    if len(lines) >= 3: # Title + Data + Sentence
        info['has_interpretation'] = True
        
    return info