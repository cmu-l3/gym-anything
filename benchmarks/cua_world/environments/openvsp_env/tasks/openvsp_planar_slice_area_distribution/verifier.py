#!/usr/bin/env python3
"""
Verifier for openvsp_planar_slice_area_distribution task.

Validation strategy involves:
1. Verifying the tabular slice file was generated during the task (20 pts).
2. Parsing the desktop report for numeric values using Regex (10 pts + 3x15 pts).
3. VLM trajectory verification to ensure the agent physically opened the 
   Planar Slice dialog and didn't just hallucinate a text file (25 pts).
"""

import os
import json
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_number(text, pattern):
    """Extracts the first numeric value following a regex pattern match."""
    match = re.search(pattern + r'[:\s=]+([+-]?\d+\.?\d*(?:[eE][+-]?\d+)?)', text, re.IGNORECASE)
    if match:
        try:
            return float(match.group(1))
        except ValueError:
            return None
    return None

def verify_planar_slice(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Execution error: copy_from_env not provided"}

    # 1. Fetch JSON result from environment
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    max_score = 100

    # Criteria 1: Output Slice File Exists & Has Tabular Data (20 pts)
    slice_found = result.get("slice_file_found", False)
    slice_rows = result.get("slice_data_rows", 0)
    
    if slice_found and slice_rows >= 15:
        score += 20
        feedback.append(f"✅ Slice output file found with {slice_rows} tabular rows (+20 pts).")
    elif slice_found and slice_rows > 0:
        score += 10
        feedback.append(f"⚠️ Slice output file found but has too few rows ({slice_rows}) (+10 pts).")
    else:
        feedback.append("❌ No valid Planar Slice tabular output file generated during task.")

    # Criteria 2: Report Exists (10 pts)
    report_exists = result.get("report_exists", False)
    report_content = result.get("report_content", "")
    
    if report_exists and len(report_content.strip()) > 20:
        score += 10
        feedback.append("✅ Report file successfully created (+10 pts).")
        
        # Criteria 3: Max Area Extracted (15 pts)
        max_area = extract_number(report_content, r'max(?:imum)?\s*cross[- ]?sectional\s*area')
        if max_area is None:
            max_area = extract_number(report_content, r'max(?:imum)?\s*area')
            
        if max_area is not None and max_area > 0:
            score += 15
            feedback.append(f"✅ Extracted Max Area: {max_area} (+15 pts).")
        else:
            feedback.append("❌ Could not parse valid Max Area from report.")
            
        # Criteria 4: X-Location Extracted (15 pts)
        x_loc = extract_number(report_content, r'x[- ]?location(?:\s*of\s*max(?:imum)?\s*area)?')
        if x_loc is None:
            x_loc = extract_number(report_content, r'x[- ]?loc')
            
        if x_loc is not None and x_loc >= 0:
            score += 15
            feedback.append(f"✅ Extracted X-Location: {x_loc} (+15 pts).")
        else:
            feedback.append("❌ Could not parse valid X-Location from report.")
            
        # Criteria 5: Approximate Volume Extracted (15 pts)
        volume = extract_number(report_content, r'(?:approximate|total|approx\.?)?\s*volume')
        if volume is None:
            volume = extract_number(report_content, r'vol(?:ume)?')
            
        if volume is not None and volume > 0:
            score += 15
            feedback.append(f"✅ Extracted Approximate Volume: {volume} (+15 pts).")
        else:
            feedback.append("❌ Could not parse valid Approximate Volume from report.")
    else:
        feedback.append("❌ Area Ruling Report file not found or empty.")

    # Criteria 6: VLM Trajectory Verification (25 pts)
    # Proves the agent actually used the OpenVSP GUI tool, avoiding text-hallucination gaming.
    vlm_score = 0
    query_vlm = env_info.get("query_vlm")
    
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Extract multiple frames to catch the popup dialog which may open and close
            frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            if final_frame:
                frames.append(final_frame)
                
            prompt = """Look closely at these screenshots of a user interacting with OpenVSP. 
Is there any evidence that the user opened the 'Planar Slice' or 'Slice' analysis tool? 
Look for a dialog box titled 'Planar Slice' or 'Slice', or an active slicing interface.
Respond with a JSON object: {"opened_planar_slice": true/false}"""

            vlm_res = query_vlm(prompt=prompt, images=frames)
            
            if vlm_res.get("success") and vlm_res.get("parsed", {}).get("opened_planar_slice", False):
                vlm_score = 25
                feedback.append("✅ VLM confirmed visual evidence of Planar Slice interaction (+25 pts).")
            else:
                feedback.append("❌ VLM did not find visual evidence of the Planar Slice dialog.")
        except ImportError:
            feedback.append("⚠️ Could not import VLM tools. Skipping visual confirmation.")
    else:
        feedback.append("⚠️ VLM querying unavailable in this environment.")

    score += vlm_score

    # Determine pass threshold (Must achieve >= 65 to pass)
    passed = score >= 65

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }