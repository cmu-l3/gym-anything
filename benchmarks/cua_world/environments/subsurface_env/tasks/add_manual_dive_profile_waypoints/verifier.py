#!/usr/bin/env python3
"""
Verifier for add_manual_dive_profile_waypoints task.

Checks that the Subsurface XML dive log contains a new dive on 2005-08-14,
and that the continuous profile data (<sample> elements) contains the expected
time/depth waypoints within a specified tolerance bounding box.
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_time_to_seconds(t_str: str) -> int:
    """Parse Subsurface time string (e.g. '5:00', '10:00 min') to total seconds."""
    if not t_str:
        return 0
    t_str = t_str.strip().lower()
    if t_str.endswith('min'):
        t_str = t_str.replace('min', '').strip()
    if t_str.endswith('s'):
        t_str = t_str.replace('s', '').strip()
        
    try:
        if ':' in t_str:
            parts = t_str.split(':')
            return int(parts[0]) * 60 + int(parts[1])
        else:
            return int(float(t_str))
    except ValueError:
        return 0


def parse_depth_to_meters(d_str: str) -> float:
    """Parse Subsurface depth string (e.g. '18.0 m', '12000 mm') to meters."""
    if not d_str:
        return 0.0
    d_str = d_str.strip().lower()
    try:
        if d_str.endswith('mm'):
            return float(d_str.replace('mm', '').strip()) / 1000.0
        if d_str.endswith('m'):
            return float(d_str.replace('m', '').strip())
        return float(d_str)
    except ValueError:
        return 0.0


def verify_add_manual_dive_profile_waypoints(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_date = metadata.get('target_date', '2005-08-14')
    waypoints = metadata.get('waypoints', [])
    tol_time = metadata.get('tolerance_time_sec', 60)
    tol_depth = metadata.get('tolerance_depth_m', 1.5)

    score = 0
    feedback_parts = []
    
    # 1. Read JSON Export Result
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    
    try:
        copy_from_env('/tmp/task_result.json', tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Could not read task_result.json: {e}")
        result_data = {}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # Anti-gaming: Ensure file was modified
    if result_data.get("file_modified_during_task", False):
        score += 5
        feedback_parts.append("File modified ✓")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Dive log file was not saved/modified after task start. Did you save the changes?"
        }
        
    initial_count = result_data.get("initial_dive_count", 8)
    current_count = result_data.get("current_dive_count", 0)
    if current_count > initial_count:
        score += 5
        feedback_parts.append(f"Dive count increased ({initial_count}->{current_count}) ✓")
    else:
        feedback_parts.append(f"Dive count did not increase (currently {current_count})")

    # 2. Read SSRF XML File
    tmp_ssrf = tempfile.NamedTemporaryFile(delete=False, suffix='.ssrf')
    tmp_ssrf.close()
    
    try:
        copy_from_env('/home/ga/Documents/dives.ssrf', tmp_ssrf.name)
        try:
            tree = ET.parse(tmp_ssrf.name)
            root = tree.getroot()
        except ET.ParseError as e:
            return {"passed": False, "score": score, "feedback": f"Could not parse SSRF XML: {e}"}
            
        # Find the target dive
        target_dive = None
        for dive in root.iter('dive'):
            if dive.get('date') == target_date:
                target_dive = dive
                break
                
        if target_dive is None:
            feedback_parts.append(f"No dive found for date {target_date} ✗")
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
            
        score += 20
        feedback_parts.append(f"Dive {target_date} found ✓")
        
        # Extract all profile samples for the dive
        samples = []
        for divecomputer in target_dive.findall('divecomputer'):
            for sample in divecomputer.findall('sample'):
                time_str = sample.get('time', '')
                depth_str = sample.get('depth', '')
                if time_str and depth_str:
                    t_sec = parse_time_to_seconds(time_str)
                    d_m = parse_depth_to_meters(depth_str)
                    samples.append((t_sec, d_m))
                    
        if not samples:
            feedback_parts.append("Dive has no profile/sample data ✗")
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
            
        # Evaluate against expected waypoints
        waypoint_points = 10
        waypoints_found = 0
        total_waypoints = len(waypoints)
        
        for i, wp in enumerate(waypoints):
            expected_t = wp['time_min'] * 60
            expected_d = wp['depth_m']
            
            # Check if any sample falls within bounding box
            found = False
            for s_t, s_d in samples:
                if (abs(s_t - expected_t) <= tol_time) and (abs(s_d - expected_d) <= tol_depth):
                    found = True
                    break
                    
            if found:
                score += waypoint_points
                waypoints_found += 1
                feedback_parts.append(f"WP{i+1}({wp['time_min']}m@{wp['depth_m']}m) found ✓")
            else:
                feedback_parts.append(f"WP{i+1}({wp['time_min']}m@{wp['depth_m']}m) missing ✗")

        passed = score >= 70
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        if os.path.exists(tmp_ssrf.name):
            os.unlink(tmp_ssrf.name)