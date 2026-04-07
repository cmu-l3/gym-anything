#!/usr/bin/env python3
"""
Verifier for european_wind_nao_climatology task.

Evaluates multi-criteria signals to verify workflow execution:
1. File Existence & Modification (Map and text report)
2. Precise Quantitative Data Extraction (Verifies Panoply grid navigation)
3. Trajectory Verification via VLM
"""

import json
import os
import tempfile
import re

def verify_european_wind_nao_climatology(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/european_wind_nao_climatology_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    task_start = int(result.get('task_start', 0))

    # ----------------------------------------------------------------
    # Criterion 1: Map Exported (15 pts)
    # ----------------------------------------------------------------
    plot_exists = result.get('plot_exists', False)
    plot_mtime = int(result.get('plot_mtime', 0))
    plot_size = int(result.get('plot_size', 0))

    if plot_exists and plot_mtime >= task_start and plot_size >= 15000:
        score += 15
        feedback.append(f"Map plot exported successfully ({plot_size} bytes)")
    elif plot_exists and plot_mtime >= task_start and plot_size >= 5000:
        score += 7
        feedback.append(f"Map plot present but size is unusually small ({plot_size} bytes)")
    else:
        feedback.append(f"Map plot missing or not created during task execution")

    # ----------------------------------------------------------------
    # Criterion 2: Report Structure (10 pts)
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    iceland_raw = result.get('iceland_slp', '').strip()
    azores_raw = result.get('azores_slp', '').strip()
    gradient_raw = result.get('nao_gradient', '').strip()

    if report_exists and report_mtime >= task_start:
        if bool(iceland_raw) and bool(azores_raw) and bool(gradient_raw):
            score += 10
            feedback.append("Report structure contains all required exact data fields")
        else:
            score += 5
            feedback.append("Report exists but is missing some quantitative data fields")
    else:
        feedback.append("Report missing or not created during task execution")

    # Helper to parse floats
    def extract_float(s):
        match = re.search(r'[-+]?\d*\.\d+|\d+', s)
        if match:
            return float(match.group())
        return None

    ice_val = extract_float(iceland_raw)
    az_val = extract_float(azores_raw)
    grad_val = extract_float(gradient_raw)

    metadata = task_info.get('metadata', {})
    iceland_range = metadata.get('iceland_range', [990.0, 1005.0])
    azores_range = metadata.get('azores_range', [1015.0, 1030.0])

    ice_correct = False
    az_correct = False

    # ----------------------------------------------------------------
    # Criterion 3: Exact Iceland Value Extraction (20 pts)
    # ----------------------------------------------------------------
    if ice_val is not None:
        if iceland_range[0] <= ice_val <= iceland_range[1]:
            score += 20
            ice_correct = True
            feedback.append(f"Iceland SLP correctly extracted: {ice_val} mb")
        else:
            feedback.append(f"Iceland SLP ({ice_val} mb) physically implausible; outside range {iceland_range}")
    else:
        feedback.append("Could not parse numeric Iceland SLP value")

    # ----------------------------------------------------------------
    # Criterion 4: Exact Azores Value Extraction (20 pts)
    # ----------------------------------------------------------------
    if az_val is not None:
        if azores_range[0] <= az_val <= azores_range[1]:
            score += 20
            az_correct = True
            feedback.append(f"Azores SLP correctly extracted: {az_val} mb")
        else:
            feedback.append(f"Azores SLP ({az_val} mb) physically implausible; outside range {azores_range}")
    else:
        feedback.append("Could not parse numeric Azores SLP value")

    # ----------------------------------------------------------------
    # Criterion 5: Gradient Math (15 pts)
    # ----------------------------------------------------------------
    if ice_val is not None and az_val is not None and grad_val is not None:
        expected_grad = az_val - ice_val
        if abs(grad_val - expected_grad) < 0.2:
            score += 15
            feedback.append(f"NAO gradient correctly calculated: {grad_val} mb")
        else:
            feedback.append(f"NAO gradient math incorrect: reported {grad_val}, expected {expected_grad:.1f}")
    else:
        feedback.append("Could not verify gradient math due to missing/unparseable values")

    # ----------------------------------------------------------------
    # Criterion 6: VLM Verification of Trajectory Workflow (20 pts)
    # ----------------------------------------------------------------
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                prompt = """Look at these screenshots of a computer desktop.
The user is supposed to use NASA Panoply to create a geographic map plot of 'slp' (Sea Level Pressure), and interact with the data tools (like Array 2D view or cursor data inspection) to extract values.
Did the user successfully interact with Panoply to visualize a geographic map plot?
Respond in JSON format: {"panoply_used": true, "map_created": true}
"""
                vlm_result = query_vlm(images=images, prompt=prompt)
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("panoply_used") and parsed.get("map_created"):
                        score += 20
                        feedback.append("VLM verified Panoply usage and map creation trajectory")
                    else:
                        feedback.append("VLM did not detect successful Panoply map creation in trajectory")
                else:
                    feedback.append("VLM verification failed to run or parse")
            else:
                feedback.append("No images available for VLM verification")
        except Exception as e:
            feedback.append(f"VLM verification error: {e}")
    else:
        feedback.append("VLM query function not available")

    # To pass, the agent must achieve an 80% score AND extract the physical values correctly
    passed = score >= 80 and ice_correct and az_correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }