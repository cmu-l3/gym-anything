#!/usr/bin/env python3
"""
Verifier for extract_yearly_stats task.

Multi-Criteria Evaluation:
1. Verify `yearly_stats.png` was created successfully (Anti-gaming check)
2. Verify `2011_summary.txt` exists and matches the required layout
3. Dynamically evaluate the "Dives" value against ground truth
4. Dynamically evaluate the "Max Depth" value against ground truth
5. Trajectory Verification using a VLM to ensure Yearly Stats was viewed
"""

import re
import json
import os
import tempfile
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_extract_yearly_stats(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available in environment info."}

    feedback = []
    score = 0

    # 1. Read exported JSON result
    result_json = {}
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result_json = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task_result.json: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # 2. Extract ground truth directly from the untampered sample file
    gt_dives = 0
    gt_max_depth = 0.0
    tmp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ssrf')
    tmp_xml.close()
    
    try:
        # We copy from the readonly sample source to prevent agent manipulation cheating
        copy_from_env("/opt/subsurface_data/SampleDivesV2.ssrf", tmp_xml.name)
        tree = ET.parse(tmp_xml.name)
        root = tree.getroot()
        
        for dive in root.iter('dive'):
            if dive.get('date', '').startswith('2011'):
                gt_dives += 1
                for dc in dive.iter('divecomputer'):
                    for depth_node in dc.iter('depth'):
                        d_str = depth_node.get('max', '0 m')
                        try:
                            d_val = float(d_str.replace('m', '').strip())
                            if d_val > gt_max_depth:
                                gt_max_depth = d_val
                        except ValueError:
                            pass
    except Exception as e:
        # Fallback to known values for this specific sample dataset if parsing fails
        gt_dives = 6
        gt_max_depth = 28.3 
    finally:
        if os.path.exists(tmp_xml.name):
            os.unlink(tmp_xml.name)

    # 3. Analyze agent's extracted text content
    agent_text = result_json.get('summary_content', '')
    agent_dives = None
    agent_max_depth = None

    if agent_text:
        dives_match = re.search(r'Dives:\s*(\d+)', agent_text, re.IGNORECASE)
        if dives_match:
            agent_dives = int(dives_match.group(1))

        depth_match = re.search(r'Max Depth:\s*([\d.]+)', agent_text, re.IGNORECASE)
        if depth_match:
            agent_max_depth = float(depth_match.group(1))

    # ==========================================
    # Scoring Logic
    # ==========================================

    # Criterion A: Screenshot File (15 pts)
    if result_json.get('screenshot_exists') and result_json.get('screenshot_created_during_task'):
        score += 15
        feedback.append("Screenshot saved correctly (+15)")
    elif result_json.get('screenshot_exists'):
        score += 5
        feedback.append("Screenshot exists but failed timestamp validation (+5)")
    else:
        feedback.append("Screenshot file missing (0/15)")

    # Criterion B: Formatting of the Summary File (15 pts)
    if result_json.get('summary_exists'):
        if agent_dives is not None and agent_max_depth is not None:
            score += 15
            feedback.append("Summary text file formatted correctly (+15)")
        else:
            score += 5
            feedback.append("Summary exists but formatting is broken/missing data (+5)")
    else:
        feedback.append("Summary text file missing (0/15)")

    # Criterion C: Dives Accuracy (30 pts)
    if agent_dives is not None:
        if agent_dives == gt_dives:
            score += 30
            feedback.append(f"Correct 2011 dives count: {agent_dives} (+30)")
        else:
            feedback.append(f"Incorrect dives count. Expected {gt_dives}, Got {agent_dives} (0/30)")
    else:
        feedback.append("Could not parse Dives count from text (0/30)")

    # Criterion D: Max Depth Accuracy (30 pts)
    if agent_max_depth is not None:
        if abs(agent_max_depth - gt_max_depth) <= 0.5:
            score += 30
            feedback.append(f"Correct max depth: {agent_max_depth}m (+30)")
        else:
            feedback.append(f"Incorrect max depth. Expected ~{gt_max_depth}m, Got {agent_max_depth}m (0/30)")
    else:
        feedback.append("Could not parse Max Depth from text (0/30)")

    # Criterion E: Visual Verification via VLM (10 pts)
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    images_to_check = frames + [final] if final else frames

    prompt = (
        "Look at these screenshots of the Subsurface dive log application. "
        "Did the user successfully open the 'Yearly Statistics' window/dialog box? "
        "You should see a panel or window titled 'Yearly Statistics' showing dive data aggregated by year. "
        "Respond strictly with a JSON object: {\"statistics_visible\": true/false}"
    )

    stats_visible = False
    vlm_result = query_vlm(images=images_to_check, prompt=prompt)
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("statistics_visible", False):
            stats_visible = True

    if stats_visible:
        score += 10
        feedback.append("VLM confirmed Yearly Statistics window was accessed (+10)")
    else:
        feedback.append("VLM did not detect Yearly Statistics window (0/10)")

    # The threshold is set so the agent must get the file format correct, save the image,
    # and get at least ONE of the exact numbers right to pass.
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }