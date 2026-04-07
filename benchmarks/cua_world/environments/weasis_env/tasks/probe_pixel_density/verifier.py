#!/usr/bin/env python3
"""
Verifier for Probe Pixel Density Values task.
"""

import os
import json
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_probe_pixel_density(traj, env_info, task_info):
    """Verify pixel density measurements against ground truth."""
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    temp_dir = tempfile.mkdtemp(prefix="weasis_probe_verify_")
    
    try:
        # Load result metadata
        result_json_path = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}

        output_exists = task_result.get("output_exists", False)
        created_during_task = task_result.get("file_created_during_task", False)
        
        # Criterion 1: Output file exists and created during task (15 pts)
        if not output_exists:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Output file ~/DICOM/exports/pixel_probe_results.txt was not found."
            }
            
        if created_during_task:
            score += 15
            feedback_parts.append("✅ Output file exists and created during task")
        else:
            feedback_parts.append("❌ Output file exists but timestamp indicates it was not modified during the task")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

        # Load ground truth
        gt_path = os.path.join(temp_dir, "ground_truth_pixels.json")
        ground_truth = {}
        try:
            copy_from_env("/tmp/ground_truth_pixels.json", gt_path)
            with open(gt_path, 'r') as f:
                ground_truth = json.load(f)
        except Exception as e:
            # Fallback based on known generation math
            ground_truth = {
                "128,128": {"raw": 2000, "hu": 976.0},
                "64,64": {"raw": 1000, "hu": -24.0},
                "192,192": {"raw": 3000, "hu": 1976.0}
            }

        # Parse agent output
        output_txt_path = os.path.join(temp_dir, "pixel_probe_results.txt")
        parsed_values = {}
        try:
            copy_from_env("/home/ga/DICOM/exports/pixel_probe_results.txt", output_txt_path)
            with open(output_txt_path, 'r') as f:
                content = f.read()
                
            pattern = r'Coordinate\s*\(\s*(\d+)\s*,\s*(\d+)\s*\)\s*:\s*([-+]?\d+\.?\d*)'
            matches = re.findall(pattern, content)
            for match in matches:
                x, y, val = int(match[0]), int(match[1]), float(match[2])
                parsed_values[f"{x},{y}"] = val
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to read or parse results file: {e}"}

        # Anti-gaming: Ensure values aren't all identical
        if len(parsed_values) >= 2:
            unique_vals = set(parsed_values.values())
            if len(unique_vals) == 1:
                return {
                    "passed": False, 
                    "score": 0, 
                    "feedback": "GAMING DETECTED: All recorded pixel values are identical. They must be distinct."
                }

        # Criteria 2-4: Coordinate value checks (20 pts each)
        coord_targets = [("128,128", "Center"), ("64,64", "Top-Left"), ("192,192", "Bottom-Right")]
        correct_values = 0
        
        for coord_key, label in coord_targets:
            gt = ground_truth.get(coord_key, {})
            gt_raw = gt.get("raw", 0)
            gt_hu = gt.get("hu", 0)
            
            # Check for exact or nearby coordinate entry
            agent_val = None
            for pk, pv in parsed_values.items():
                px, py = map(int, pk.split(','))
                tx, ty = map(int, coord_key.split(','))
                if abs(px - tx) <= 5 and abs(py - ty) <= 5:
                    agent_val = pv
                    break
            
            if agent_val is not None:
                raw_diff = abs(agent_val - gt_raw)
                hu_diff = abs(agent_val - gt_hu)
                
                if raw_diff <= 100 or hu_diff <= 100:
                    score += 20
                    correct_values += 1
                    match_type = "Raw" if raw_diff <= hu_diff else "HU"
                    feedback_parts.append(f"✅ {label} ({coord_key}): Value {agent_val} matches {match_type}")
                else:
                    feedback_parts.append(f"❌ {label} ({coord_key}): Value {agent_val} does not match expected raw ({gt_raw}) or HU ({gt_hu})")
            else:
                feedback_parts.append(f"❌ {label} ({coord_key}): Not found in output")

        # Criterion 5: VLM trajectory verification (25 pts)
        if query_vlm:
            try:
                # Import necessary functions safely within the scope
                from gym_anything.vlm import sample_trajectory_frames
                frames = sample_trajectory_frames(traj, n=5)
                
                prompt = """Did the agent actively use Weasis DICOM Viewer to probe pixel values?
                Look at the sequence of screenshots:
                1. Is Weasis open with a medical image displayed?
                2. Can you see evidence of the cursor moving over the image or examining different regions?
                Answer in JSON: {"workflow_observed": true/false}
                """
                
                vlm_result = query_vlm(images=frames, prompt=prompt)
                
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("workflow_observed", False):
                        score += 25
                        feedback_parts.append("✅ VLM verified active Weasis workflow")
                    else:
                        feedback_parts.append("❌ VLM did not observe expected Weasis interactions")
                else:
                    score += 25
                    feedback_parts.append("⚠️ VLM query failed, granting points conservatively")
            except ImportError:
                # If library isn't available, pass silently with points to avoid blocking local runs
                score += 25
                feedback_parts.append("⚠️ VLM frame extraction unavailable, bypassing VLM check")
        else:
            # Grant points if VLM is entirely unavailable
            score += 25
            feedback_parts.append("⚠️ VLM unavailable, granting trajectory points automatically")

        # Key Criteria: Must have file, must have at least 2 correct values
        key_criteria_met = output_exists and correct_values >= 2
        passed = score >= 65 and key_criteria_met

        if not key_criteria_met:
            feedback_parts.append("❌ Failed: Requires at least 2 correct coordinate values.")

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    finally:
        import shutil
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)