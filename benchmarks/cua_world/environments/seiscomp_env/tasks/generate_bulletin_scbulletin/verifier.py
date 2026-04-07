#!/usr/bin/env python3
"""
Verifier for generate_bulletin_scbulletin task.

Verification Criteria:
1. File Exists (15 pts) - Bulletin file was generated
2. Anti-Gaming (15 pts) - File was created/modified during the task
3. Size Check (10 pts) - File is > 100 bytes (real bulletin size)
4. Content Validation (40 pts) - Parsed lat, lon, mag, and year match the Noto Earthquake
5. VLM Trajectory (20 pts) - Shows CLI usage

Pass threshold: 60 points
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_trajectory_frames(traj, n=4):
    """Safely extract images from the trajectory for VLM evaluation."""
    frames = []
    if not traj:
        return frames
    
    # Evenly sample n frames from the trajectory
    step = max(1, len(traj) // n)
    for i in range(0, len(traj), step):
        obs = traj[i].get('obs', {})
        if 'rgb_screen' in obs:
            frames.append(obs['rgb_screen'])
    
    # Ensure we don't return more than n frames
    return frames[:n]

def verify_generate_bulletin(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_year = metadata.get('expected_year', '2024')
    min_size = metadata.get('min_file_size_bytes', 100)
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve the task result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # Early Check: Did they generate anything?
    output_exists = result.get('output_exists', False)
    if not output_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Bulletin file not found at the expected location.",
            "details": result
        }
        
    score += 15
    feedback_parts.append("Bulletin file exists")
    
    # Anti-gaming: File created during task
    if result.get('file_created_during_task', False):
        score += 15
        feedback_parts.append("File created during session")
    else:
        feedback_parts.append("Warning: File timestamp indicates it was not created during this session")
        
    # File Size check
    file_size = result.get('output_size_bytes', 0)
    if file_size >= min_size:
        score += 10
        feedback_parts.append(f"File size valid ({file_size} bytes)")
    else:
        feedback_parts.append(f"Warning: File suspiciously small ({file_size} bytes)")
        
    # 2. Retrieve the actual bulletin content for verification
    content = ""
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/agent_bulletin.txt", temp_txt.name)
        with open(temp_txt.name, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
    except Exception as e:
        logger.warning(f"Could not read agent bulletin: {e}")
    finally:
        if os.path.exists(temp_txt.name):
            os.unlink(temp_txt.name)
            
    # 3. Content Validation (40 points total)
    if content:
        # Check Year (10 pts)
        if expected_year in content:
            score += 10
            feedback_parts.append("Event year found in bulletin")
            
        # Extract floats to find lat/lon/mag
        # This regex matches numbers like 37.5, -137.2, 7.51
        floats = [float(f) for f in re.findall(r'-?\d+\.\d+', content)]
        
        # Check Latitude ~37.5 (10 pts)
        if any(36.5 <= f <= 38.5 for f in floats):
            score += 10
            feedback_parts.append("Correct latitude found")
            
        # Check Longitude ~137.2 (10 pts)
        if any(136.0 <= f <= 138.5 for f in floats):
            score += 10
            feedback_parts.append("Correct longitude found")
            
        # Check Magnitude ~7.5 (10 pts)
        if any(7.0 <= f <= 8.0 for f in floats):
            score += 10
            feedback_parts.append("Correct magnitude found")
            
        # Ground Truth check
        gt_event = result.get('gt_event_id', '')
        if gt_event and gt_event in content:
            feedback_parts.append("Exact event ID matches ground truth")
    else:
        feedback_parts.append("Failed to read file content or file is empty")

    # 4. VLM Verification of workflow (20 points)
    vlm_passed = False
    if query_vlm:
        frames = extract_trajectory_frames(traj, n=4)
        if frames:
            prompt = """
            You are evaluating an AI agent performing a Linux command line task.
            The agent was instructed to use SeisComP terminal tools (like `scevtls` and `scbulletin`) 
            to query an earthquake event and generate a text bulletin.
            
            Look at these sequential screenshots of the agent's screen:
            1. Do you see evidence of a terminal/command-line interface being used?
            2. Do you see the agent executing SeisComP commands (such as 'scevtls' or 'scbulletin')?
            
            Return a JSON object with:
            {
                "terminal_used": true/false,
                "seiscomp_commands_visible": true/false,
                "confidence": "high/medium/low"
            }
            """
            try:
                vlm_result = query_vlm(prompt=prompt, images=frames)
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("terminal_used") and parsed.get("seiscomp_commands_visible"):
                        score += 20
                        vlm_passed = True
                        feedback_parts.append("VLM confirmed terminal & tool usage")
                    else:
                        feedback_parts.append("VLM did not detect correct CLI usage")
            except Exception as e:
                logger.warning(f"VLM error: {e}")
                
    # Evaluate Pass/Fail
    # To pass, they must have achieved at least 60 points (which means file created + some content matched)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "file_exists": output_exists,
            "vlm_verified": vlm_passed
        }
    }