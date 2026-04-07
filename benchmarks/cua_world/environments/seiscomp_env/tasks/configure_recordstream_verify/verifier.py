#!/usr/bin/env python3
"""
Verifier for SeisComP RecordStream Configuration and Data Verification Task.

Evaluates 4 Criteria:
1. Global configuration correctness (25 points)
2. Inventory listing extraction (25 points)
3. Waveform extraction & validation (30 points)
4. Trajectory VLM Check (20 points)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Prompt for the VLM trajectory analysis
TRAJECTORY_PROMPT = """You are evaluating an agent that is using a Linux terminal to configure the SeisComP seismological software.

Please review the provided trajectory screenshots (from start to finish) and assess whether the agent actively used the terminal to perform commands.
Look for indications of terminal usage such as:
1. Opening files in a text editor like nano or vim (e.g. editing global.cfg)
2. Running command line tools like `scinv ls`
3. Running waveform extraction tools like `scart`

Did the agent demonstrate active terminal usage and run commands relevant to the task?
Respond with a JSON object containing a boolean "terminal_used" and a string "reason" describing the observations.

Example format:
{
    "terminal_used": true,
    "reason": "Agent opened global.cfg in nano and executed scinv in the terminal."
}
"""

def get_vlm_score(traj, env_info):
    """Analyze trajectory frames via VLM to confirm terminal work."""
    score = 0
    feedback = []
    
    if 'query_vlm' not in env_info:
        logger.warning("VLM query function not provided. Skipping VLM check.")
        return 0, ["VLM not available, skipping terminal validation"]

    query_vlm = env_info['query_vlm']
    
    try:
        # Import safely based on framework spec
        import gym_anything.vlm as vlm_utils
        frames = vlm_utils.sample_trajectory_frames(traj, n=4)
    except Exception as e:
        logger.warning(f"Could not sample trajectory frames: {e}")
        return 0, ["Failed to sample trajectory frames"]

    if not frames:
        return 0, ["No trajectory frames available for VLM"]

    try:
        result = query_vlm(images=frames, prompt=TRAJECTORY_PROMPT)
        if result and result.get('success') and 'parsed' in result:
            parsed = result['parsed']
            terminal_used = parsed.get('terminal_used', False)
            reason = parsed.get('reason', '')
            
            if terminal_used:
                score += 20
                feedback.append("VLM: Terminal usage and commands visually verified.")
            else:
                feedback.append(f"VLM: Terminal commands not detected. Reason: {reason}")
        else:
            feedback.append("VLM: Failed to parse terminal usage validation.")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        feedback.append("VLM: Error during verification query.")
        
    return score, feedback

def verify_recordstream_workflow(traj, env_info, task_info):
    """Main verification logic."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Retrieve result JSON from environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            res = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    task_start = res.get('task_start', 0)
    
    # ---------------------------------------------------------
    # Criterion 1: Configuration (25 pts max)
    # ---------------------------------------------------------
    rs_line = res.get('recordstream_line', '').strip()
    cfg_mtime = res.get('cfg_mtime', 0)
    cfg_preserved = res.get('cfg_preserved', False)
    
    if rs_line:
        score += 10
        feedback_parts.append("Global config updated with recordstream line")
        
        # Verify correct protocol
        if "sdsarchive://" in rs_line:
            score += 5
            feedback_parts.append("Correct sdsarchive protocol used")
        else:
            feedback_parts.append("Incorrect recordstream protocol")
            
        # Verify correct path
        if "/home/ga/seiscomp/var/lib/archive" in rs_line:
            score += 5
            feedback_parts.append("Correct SDS archive path configured")
        else:
            feedback_parts.append("Incorrect SDS archive path configured")
            
        # Anti-gaming & sanity Check
        if cfg_mtime >= task_start:
            feedback_parts.append("Config modified during task")
        else:
            score -= 10
            feedback_parts.append("PENALTY: Config modified before task started!")
            
        if cfg_preserved:
            score += 5
            feedback_parts.append("Original config parameters preserved")
        else:
            feedback_parts.append("Warning: Existing global.cfg parameters may have been deleted")
    else:
        feedback_parts.append("Recordstream line NOT found in global.cfg")

    # ---------------------------------------------------------
    # Criterion 2: Inventory Listing (25 pts max)
    # ---------------------------------------------------------
    inv_exists = res.get('inv_exists', False)
    inv_size = res.get('inv_size', 0)
    inv_mtime = res.get('inv_mtime', 0)
    st_found = res.get('stations_found', 0)
    
    if inv_exists and inv_size > 10:
        score += 5
        feedback_parts.append(f"Inventory listing exists ({inv_size} bytes)")
        
        if inv_mtime >= task_start:
            feedback_parts.append("Inventory created during task")
        else:
            score -= 5
            feedback_parts.append("PENALTY: Inventory file created before task start!")
            
        # Award 4 pts per station found (max 20)
        st_pts = min(st_found * 4, 20)
        score += st_pts
        feedback_parts.append(f"Found {st_found}/5 expected stations (+{st_pts} pts)")
    else:
        feedback_parts.append("Inventory listing missing or empty")

    # ---------------------------------------------------------
    # Criterion 3: Waveform Extraction (30 pts max)
    # ---------------------------------------------------------
    wave_exists = res.get('wave_exists', False)
    wave_size = res.get('wave_size', 0)
    wave_mtime = res.get('wave_mtime', 0)
    quality_byte = res.get('quality_byte', '')
    ge_found = res.get('ge_found', False)
    
    if wave_exists and wave_size >= 512:
        score += 5
        feedback_parts.append(f"Waveform output exists ({wave_size} bytes)")
        
        if wave_mtime >= task_start:
            feedback_parts.append("Waveform created during task")
            score += 5
        else:
            score -= 5
            feedback_parts.append("PENALTY: Waveform file created before task start!")
            
        # Validate miniSEED structure via quality byte (D, R, Q, M)
        if quality_byte and quality_byte.upper() in ['D', 'R', 'Q', 'M']:
            score += 10
            feedback_parts.append(f"Valid miniSEED header detected (Quality: {quality_byte})")
        else:
            feedback_parts.append(f"miniSEED header validation failed (Byte: {quality_byte})")
            
        if ge_found:
            score += 10
            feedback_parts.append("Network code 'GE' found in binary data")
        else:
            feedback_parts.append("Expected network code 'GE' missing from binary data")
    else:
        feedback_parts.append("Waveform output missing or too small")

    # ---------------------------------------------------------
    # Criterion 4: VLM Validation (20 pts max)
    # ---------------------------------------------------------
    vlm_score, vlm_fb = get_vlm_score(traj, env_info)
    score += vlm_score
    feedback_parts.extend(vlm_fb)

    # ---------------------------------------------------------
    # Pass/Fail Determination
    # ---------------------------------------------------------
    passed = score >= 60 and rs_line and inv_exists and wave_exists
    
    return {
        "passed": passed,
        "score": max(0, min(100, score)),
        "feedback": " | ".join(feedback_parts)
    }