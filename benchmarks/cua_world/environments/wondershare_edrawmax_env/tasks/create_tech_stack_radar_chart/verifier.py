#!/usr/bin/env python3
"""
Verifier for create_tech_stack_radar_chart task.
"""

import json
import os
import tempfile
import zipfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_radar_chart(traj, env_info, task_info):
    """
    Verifies the creation of a Cloud Provider Radar Chart.
    
    Strategy:
    1. File Validation (40%): Checks if .eddx and .png exist and were created during the task.
    2. Content Analysis (30%): Unzips .eddx to check for specific data labels (AWS, Azure, Cost Efficiency).
    3. VLM Verification (30%): Checks trajectory for chart editing workflow and final visual output.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    score = 0
    feedback = []
    
    # ------------------------------------------------------------------
    # 1. Retrieve Task Result JSON
    # ------------------------------------------------------------------
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix=".json") as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

    # ------------------------------------------------------------------
    # 2. File Existence & Timestamp Checks (Anti-Gaming)
    # ------------------------------------------------------------------
    eddx_exists = task_result.get("eddx_exists", False)
    eddx_created = task_result.get("eddx_created_during_task", False)
    png_exists = task_result.get("png_exists", False)
    png_created = task_result.get("png_created_during_task", False)
    
    if eddx_exists:
        if eddx_created:
            score += 20
            feedback.append("Source .eddx file created successfully.")
        else:
            score += 5
            feedback.append("Source file exists but has old timestamp (pre-existing?).")
    else:
        feedback.append("Source .eddx file not found.")

    if png_exists:
        if png_created:
            score += 20
            feedback.append("Exported .png image created successfully.")
        else:
            score += 5
            feedback.append("Exported image exists but has old timestamp.")
    else:
        feedback.append("Exported .png image not found.")

    # Stop here if essential files are missing to save compute
    if not eddx_exists:
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # ------------------------------------------------------------------
    # 3. Content Analysis (Deep Inspection of .eddx XML)
    # ------------------------------------------------------------------
    # Copy .eddx from env to check content
    content_score = 0
    with tempfile.NamedTemporaryFile(suffix=".eddx") as f:
        try:
            copy_from_env("/home/ga/Documents/cloud_radar_comparison.eddx", f.name)
            
            # EdrawMax files are ZIPs containing XML
            try:
                xml_content = ""
                with zipfile.ZipFile(f.name, 'r') as z:
                    for name in z.namelist():
                        if name.endswith(".xml"):
                            xml_content += z.read(name).decode('utf-8', errors='ignore')
                
                # Check for critical data strings
                required_strings = [
                    "AWS", "Azure", "GCP", 
                    "Cost Efficiency", "Global Availability", 
                    "Compute Performance"
                ]
                
                found_count = 0
                for s in required_strings:
                    if s in xml_content:
                        found_count += 1
                
                if found_count >= len(required_strings) - 1: # Allow 1 miss
                    content_score += 20
                    feedback.append("Data labels (Series/Categories) confirmed in file structure.")
                elif found_count > 0:
                    content_score += 10
                    feedback.append(f"Partial data found ({found_count}/{len(required_strings)} items).")
                else:
                    feedback.append("No expected data labels found in file structure.")
                    
                # Check for Title
                if "Cloud Provider Evaluation 2026" in xml_content:
                    content_score += 10
                    feedback.append("Chart title confirmed in file structure.")
                else:
                    feedback.append("Chart title missing from internal file data.")
                    
            except zipfile.BadZipFile:
                feedback.append("Saved .eddx file is corrupted or not a valid archive.")

        except Exception as e:
            feedback.append(f"Error analyzing file content: {e}")
    
    score += content_score

    # ------------------------------------------------------------------
    # 4. VLM Verification (Trajectory & Final Output)
    # ------------------------------------------------------------------
    # Sample 5 frames from trajectory + final screenshot
    frames = sample_trajectory_frames(traj, n=5)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying an agent's work in EdrawMax. 
    The goal was to create a Radar/Spider chart comparing AWS, Azure, and GCP.
    
    Please analyze the images and answer:
    1. Did the agent open a 'Spider' or 'Radar' chart template?
    2. Is there a visible chart with a spider-web or pentagon shape?
    3. Can you see labels like 'AWS', 'Azure', or 'Cost Efficiency'?
    4. Is the final chart title 'Cloud Provider Evaluation 2026'?
    5. Does the chart have 3 distinct colored regions/lines?
    
    Return a JSON object with boolean keys: chart_visible, data_labels_visible, title_correct, three_series_visible.
    """
    
    vlm_score = 0
    try:
        # Use final screenshot for detailed inspection, fallback to frames if needed
        result = query_vlm(
            images=frames + [final_screen],
            prompt=vlm_prompt
        )
        
        if result and result.get("success"):
            parsed = result.get("parsed", {})
            
            if parsed.get("chart_visible", False):
                vlm_score += 10
                feedback.append("VLM confirmed radar chart visibility.")
            
            if parsed.get("data_labels_visible", False):
                vlm_score += 10
                feedback.append("VLM confirmed data labels are visible.")
            
            if parsed.get("title_correct", False):
                vlm_score += 5
                feedback.append("VLM confirmed correct chart title.")
            elif parsed.get("three_series_visible", False):
                # Fallback points if title obscure but data looks good
                vlm_score += 5
        else:
            feedback.append("VLM analysis failed or was inconclusive.")
            
    except Exception as e:
        feedback.append(f"VLM error: {e}")
        
    score += vlm_score
    
    # ------------------------------------------------------------------
    # Final Decision
    # ------------------------------------------------------------------
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }