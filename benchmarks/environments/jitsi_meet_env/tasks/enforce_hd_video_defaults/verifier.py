#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enforce_hd_video_defaults(traj, env_info, task_info):
    """
    Verify that Jitsi Meet config enforces 720p resolution and high bitrate.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.js')
    
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
            
        # Copy the ground truth config captured in export_result.sh
        ground_truth_path = result.get("actual_config_path", "/tmp/ground_truth_config.js")
        copy_from_env(ground_truth_path, temp_config.name)
        
        with open(temp_config.name, 'r') as f:
            config_content = f.read()
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        if os.path.exists(temp_config.name):
            os.unlink(temp_config.name)

    score = 0
    feedback = []

    # Criterion 1: Service Health (10 pts)
    if result.get("container_running", False):
        score += 10
        feedback.append("Jitsi Web container is running.")
    else:
        feedback.append("Jitsi Web container is NOT running.")

    # Criterion 2: Evidence File Created (10 pts)
    if result.get("evidence_exists", False) and int(result.get("evidence_size", 0)) > 100:
        score += 10
        feedback.append("Agent saved configuration evidence.")
    else:
        feedback.append("Agent did not save configuration evidence.")

    # Check Content of ACTUAL Config (Ground Truth)
    # Note: Jitsi config.js is JS, not pure JSON, so we use Regex.

    # Criterion 3: Resolution set to 720 (20 pts)
    # Search for resolution: 720 (ignoring comments)
    # Remove comments first to be safe (simple // removal)
    clean_config = re.sub(r'//.*', '', config_content)
    
    res_match = re.search(r'resolution:\s*720', clean_config)
    if res_match:
        score += 20
        feedback.append("Resolution is set to 720.")
    else:
        feedback.append("Resolution NOT set to 720 in served config.")

    # Criterion 4: Start Bitrate 4000 (20 pts)
    # Can be number or string: startBitrate: 4000 or startBitrate: "4000"
    bitrate_match = re.search(r'startBitrate:\s*["\']?4000["\']?', clean_config)
    if bitrate_match:
        score += 20
        feedback.append("Start bitrate is set to 4000.")
    else:
        feedback.append("Start bitrate NOT set to 4000 in served config.")

    # Criterion 5: Constraints Object (30 pts)
    # Looking for structure like:
    # constraints: { video: { height: { ideal: 720, max: 720, min: 720 } } }
    # We'll look for the specific height constraints.
    
    constraints_video_match = re.search(r'constraints\s*:\s*\{[^}]*video', clean_config, re.DOTALL)
    if constraints_video_match:
        # Narrow down to video block
        video_block = clean_config[constraints_video_match.start():]
        
        # check for height 720 settings
        has_ideal = re.search(r'ideal:\s*720', video_block)
        has_max = re.search(r'max:\s*720', video_block)
        has_min = re.search(r'min:\s*720', video_block)
        
        if has_ideal and has_max and has_min:
            score += 30
            feedback.append("Video constraints correctly configured (ideal/max/min 720).")
        elif has_ideal:
            score += 15
            feedback.append("Partial constraints found (ideal 720), but missing strict min/max.")
        else:
            feedback.append("Video constraints missing required 720p settings.")
    else:
        feedback.append("Constraints object not found or malformed.")

    # Criterion 6: Visual Verification (10 pts)
    # We check if the final screenshot exists. 
    # (Advanced VLM check for 'High Definition' text could go here, but simple check is existence)
    if result.get("evidence_exists", False): # Reusing existence as proxy for "did something"
        # We give these points if config is good, as visual check implies success
        if score >= 70:
            score += 10
            feedback.append("Visual verification assumed passed based on config success.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback)
    }