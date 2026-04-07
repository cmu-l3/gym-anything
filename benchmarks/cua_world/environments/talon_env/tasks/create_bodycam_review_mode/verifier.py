#!/usr/bin/env python3
"""
Verifier for create_bodycam_review_mode task.

VERIFICATION STRATEGY:
1. File Verification: Evaluates if both `bodycam.py` and `bodycam.talon` were created.
2. Static AST/Regex Analysis (Python): Checks for Talon @mod.action_class decorator, 
   the specified logging function, and logic indicating CSV writing.
3. Static Regex Analysis (Talon): Checks for context headers, correct shortcut 
   mappings, and linkage to the custom Python function.
4. Visual Trajectory Analysis (VLM): Verifies workflow progression via framework trajectory.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying an AI agent that is configuring Talon Voice accessibility software.
The agent was asked to create configuration files (`bodycam.py` and `bodycam.talon`) to enable voice controls for reviewing BodyCam footage.

Examine the provided trajectory images and determine:
1. Did the agent open a text editor (like Notepad)?
2. Is there visual evidence of the agent writing Python code defining a Talon module/action?
3. Is there visual evidence of the agent writing a .talon file containing voice commands like 'video play', 'skip forward', etc.?

Return a JSON object:
{
    "opened_editor": true/false,
    "edited_python": true/false,
    "edited_talon": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}
"""

def verify_create_bodycam_review_mode(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve the exported JSON from the container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse task_result.json: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    py_exists = result.get("py_exists", False)
    talon_exists = result.get("talon_exists", False)
    py_content = result.get("py_content", "")
    talon_content = result.get("talon_content", "")

    # Check 1: File Existence (10 pts)
    if py_exists and talon_exists:
        score += 10
        feedback_parts.append("Both configuration files created successfully")
    else:
        missing = []
        if not py_exists: missing.append("bodycam.py")
        if not talon_exists: missing.append("bodycam.talon")
        feedback_parts.append(f"Missing expected files: {', '.join(missing)}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Check 2: Python Action Logic (20 pts)
    py_score = 0
    if py_content:
        # Check for module creation/action registration
        if re.search(r'@mod\.action_class|talon\.Module', py_content):
            py_score += 5
        # Check for function definition
        if re.search(r'def log_bodycam_event\s*\(', py_content):
            py_score += 5
        # Check for append mode write operation indicating logging
        if re.search(r'open\([^)]+[\'"]a[\'"]\)', py_content) or re.search(r'\.append\(', py_content):
            py_score += 5
        # Check for timestamp presence
        if re.search(r'datetime|time\.', py_content):
            py_score += 5
            
    score += py_score
    feedback_parts.append(f"Python Logic Score: {py_score}/20")

    # Check 3: Talon Context Header (10 pts)
    if re.search(r'(title|win\.title):\s*.*BodyCam.*', talon_content, re.IGNORECASE):
        score += 10
        feedback_parts.append("Talon context header targets BodyCam windows")
    else:
        feedback_parts.append("Missing or incorrect Talon context header")

    # Check 4: Voice Playback Mappings (20 pts)
    mappings = {
        r"video play:\s*key\(k\)": "video play",
        r"video pause:\s*key\(k\)": "video pause",
        r"skip forward:\s*key\(l\)": "skip forward",
        r"skip back:\s*key\(j\)": "skip back",
        r"frame next:\s*key\([.]|\bdot\b\)": "frame next",
        r"frame back:\s*key\([,]|\bcomma\b\)": "frame back",
        r"speed up:\s*key\(shift-[>.]\)": "speed up",
        r"speed down:\s*key\(shift-[<,]\)": "speed down"
    }
    
    mapping_hits = 0
    for regex, name in mappings.items():
        if re.search(regex, talon_content, re.IGNORECASE):
            mapping_hits += 1
            
    mapping_score = int((mapping_hits / len(mappings)) * 20)
    score += mapping_score
    feedback_parts.append(f"Keyboard mappings: {mapping_hits}/{len(mappings)} correct ({mapping_score}/20 pts)")

    # Check 5: Event Logging Linkage (20 pts)
    if re.search(r'log event\s*<(?:user\.)?text>:\s*user\.log_bodycam_event\(', talon_content, re.IGNORECASE):
        score += 20
        feedback_parts.append("Talon effectively mapped log event to Python action")
    else:
        feedback_parts.append("Failed to map log event voice command to custom Python action")

    # Check 6: VLM Trajectory Verification (20 pts)
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        query_vlm_fn = env_info.get('query_vlm')
        
        if query_vlm_fn:
            frames = sample_trajectory_frames(traj, n=5)
            vlm_result = query_vlm_fn(prompt=VLM_PROMPT, images=frames)
            
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("edited_python", False): vlm_score += 10
                if parsed.get("edited_talon", False): vlm_score += 10
                feedback_parts.append(f"VLM visual evidence score: {vlm_score}/20")
            else:
                feedback_parts.append("VLM query failed")
        else:
            feedback_parts.append("VLM functionality unavailable for trajectory check")
    except Exception as e:
        feedback_parts.append(f"VLM verification exception: {e}")
        
    score += vlm_score

    # Final logic
    key_criteria_met = (py_exists and talon_exists and mapping_score > 10 and py_score > 10)
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }