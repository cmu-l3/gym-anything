#!/usr/bin/env python3
"""
Verifier for visualize_critical_section task.

Criteria:
1. Agent identifies the correct River Station (max depth).
2. Agent reports the correct max depth (within tolerance).
3. Agent produces a visualization (PNG).
4. VLM verification: Plot shows water, terrain, and correct title.
"""

import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_visualize_critical_section(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Extract Ground Truth
    ground_truth = result.get("ground_truth", {})
    gt_station = ground_truth.get("ground_truth_station", "UNKNOWN")
    gt_depth = ground_truth.get("ground_truth_depth", 0.0)
    
    if "error" in ground_truth:
        return {"passed": False, "score": 0, "feedback": f"Ground truth calculation failed: {ground_truth['error']}"}

    # Extract Agent Report
    report_content = result.get("report_content", "")
    
    # CRITERION 1: Correct Station Identification (30 pts)
    # Check if the GT station string appears in the report
    station_match = False
    if gt_station in report_content:
        station_match = True
        score += 30
        feedback.append(f"Correct critical station identified: {gt_station}")
    else:
        feedback.append(f"Critical station {gt_station} not found in report.")

    # CRITERION 2: Accurate Depth (20 pts)
    # Find numbers in the report and check if any are close to GT depth
    depth_match = False
    # Regex to find floats
    numbers = [float(x) for x in re.findall(r"[-+]?\d*\.\d+|\d+", report_content)]
    
    tolerance = 0.5 # ft
    for num in numbers:
        if abs(num - gt_depth) <= tolerance:
            depth_match = True
            break
            
    if depth_match:
        score += 20
        feedback.append(f"Reported depth matches ground truth ({gt_depth:.2f} ft)")
    else:
        feedback.append(f"No reported value close to max depth {gt_depth:.2f} ft")

    # CRITERION 3: Plot Creation (20 pts)
    plot_path = result.get("plot_path", "")
    plot_exists = result.get("plot_exists", False)
    plot_fresh = result.get("plot_created_during_task", False)
    
    if plot_exists and plot_fresh:
        score += 20
        feedback.append("Visualization plot created.")
        
        # CRITERION 4: VLM Visual Verification (30 pts)
        # We need to pull the image file to verify it
        local_plot_path = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
        try:
            copy_from_env(plot_path, local_plot_path)
            
            vlm_prompt = f"""
            Analyze this cross-section plot of a river.
            1. Does the image contain a filled area representing water (usually blue)?
            2. Does the image contain a terrain profile (ground line)?
            3. Does the text '{gt_station}' appear in the title or legend?
            
            Return JSON: {{ "has_water": bool, "has_terrain": bool, "has_station_id": bool }}
            """
            
            vlm_res = query_vlm(prompt=vlm_prompt, image=local_plot_path)
            
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                
                if parsed.get("has_water"):
                    score += 10
                    feedback.append("VLM: Water layer visible.")
                else:
                    feedback.append("VLM: Water layer NOT detected.")
                    
                if parsed.get("has_terrain"):
                    score += 10
                    feedback.append("VLM: Terrain profile visible.")
                
                if parsed.get("has_station_id"):
                    score += 10
                    feedback.append("VLM: Station ID found in plot.")
                else:
                    feedback.append(f"VLM: Station ID {gt_station} NOT detected in plot.")
            else:
                feedback.append("VLM analysis failed.")
                
        except Exception as e:
            feedback.append(f"Failed to copy plot for verification: {e}")
        finally:
            if os.path.exists(local_plot_path):
                os.unlink(local_plot_path)
                
    else:
        feedback.append("Visualization plot not found or not created during task.")

    passed = (score >= 70) and station_match
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }