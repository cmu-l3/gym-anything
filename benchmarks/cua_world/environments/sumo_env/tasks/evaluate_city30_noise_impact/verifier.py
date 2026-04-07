#!/usr/bin/env python3
"""
Verifier for the 'Città 30' (City 30) policy evaluation task.

Verification checks:
1. File Existence & Anti-Gaming: All 5 files must exist and be created during the task.
2. Network Physics: The modified network must cap lane speeds at ~8.33 m/s (30 km/h).
3. Tripinfo Physics: The mean travel time in the city30 scenario MUST be higher than baseline.
4. Noise Physics: The mean noise level in the city30 scenario MUST be lower than baseline.
5. VLM Trajectory: Verifies terminal or code editor usage to prove work was done.
"""

import os
import json
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_tripinfo_mean_duration(filepath):
    """Parses tripinfo XML and returns mean duration and trip count."""
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        durations = []
        for trip in root.findall('tripinfo'):
            dur = trip.get('duration')
            if dur is not None:
                durations.append(float(dur))
        
        count = len(durations)
        mean_dur = sum(durations) / count if count > 0 else 0
        return mean_dur, count
    except Exception as e:
        logger.error(f"Failed to parse tripinfo {filepath}: {e}")
        return 0, 0

def parse_noise_mean(filepath):
    """Parses edgeData XML and returns mean noise."""
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        noise_vals = []
        # Usually edgeData wraps in <interval>
        for interval in root.findall('.//interval'):
            for edge in interval.findall('edge'):
                noise = edge.get('noise')
                if noise is not None:
                    noise_vals.append(float(noise))
        
        count = len(noise_vals)
        mean_noise = sum(noise_vals) / count if count > 0 else 0
        return mean_noise, count
    except Exception as e:
        logger.error(f"Failed to parse noise file {filepath}: {e}")
        return 0, 0

def check_network_speeds(filepath, threshold=8.34):
    """Checks if all lane speeds in the network are capped at the threshold."""
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        lanes = root.findall('.//lane')
        if not lanes:
            return False, "No lanes found in network file"
        
        violating_lanes = 0
        max_speed_found = 0
        for lane in lanes:
            speed = float(lane.get('speed', '0'))
            if speed > max_speed_found:
                max_speed_found = speed
            if speed > threshold:
                violating_lanes += 1
                
        if violating_lanes > 0:
            return False, f"Found {violating_lanes} lanes exceeding {threshold} m/s (Max: {max_speed_found:.2f})"
        return True, f"Speeds valid (Max: {max_speed_found:.2f})"
    except Exception as e:
        logger.error(f"Failed to parse network file {filepath}: {e}")
        return False, f"Parse error: {str(e)}"

def verify_city30_evaluation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    score = 0
    feedback_parts = []
    
    # 1. Load exported JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # 2. Check File Existence & Creation (20 pts)
    files_data = {f['filename']: f for f in result.get('files', [])}
    required_files = [
        "baseline_tripinfo.xml", "baseline_noise.xml",
        "pasubio_city30.net.xml", "city30_tripinfo.xml", "city30_noise.xml"
    ]
    
    missing_files = []
    old_files = []
    for f in required_files:
        fdata = files_data.get(f, {})
        if not fdata.get('exists', False):
            missing_files.append(f)
        elif not fdata.get('created_during_task', False):
            old_files.append(f)
            
    if missing_files:
        feedback_parts.append(f"Missing outputs: {', '.join(missing_files)}")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    elif old_files:
        feedback_parts.append(f"Anti-gaming fail: files existed before task: {', '.join(old_files)}")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    else:
        score += 20
        feedback_parts.append("All output files present and created during task")

    # We need to copy the files to host for XML parsing
    temp_dir = tempfile.mkdtemp()
    try:
        for f in required_files:
            container_path = files_data[f]['path']
            host_path = os.path.join(temp_dir, f)
            copy_from_env(container_path, host_path)
            
        # 3. Network Modified Correctly (30 pts)
        net_path = os.path.join(temp_dir, "pasubio_city30.net.xml")
        net_valid, net_msg = check_network_speeds(net_path, threshold=8.34)
        if net_valid:
            score += 30
            feedback_parts.append("Network successfully modified to 30km/h cap")
        else:
            feedback_parts.append(f"Network error: {net_msg}")
            
        # 4. Valid Tripinfo Data & Travel Time Physics (30 pts: 10 + 20)
        base_trip_path = os.path.join(temp_dir, "baseline_tripinfo.xml")
        city_trip_path = os.path.join(temp_dir, "city30_tripinfo.xml")
        
        base_dur, base_count = parse_tripinfo_mean_duration(base_trip_path)
        city_dur, city_count = parse_tripinfo_mean_duration(city_trip_path)
        
        if base_count > 100 and city_count > 100:
            score += 10
            feedback_parts.append("Sufficient trips completed in simulations")
            
            # Physics check: slower speeds -> higher travel time
            if city_dur > base_dur:
                score += 20
                feedback_parts.append(f"Travel time increased correctly ({base_dur:.1f}s -> {city_dur:.1f}s)")
            else:
                feedback_parts.append(f"Physics violation: travel time did not increase (Base: {base_dur:.1f}s, City30: {city_dur:.1f}s)")
        else:
            feedback_parts.append(f"Simulations lack traffic (Base: {base_count}, City30: {city_count} trips)")
            
        # 5. Noise Reduction Physics (20 pts)
        base_noise_path = os.path.join(temp_dir, "baseline_noise.xml")
        city_noise_path = os.path.join(temp_dir, "city30_noise.xml")
        
        base_noise, b_n_count = parse_noise_mean(base_noise_path)
        city_noise, c_n_count = parse_noise_mean(city_noise_path)
        
        if b_n_count > 0 and c_n_count > 0:
            # Physics check: lower speeds -> lower average noise
            if city_noise < base_noise and city_noise > 0:
                score += 20
                feedback_parts.append(f"Noise decreased correctly ({base_noise:.2f} -> {city_noise:.2f})")
            else:
                feedback_parts.append(f"Physics violation: noise did not decrease (Base: {base_noise:.2f}, City30: {city_noise:.2f})")
        else:
            feedback_parts.append("Noise output files are empty or invalid")

    except Exception as e:
        logger.error(f"Error during file verification: {e}")
        feedback_parts.append(f"Verification error: {str(e)}")
    finally:
        # Cleanup temp dir
        for f in required_files:
            p = os.path.join(temp_dir, f)
            if os.path.exists(p):
                os.unlink(p)
        os.rmdir(temp_dir)
        
    # Final VLM Check for trajectory (Terminal / Editor usage)
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    if 'query_vlm' in env_info:
        try:
            frames = sample_trajectory_frames(traj, n=3)
            if frames:
                prompt = (
                    "Look at these screenshots from a user's session. "
                    "Did the user use a terminal, command prompt, or code editor to write scripts or run commands? "
                    "Respond with a JSON object: {\"terminal_used\": true/false}"
                )
                vlm_res = query_vlm(images=frames, prompt=prompt)
                parsed = vlm_res.get('parsed', {})
                if parsed.get('terminal_used', False):
                    feedback_parts.append("VLM confirmed terminal/scripting usage.")
                else:
                    # Minor deduction or note if VLM doesn't see it, but we won't strictly fail 
                    # if the hard physics checks passed, as the agent clearly did the work.
                    feedback_parts.append("VLM couldn't clearly verify terminal usage.")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")

    key_criteria_met = net_valid and (city_dur > base_dur) and (city_noise < base_noise) and (city_noise > 0)
    passed = score >= 70 and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }