#!/usr/bin/env python3
"""
Verifier for Calculate Reservoir Water Capacity task.

Uses a hybrid verification strategy:
1. Programmatic Check: Parses the agent's reported capacity file, comparing to hidden ground truth.
2. VLM Trajectory Check: Reviews screenshots to ensure TopoCal TIN/Volume workflows were visibly used (preventing random guessing).
"""

import os
import re
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_calculate_reservoir_capacity(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Error: copy_from_env not available."}

    # Fetch ground truth configurations from task metadata
    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth_volume', 12450.5)
    tol_rough = metadata.get('tolerance_rough_percent', 10.0)
    tol_precise = metadata.get('tolerance_precise_percent', 2.5)

    score = 0
    feedback_parts = []
    
    # --- 1. Copy and Parse Results ---
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Windows path fetching abstraction
        try:
            copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        except Exception:
            copy_from_env("C:/tmp/task_result.json", temp_result.name)
            
        with open(temp_result.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # --- 2. Evaluate File Artifacts ---
    if result.get('project_exists'):
        if result.get('project_created_during_task'):
            score += 10
            feedback_parts.append("Project saved successfully")
        else:
            feedback_parts.append("Project exists but wasn't updated during task")
    else:
        feedback_parts.append("Project file not saved")

    # --- 3. Evaluate Report & Numerical Output ---
    report_exists = result.get('report_exists', False)
    content = result.get('report_content', '')
    volume_accuracy_achieved = False

    if report_exists:
        if result.get('report_created_during_task'):
            score += 10
            feedback_parts.append("Report created")
        else:
            feedback_parts.append("Report existed prior (not modified)")

        # Parse format: Capacity: 12450.5 m3
        match = re.search(r'Capacity:\s*([\d\.,]+)\s*m3', content, re.IGNORECASE)
        if match:
            score += 10
            feedback_parts.append("Report format correct")
            
            # Clean string and parse number (handling European comma notation if present)
            val_str = match.group(1).replace(',', '') 
            try:
                reported_vol = float(val_str)
                error_percent = abs(reported_vol - ground_truth) / ground_truth * 100

                if error_percent <= tol_precise:
                    score += 40
                    volume_accuracy_achieved = True
                    feedback_parts.append(f"Volume Precise! ({reported_vol} m3, err: {error_percent:.1f}%)")
                elif error_percent <= tol_rough:
                    score += 20
                    volume_accuracy_achieved = True
                    feedback_parts.append(f"Volume Roughly Correct ({reported_vol} m3, err: {error_percent:.1f}%)")
                else:
                    feedback_parts.append(f"Volume Inaccurate ({reported_vol} m3, err: {error_percent:.1f}%)")
            except ValueError:
                feedback_parts.append("Failed to parse volume number")
        else:
            feedback_parts.append("Report format incorrect (Expected 'Capacity: XXXX.X m3')")
    else:
        feedback_parts.append("Capacity report missing")

    # --- 4. Trajectory Evidence via VLM (Anti-Gaming) ---
    try:
        # Import dynamically depending on framework version availability
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """Analyze these trajectory screenshots of an agent using TopoCal CAD.
Determine if the agent performed the actual workflow:
1. Did the agent generate a Triangulated Terrain Model (TIN / MDT)? (Look for a mesh/grid connecting the points).
2. Did the agent open the Volume Calculation tool (Volúmenes / Por Cota)? (Look for a calculation dialog box).

Return ONLY valid JSON matching this schema:
{
    "tin_created": true/false,
    "volume_tool_used": true/false
}"""
            vlm_res = query_vlm(images=images, prompt=prompt)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('tin_created'):
                    score += 15
                    feedback_parts.append("VLM: TIN creation verified")
                if parsed.get('volume_tool_used'):
                    score += 15
                    feedback_parts.append("VLM: Volume tool usage verified")
            else:
                logger.warning("VLM call failed, skipping trajectory verification scoring.")
    except Exception as e:
        logger.warning(f"VLM verification block failed: {e}")

    # Determine passing state (Score >= 60 AND actually got a reasonably accurate volume)
    passed = (score >= 60) and volume_accuracy_achieved

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }