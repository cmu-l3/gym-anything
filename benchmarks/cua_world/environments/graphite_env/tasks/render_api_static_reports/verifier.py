#!/usr/bin/env python3
"""
Verifier for render_api_static_reports task.

Evaluates both the generated artifacts (PNG files) and the programmatic pipeline (shell script)
used to produce them. Ensures correct dimensions, file formats, and API parameters.
Uses VLM on trajectory to verify the agent actually interacted with a terminal.
"""

import json
import os
import tempfile
import logging

# Ensure gym_anything modules are in path for VLM
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames
except ImportError:
    pass  # Allow running in testing without gym_anything

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
RESULT_PATH = "/tmp/render_api_result.json"

VLM_TERMINAL_PROMPT = """You are verifying an agent's workflow trajectory.
The agent was tasked with opening a terminal and running shell scripts / curl commands.

Looking at these sampled screenshots from the agent's screen:
1. Is there evidence that the agent opened a terminal emulator window (e.g., GNOME Terminal)?
2. Are there visible shell commands being typed or executed (especially `curl`, `mkdir`, or `chmod`)?

Respond in JSON format:
{
    "terminal_opened": true/false,
    "shell_commands_visible": true/false,
    "confidence": "low/medium/high"
}
"""

def _eval_image(file_info, expected_w, expected_h, min_size_kb, task_start):
    """Evaluate a single generated image and return its score / feedback."""
    score = 0
    feedback = []
    
    if not file_info.get("exists", False):
        return 0, ["Missing"]
        
    size_kb = file_info.get("size", 0) / 1024.0
    mtime = file_info.get("mtime", 0)
    
    # 1. Existence and valid size (8 pts)
    if size_kb >= min_size_kb and file_info.get("format") == "PNG":
        score += 8
        feedback.append(f"Valid PNG ({size_kb:.1f}KB)")
    else:
        feedback.append(f"Invalid format or too small ({size_kb:.1f}KB, {file_info.get('format')})")
        
    # Anti-gaming: Ensure it was created after task start
    if mtime < task_start:
        feedback.append("WARNING: File created before task started!")
        score = 0
        return score, feedback
        
    # 2. Dimensions (4 pts)
    w = file_info.get("width", 0)
    h = file_info.get("height", 0)
    if w == expected_w and h == expected_h:
        score += 4
        feedback.append(f"Dimensions correct ({w}x{h})")
    else:
        feedback.append(f"Wrong dimensions ({w}x{h})")
        
    return score, feedback

def verify_render_api_static_reports(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
        
    metadata = task_info.get("metadata", {})
    expected_w = metadata.get("expected_width", 800)
    expected_h = metadata.get("expected_height", 400)
    min_size_kb = metadata.get("min_file_size_kb", 2)
    
    score = 0
    feedback_parts = []
    
    # 1. Read result JSON
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env(RESULT_PATH, tmp_path)
        with open(tmp_path, "r") as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result file: {e}"}

    task_start = result.get("task_start", 0)

    # 2. Directory Exists (5 pts)
    if result.get("dir_exists"):
        score += 5
        feedback_parts.append("[+5] Directory /home/ga/reports exists")
    else:
        feedback_parts.append("[-] Directory missing")
        
    files = result.get("files", {})
    script_content = result.get("script_content", "").lower()
    
    # 3. Evaluate Image 1: Fleet CPU
    img1_score, img1_fb = _eval_image(files.get("fleet_cpu_overview.png", {}), expected_w, expected_h, min_size_kb, task_start)
    score += img1_score
    feedback_parts.append(f"Image 1: " + ", ".join(img1_fb))
    
    # Image 1 Script targets (10 pts)
    if all(x in script_content for x in ["ec2_instance_1", "ec2_instance_2", "cloudwatch_utilization"]):
        score += 10
        feedback_parts.append("[+10] Script has Fleet CPU targets")
    else:
        feedback_parts.append("[-] Script missing Fleet CPU targets")

    # 4. Evaluate Image 2: Disk Write
    img2_score, img2_fb = _eval_image(files.get("disk_write_rate.png", {}), expected_w, expected_h, min_size_kb, task_start)
    score += img2_score
    feedback_parts.append(f"Image 2: " + ", ".join(img2_fb))
    
    # Image 2 Script derivative (10 pts)
    if "derivative" in script_content and "disk.write_bytes" in script_content:
        score += 10
        feedback_parts.append("[+10] Script uses derivative() for disk")
    else:
        feedback_parts.append("[-] Script missing derivative() for disk")

    # 5. Evaluate Image 3: Temperature
    img3_score, img3_fb = _eval_image(files.get("temperature_analysis.png", {}), expected_w, expected_h, min_size_kb, task_start)
    score += img3_score
    feedback_parts.append(f"Image 3: " + ", ".join(img3_fb))
    
    # Image 3 Script movingAverage (10 pts)
    if "movingaverage" in script_content and "machine_temperature" in script_content:
        score += 10
        feedback_parts.append("[+10] Script uses movingAverage() for temp")
    else:
        feedback_parts.append("[-] Script missing movingAverage() for temp")

    # 6. Evaluate Script General Constraints
    if result.get("script_exists") and result.get("script_executable"):
        score += 7
        feedback_parts.append("[+7] Script exists and is executable")
    elif result.get("script_exists"):
        score += 3
        feedback_parts.append("[+3] Script exists but NOT executable")
    else:
        feedback_parts.append("[-] Script missing")
        
    if all(x in script_content for x in ["fleet_cpu_overview.png", "disk_write_rate.png", "temperature_analysis.png"]):
        score += 7
        feedback_parts.append("[+7] Script specifies all three output files")
    
    if "alias(" in script_content:
        score += 5
        feedback_parts.append("[+5] Script utilizes alias() function")
        
    # 7. VLM Trajectory Verification (10 pts)
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(trajectory, n=4)
        if frames:
            vlm_res = query_vlm(images=frames, prompt=VLM_TERMINAL_PROMPT)
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("terminal_opened") and parsed.get("shell_commands_visible"):
                    vlm_score = 10
                    feedback_parts.append("[+10] VLM confirms terminal usage")
                else:
                    feedback_parts.append("[-] VLM did not clearly see terminal interaction")
            else:
                feedback_parts.append("[!] VLM query failed, skipping terminal visual check")
        else:
            feedback_parts.append("[!] No trajectory frames to check")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        feedback_parts.append(f"[!] VLM verification error: {e}")
        
    score += vlm_score

    # Final tally
    passed = score >= 60 and result.get("script_exists", False)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }