#!/usr/bin/env python3
"""
Verifier for convert_text_to_3d_points task.

VERIFICATION METRICS:
1. Output file exists and was created during the session (15 pts)
2. Proper point count extracted (~85 points) (15 pts)
3. Successful Z-parsing (no longer Z=0) (30 pts)
4. Coordinate Accuracy against hidden ground truth (30 pts)
5. VLM workflow trajectory check (10 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_convert_text_to_3d_points(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback = []
    score = 0
    
    # 1. Fetch export result metadata
    result_meta = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        try:
            copy_from_env("C:\\temp\\task_result.json", f.name)
            with open(f.name, 'r') as jf:
                result_meta = json.load(jf)
        except Exception as e:
            logger.error(f"Failed to read task result meta: {e}")
        finally:
            os.unlink(f.name)

    # Base existence checks
    if not result_meta.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "Failure: Expected output CSV not found at target location."}
    
    if result_meta.get("file_created_during_task"):
        score += 15
        feedback.append("File created/modified during task (+15)")
    else:
        feedback.append("File exists but was NOT created during this session (possible cheating) (+0)")

    # 2. Fetch the Agent's generated CSV
    agent_content = ""
    with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as f:
        try:
            copy_from_env("C:\\Users\\Docker\\Documents\\converted_3d_points.csv", f.name)
            with open(f.name, 'r', encoding='utf-8', errors='replace') as cf:
                agent_content = cf.read()
        except Exception as e:
            logger.error(f"Failed to copy agent CSV: {e}")
        finally:
            os.unlink(f.name)

    # Parse Agent's CSV (accounting for Spanish localization ',' vs '.')
    agent_points = []
    for line in agent_content.split('\n'):
        line = line.strip()
        if not line: continue
        
        # Detect delimiter
        sep = ';' if ';' in line else ','
        parts = line.split(sep)
        
        if len(parts) >= 4:
            try:
                # TopoCal order is typically: ID, X, Y, Z, [Code]
                x = float(parts[1].replace(',', '.'))
                y = float(parts[2].replace(',', '.'))
                z = float(parts[3].replace(',', '.'))
                agent_points.append((x, y, z))
            except ValueError:
                # Likely a header row
                pass

    # Point Count Verification
    pt_count = len(agent_points)
    if 80 <= pt_count <= 90:
        score += 15
        feedback.append(f"Correct point count exported: {pt_count} (+15)")
    elif pt_count > 0:
        score += 5
        feedback.append(f"Incorrect point count exported: {pt_count} (Expected ~85) (+5)")
    else:
        feedback.append("No valid coordinate data could be parsed from the CSV (+0)")

    # 3. Fetch Ground Truth
    gt_content = ""
    with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as f:
        try:
            copy_from_env("C:\\workspace\\data\\ground_truth\\true_coordinates.csv", f.name)
            with open(f.name, 'r') as cf:
                gt_content = cf.read()
        except Exception as e:
            logger.error(f"Failed to copy Ground Truth: {e}")
        finally:
            os.unlink(f.name)

    # Parse Ground Truth
    gt_points = []
    for line in gt_content.split('\n'):
        if not line or line.startswith('Point'): continue
        parts = line.split(',')
        if len(parts) >= 4:
            x = float(parts[1])
            y = float(parts[2])
            z = float(parts[3])
            gt_points.append((x, y, z))

    # Evaluate Accuracy and Z Parsing
    z_zero_count = 0
    matched_count = 0
    
    for px, py, pz in agent_points:
        if abs(pz) < 0.001:
            z_zero_count += 1
            
        # Match against ground truth (XY within 0.1m, Z within 0.01m)
        for gx, gy, gz in gt_points:
            if abs(px - gx) < 0.1 and abs(py - gy) < 0.1:
                if abs(pz - gz) < 0.01:
                    matched_count += 1
                break

    # Z-Parsing Scoring
    if pt_count > 0:
        if z_zero_count == 0 and pt_count > 50:
            score += 30
            feedback.append("Successfully parsed Z coordinates from text strings (+30)")
        elif z_zero_count < 10 and pt_count > 50:
            score += 15
            feedback.append(f"Partially parsed Z coordinates ({z_zero_count} zeros found) (+15)")
        else:
            feedback.append("Failed to parse Z coordinates (most points remain at Z=0) (+0)")

    # Coordinate Accuracy Scoring
    if matched_count >= 80:
        score += 30
        feedback.append(f"High coordinate accuracy: {matched_count} points match ground truth (+30)")
    elif matched_count >= 40:
        score += 15
        feedback.append(f"Partial coordinate accuracy: {matched_count} points match ground truth (+15)")
    else:
        feedback.append(f"Poor coordinate accuracy: {matched_count} points match ground truth (+0)")

    # 4. VLM Trajectory Check (Anti-gaming check)
    vlm_points = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images and env_info.get('query_vlm'):
            prompt = """You are verifying a CAD task in TopoCal (Spanish interface).
            The goal was to convert flat 2D TEXT entities into 3D survey points.
            Analyze the trajectory screenshots:
            1. Did the agent navigate to the 'Puntos' (Points) menu?
            2. Did the agent use a tool like 'Crear' -> 'De textos' (Create -> From texts)?
            3. Did the agent attempt to save or export a file?
            
            Respond in JSON format:
            {
              "used_text_conversion_tool": true,
              "reasoning": "Brief explanation of evidence found"
            }"""
            
            vlm_result = env_info['query_vlm'](images=images, prompt=prompt)
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("used_text_conversion_tool", False):
                    vlm_points = 10
                    feedback.append("VLM verified use of text conversion GUI tool (+10)")
                else:
                    feedback.append("VLM did not detect use of text conversion tool (+0)")
            else:
                feedback.append("VLM analysis failed to execute (+0)")
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        feedback.append("VLM verification skipped due to framework error.")
        
    score += vlm_points

    # Require successful Z parsing and a decent accuracy match to pass
    key_criteria_met = (z_zero_count < 10) and (matched_count > 50)
    passed = (score >= 75) and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "exported_points": pt_count,
            "z_zero_count": z_zero_count,
            "matched_ground_truth": matched_count
        }
    }