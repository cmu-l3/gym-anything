#!/usr/bin/env python3
"""Verifier for extract_aggregated_dive_stats task.

Checks that the agent created training_stats.txt with the correct aggregated metrics,
and uses VLM to verify that the GUI multi-selection feature was used.
"""

import os
import re
import json
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_duration_to_minutes(duration_str):
    """Parses '43:00 min' to 43.0 minutes."""
    try:
        time_part = duration_str.split(' ')[0]
        parts = time_part.split(':')
        if len(parts) == 2:
            return int(parts[0]) + int(parts[1]) / 60.0
        elif len(parts) == 3:
            return int(parts[0]) * 60 + int(parts[1]) + int(parts[2]) / 60.0
    except Exception:
        pass
    return 0.0

def parse_depth_to_meters(depth_str):
    """Parses '30.5 m' to 30.5."""
    try:
        return float(depth_str.replace(' m', '').strip())
    except Exception:
        return 0.0

def verify_extract_aggregated_dive_stats(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_dives = [str(n) for n in metadata.get('target_dives', [2, 3, 4])]
    time_tolerance = metadata.get('time_tolerance_min', 2.0)
    depth_tolerance = metadata.get('depth_tolerance_m', 0.5)

    score = 0
    feedback_parts = []

    # 1. Read the task result JSON
    result_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_tmp.close()
    try:
        copy_from_env('/tmp/task_result.json', result_tmp.name)
        with open(result_tmp.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(result_tmp.name):
            os.unlink(result_tmp.name)

    output_exists = task_result.get('output_exists', False)
    file_created_during_task = task_result.get('file_created_during_task', False)

    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "training_stats.txt was not created"}
    
    if file_created_during_task:
        score += 10
        feedback_parts.append("File created during task (+10)")
    else:
        feedback_parts.append("Warning: File timestamp indicates it might not have been created during task")

    # 2. Extract agent's answers
    agent_stats_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    agent_stats_tmp.close()
    agent_time = None
    agent_depth = None
    
    try:
        copy_from_env('/home/ga/Documents/training_stats.txt', agent_stats_tmp.name)
        with open(agent_stats_tmp.name, 'r') as f:
            content = f.read()
            
        time_match = re.search(r'Total Time:\s*([\d\.]+)', content, re.IGNORECASE)
        depth_match = re.search(r'Max Depth:\s*([\d\.]+)', content, re.IGNORECASE)
        
        if time_match:
            agent_time = float(time_match.group(1))
        if depth_match:
            agent_depth = float(depth_match.group(1))
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse training_stats.txt: {e}"}
    finally:
        if os.path.exists(agent_stats_tmp.name):
            os.unlink(agent_stats_tmp.name)

    if agent_time is None or agent_depth is None:
        return {"passed": False, "score": score, "feedback": f"Failed to extract numeric values from training_stats.txt using required format. Found: {content[:100]}"}

    # 3. Calculate ground truth from XML
    ssrf_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.ssrf')
    ssrf_tmp.close()
    
    gt_total_time = 0.0
    gt_max_depth = 0.0
    
    try:
        copy_from_env('/home/ga/Documents/dives.ssrf', ssrf_tmp.name)
        tree = ET.parse(ssrf_tmp.name)
        root = tree.getroot()
        
        for dive in root.iter('dive'):
            if dive.get('number') in target_dives:
                # Add time
                duration_str = dive.get('duration', '')
                gt_total_time += parse_duration_to_minutes(duration_str)
                
                # Check max depth
                depth_elem = dive.find('depth')
                if depth_elem is not None:
                    max_d_str = depth_elem.get('max', '')
                    d_val = parse_depth_to_meters(max_d_str)
                    if d_val > gt_max_depth:
                        gt_max_depth = d_val
    except Exception as e:
        logger.error(f"Failed to parse ground truth from SSRF: {e}")
    finally:
        if os.path.exists(ssrf_tmp.name):
            os.unlink(ssrf_tmp.name)

    if gt_total_time == 0.0 or gt_max_depth == 0.0:
        return {"passed": False, "score": score, "feedback": "Failed to establish ground truth from dive log."}

    # 4. Compare Agent vs Ground Truth
    time_correct = abs(agent_time - gt_total_time) <= time_tolerance
    depth_correct = abs(agent_depth - gt_max_depth) <= depth_tolerance
    
    if time_correct:
        score += 30
        feedback_parts.append(f"Total time correct ({agent_time} ~= {gt_total_time:.1f}) (+30)")
    else:
        feedback_parts.append(f"Total time incorrect (got {agent_time}, expected ~{gt_total_time:.1f})")

    if depth_correct:
        score += 30
        feedback_parts.append(f"Max depth correct ({agent_depth} ~= {gt_max_depth:.1f}) (+30)")
    else:
        feedback_parts.append(f"Max depth incorrect (got {agent_depth}, expected ~{gt_max_depth:.1f})")

    # 5. VLM Verification (Anti-Gaming)
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=5)
        
        prompt = (
            "You are verifying if an AI agent correctly used the Subsurface application GUI. "
            "Look at these trajectory screenshots and determine: "
            "1. Did the agent highlight multiple dives in the main dive list simultaneously? "
            "2. Did the agent open or view the 'Stats' (Statistics) tab in the lower notebook panel? "
            "Respond in JSON format: "
            '{"multi_selected": true/false, "stats_tab_visible": true/false}'
        )
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        parsed = vlm_res.get('parsed', {})
        
        multi_selected = parsed.get('multi_selected', False)
        stats_visible = parsed.get('stats_tab_visible', False)
        
        if multi_selected and stats_visible:
            score += 30
            feedback_parts.append("VLM verified GUI multi-selection and Stats tab usage (+30)")
        else:
            feedback_parts.append(f"VLM verification missing GUI evidence (multi_selected: {multi_selected}, stats_visible: {stats_visible})")
            
    except Exception as e:
        logger.warning(f"VLM check failed or not available: {e}")
        feedback_parts.append("VLM check skipped or failed.")

    # Passed if score >= 70
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }