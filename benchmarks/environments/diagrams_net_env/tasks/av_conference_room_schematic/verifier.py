#!/usr/bin/env python3
"""
Verifier for AV Conference Room Schematic Task.

Checks:
1. File creation/modification (Anti-gaming).
2. Presence of required devices (Fuzzy text matching).
3. Correct Topology (Dante vs HDMI vs USB).
4. Visual Styling (Distinction between cable types).
5. PDF Export.
6. VLM Verification of trajectory (Process check).
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def check_device_presence(shapes, device_keywords):
    """
    Returns True if a shape label matches keywords.
    """
    for shape in shapes:
        label = shape.get('label', '').lower()
        if all(k in label for k in device_keywords):
            return True
    return False

def check_connection(edges, source_keywords, target_keywords):
    """
    Returns the edge if a connection exists between source and target matching keywords.
    """
    for edge in edges:
        src = edge.get('source_label', '').lower()
        tgt = edge.get('target_label', '').lower()
        
        # Check forward direction
        src_match = all(k in src for k in source_keywords)
        tgt_match = all(k in tgt for k in target_keywords)
        
        # Check reverse direction (undirected graph logic for cables)
        rev_src_match = all(k in src for k in target_keywords)
        rev_tgt_match = all(k in tgt for k in source_keywords)
        
        if (src_match and tgt_match) or (rev_src_match and rev_tgt_match):
            return edge
    return None

def verify_av_schematic(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Basic File Checks
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "No .drawio file found."}
        
    if not result.get('file_created_during_task'):
        return {"passed": False, "score": 0, "feedback": "File was not modified during the task."}
    
    score += 10 # File created/modified
    
    diagram_data = result.get('diagram_data', {})
    shapes = diagram_data.get('shapes', [])
    edges = diagram_data.get('edges', [])
    
    # 3. Device Presence Check (15 pts)
    devices = [
        (["mxa", "920"], "Microphone"),
        (["core", "8"], "DSP"),
        (["switch"], "Network Switch"),
        (["pc", "lenovo"], "PC"),
        (["display", "samsung"], "Display"),
        (["camera", "aver"], "Camera")
    ]
    
    devices_found = 0
    for keywords, name in devices:
        if check_device_presence(shapes, keywords):
            devices_found += 1
    
    if devices_found >= 5:
        score += 15
        feedback.append(f"Found {devices_found}/6 required devices.")
    else:
        score += int((devices_found / 6) * 15)
        feedback.append(f"Missing some devices. Found {devices_found}/6.")

    # 4. Topology Checks (40 pts)
    # Critical: Mic to Switch (Dante)
    mic_switch = check_connection(edges, ["mxa"], ["switch"])
    if mic_switch:
        score += 20
        feedback.append("Correct: Mic connected to Switch (Dante).")
    else:
        # Check if they connected Mic to DSP (Common Mistake)
        if check_connection(edges, ["mxa"], ["core"]):
            feedback.append("Incorrect: Mic connected directly to DSP (Should be via Switch/Dante).")
        else:
            feedback.append("Missing: Mic to Switch connection.")

    # DSP to Switch
    dsp_switch = check_connection(edges, ["core"], ["switch"])
    if dsp_switch:
        score += 10
        feedback.append("Correct: DSP connected to Switch.")
    
    # PC to Display
    pc_display = check_connection(edges, ["pc"], ["display"])
    if pc_display:
        score += 10
        feedback.append("Correct: PC connected to Display.")

    # 5. Style Distinction (15 pts)
    # Check if Network cables look different from HDMI cables
    if mic_switch and pc_display:
        style_mic = mic_switch.get('style', '')
        style_hdmi = pc_display.get('style', '')
        
        # Simple check: are the style strings different?
        # A more robust check would parse color codes, but difference is a good proxy for intent
        if style_mic != style_hdmi:
            score += 15
            feedback.append("Good: Different styles used for Network and HDMI.")
        else:
            feedback.append("Style warning: Network and HDMI cables look identical.")
    
    # 6. PDF Export (10 pts)
    if result.get('pdf_exists'):
        score += 10
        feedback.append("PDF export found.")

    # 7. VLM Verification (10 pts)
    # Check trajectory to ensure they didn't just open a pre-made file or paste an image
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if frames:
        vlm_prompt = (
            "Analyze these screenshots of a user using Diagrams.net (draw.io). "
            "Did the user progressively build a diagram? "
            "Look for: 1. Adding shapes 2. Drawing lines 3. Editing text. "
            "Reply 'YES' if work was done, 'NO' if the screen remained static or blank."
        )
        try:
            vlm_response = query_vlm(images=frames, prompt=vlm_prompt).get('parsed', '')
            if "YES" in str(vlm_response).upper():
                score += 10
                feedback.append("VLM confirmed active work.")
            else:
                feedback.append("VLM did not detect diagramming activity.")
        except:
            score += 10 # Fallback if VLM fails, assume innocent
            
    # Calculate Final
    passed = score >= 65 and mic_switch is not None
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }