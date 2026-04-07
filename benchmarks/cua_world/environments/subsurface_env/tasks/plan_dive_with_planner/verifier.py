#!/usr/bin/env python3
"""
Verifier for Plan a Recreational Dive Using the Dive Planner.

Multi-Criteria Verification:
1. File modified during task (anti-gaming timestamp check)
2. Dive count increased (checks XML structure)
3. New dive matches depth profile (~18m)
4. New dive matches duration profile (>= 35 min)
5. New dive uses Air (21% O2 or default)
6. New dive has planner tag (`divecomputer model="planned dive"`)
7. VLM check of trajectory frames proves the planner UI was actively used.
"""

import os
import json
import re
import tempfile
import logging
import xml.etree.ElementTree as ET

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are analyzing trajectory screenshots from an agent interacting with Subsurface Dive Log.
Task: The agent was instructed to use the "Dive Planner" module.

Look closely at the provided screenshots to determine:
1. Did the agent open the Dive Planner interface? (Look for a split screen with a "Plan dive" left panel featuring waypoints, depth/time inputs, and available gases).
2. Is there evidence the agent configured segments (e.g. 18m, 40min) in this planner?

Respond ONLY in JSON format:
{
    "planner_interface_visible": true/false,
    "waypoints_entered": true/false,
    "confidence": "high/medium/low"
}
"""

def verify_plan_dive(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Fetch JSON info and Initial State
    # ---------------------------------------------------------
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_init_count = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    temp_ssrf = tempfile.NamedTemporaryFile(delete=False, suffix='.ssrf')
    
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result = json.load(f)
            
        copy_from_env("/tmp/initial_count.txt", temp_init_count.name)
        with open(temp_init_count.name, 'r') as f:
            initial_count_str = f.read().strip()
            initial_count = int(initial_count_str) if initial_count_str.isdigit() else 29
            
        copy_from_env("/home/ga/Documents/dives.ssrf", temp_ssrf.name)
        
        task_start = result.get("task_start", 0)
        file_mtime = result.get("file_mtime", 0)
        
        # Criterion 1: File modified during task (10 pts)
        # We add a 5 second margin to account for clock sync delays
        if file_mtime >= (task_start - 5):
            score += 10
            feedback_parts.append("File modified during task (+10)")
        else:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Dive log file was not saved/modified after task start. Ensure you press Ctrl+S."
            }

        # ---------------------------------------------------------
        # 2. Parse XML for Dive Data
        # ---------------------------------------------------------
        try:
            tree = ET.parse(temp_ssrf.name)
            root = tree.getroot()
            dives = root.findall('.//dive')
            current_count = len(dives)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to parse SSRF file: {e}"}
            
        # Criterion 2: Dive count increased (10 pts)
        if current_count > initial_count:
            score += 10
            feedback_parts.append(f"Dive count increased ({initial_count} -> {current_count}) (+10)")
        else:
            feedback_parts.append("Dive count did not increase (No new dive saved)")
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }

        # Find the best matching new dive
        best_dive_score = 0
        best_dive_feedback = []
        
        for dive in dives:
            d_score = 0
            d_feedback = []
            
            # Check Depth (~18m)
            depth_str = dive.get('maxdepth', dive.get('depth', ''))
            depth_val = 0.0
            m = re.search(r'([0-9.]+)', depth_str)
            if m:
                depth_val = float(m.group(1))
            else:
                for s in dive.findall('.//sample'):
                    sd = s.get('depth', '')
                    m2 = re.search(r'([0-9.]+)', sd)
                    if m2:
                        d = float(m2.group(1))
                        if d > depth_val:
                            depth_val = d
                            
            if 16.0 <= depth_val <= 20.0:
                d_score += 15
                d_feedback.append("Depth ~18m (+15)")
                
            # Check Duration (>= 35 min)
            duration_str = dive.get('duration', '')
            duration_min = 0.0
            m3 = re.search(r'(\d+):(\d+)', duration_str)
            if m3:
                duration_min = int(m3.group(1)) + int(m3.group(2)) / 60.0
            else:
                m4 = re.search(r'(\d+)', duration_str)
                if m4:
                    duration_min = float(m4.group(1))
                    
            if not duration_min:
                samples = dive.findall('.//sample')
                if samples:
                    last_time = samples[-1].get('time', '')
                    m_time = re.search(r'(\d+):(\d+)', last_time)
                    if m_time:
                        duration_min = int(m_time.group(1)) + int(m_time.group(2)) / 60.0
                        
            if duration_min >= 35.0:
                d_score += 15
                d_feedback.append("Duration >=35min (+15)")
                
            # Check Gas (Air)
            has_air = False
            cylinders = dive.findall('.//cylinder')
            if not cylinders:
                has_air = True
            else:
                for cyl in cylinders:
                    o2_str = cyl.get('o2', '')
                    if not o2_str:
                        has_air = True
                    else:
                        m5 = re.search(r'([0-9.]+)', o2_str)
                        if m5:
                            o2_val = float(m5.group(1))
                            if o2_val < 1: o2_val *= 100
                            if 19.0 <= o2_val <= 23.0:
                                has_air = True
                                
            if has_air:
                d_score += 10
                d_feedback.append("Gas=Air (+10)")
                
            # Check Planner Tag
            is_planned = False
            for dc in dive.findall('.//divecomputer'):
                if 'plan' in dc.get('model', '').lower():
                    is_planned = True
                    break
            if is_planned:
                d_score += 20
                d_feedback.append("Planner Tag Found (+20)")
                
            if d_score > best_dive_score:
                best_dive_score = d_score
                best_dive_feedback = d_feedback

        score += best_dive_score
        feedback_parts.extend(best_dive_feedback)
        
        if best_dive_score == 0:
            feedback_parts.append("No dive parameters matched the planned profile.")

        # ---------------------------------------------------------
        # 3. VLM Verification (Trajectory frames)
        # ---------------------------------------------------------
        vlm_score = 0
        if VLM_AVAILABLE and traj:
            try:
                frames = sample_trajectory_frames(traj, n=4)
                final_screenshot = get_final_screenshot(traj)
                if final_screenshot:
                    frames.append(final_screenshot)
                    
                vlm_result = query_vlm(images=frames, prompt=VLM_PROMPT)
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("planner_interface_visible"):
                        vlm_score += 10
                        feedback_parts.append("VLM confirmed Planner UI visible (+10)")
                    if parsed.get("waypoints_entered"):
                        vlm_score += 10
                        feedback_parts.append("VLM confirmed waypoints entered (+10)")
                else:
                    logger.warning(f"VLM query failed: {vlm_result.get('error')}")
            except Exception as e:
                logger.warning(f"VLM verification error: {e}")

        score += vlm_score
        
        # We need key criteria met for a pass
        # File modified + Count increased + Some meaningful parameters accurate
        key_criteria_met = (file_mtime >= (task_start - 5)) and (current_count > initial_count) and (best_dive_score >= 30)
        passed = (score >= 60) and key_criteria_met

        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        for tmp_file in [temp_res, temp_init_count, temp_ssrf]:
            if os.path.exists(tmp_file.name):
                os.unlink(tmp_file.name)