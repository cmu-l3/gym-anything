#!/usr/bin/env python3
"""
Verifier for svalbard_spitsbergen_current_winter_anomaly task.

Verifies map export, report parsing, scientific value extraction, and
uses VLM trajectory verification to ensure a polar projection was applied.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an agent's usage of NASA Panoply for an Arctic climate analysis.

The agent was instructed to:
1. Open a Sea Surface Temperature (SST) dataset.
2. Change the map projection from a standard equirectangular view to a Polar projection (e.g., North Polar Stereographic, North Polar Orthographic) to accurately view the Arctic Ocean.

Review the provided screenshots of the agent's session (trajectory frames and the final screen).
Did the agent successfully change the map projection to a polar view showing the Arctic from above?

Respond with a JSON object containing:
{
    "used_polar_projection": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of the visible map projection and whether it is a polar view."
}
"""

def verify_svalbard_spitsbergen_current_winter_anomaly(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON from the VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/svalbard_spitsbergen_current_winter_anomaly_result.json', tmp.name)
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

    # 1. Output File Validations (15 pts)
    plot_exists = result.get('plot_exists', False)
    plot_mtime = int(result.get('plot_mtime', 0))
    plot_size = int(result.get('plot_size', 0))

    if plot_exists and plot_mtime >= task_start and plot_size >= 15000:
        score += 15
        feedback.append(f"✅ Map exported ({plot_size} bytes).")
    elif plot_exists and plot_mtime >= task_start:
        score += 7
        feedback.append(f"⚠️ Map exported but unusually small ({plot_size} bytes).")
    else:
        feedback.append(f"❌ Map not exported or not created during task.")

    # 2. Report Validity & Structure (15 pts)
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    analysis_month = result.get('analysis_month', '').lower()
    canadian_sst_str = result.get('canadian_sst', '').strip()
    svalbard_sst_str = result.get('svalbard_sst', '').strip()
    mechanism = result.get('warming_mechanism', '').lower()

    if report_exists and report_mtime >= task_start:
        if 'feb' in analysis_month and canadian_sst_str and svalbard_sst_str and mechanism:
            score += 15
            feedback.append("✅ Report correctly formatted with all key fields.")
        else:
            score += 5
            feedback.append("⚠️ Report exists but is missing required keys or target month.")
    else:
        feedback.append("❌ Report missing or not created during task.")

    # 3. Canadian Arctic SST Check (15 pts)
    # Expected: ~ -1.8C (freezing point of seawater, minimum allowed in the ice-masked data)
    try:
        # Strip potential letters if agent added 'C'
        canadian_val = float(''.join(c for c in canadian_sst_str if c.isdigit() or c in '.-'))
        if -2.0 <= canadian_val <= -1.5:
            score += 15
            feedback.append(f"✅ Canadian SST correct ({canadian_val}°C, expected freezing range).")
        else:
            feedback.append(f"❌ Canadian SST incorrect ({canadian_val}°C). Expected ~ -1.8°C.")
    except Exception:
        feedback.append(f"❌ Could not parse Canadian SST value: '{canadian_sst_str}'.")

    # 4. Svalbard West SST Check (15 pts)
    # Expected: Warm anomaly (0.5 to 5.0)
    try:
        svalbard_val = float(''.join(c for c in svalbard_sst_str if c.isdigit() or c in '.-'))
        if 0.5 <= svalbard_val <= 5.0:
            score += 15
            feedback.append(f"✅ Svalbard SST correct ({svalbard_val}°C, showing the warm anomaly).")
        else:
            feedback.append(f"❌ Svalbard SST incorrect ({svalbard_val}°C). Expected warm anomaly > 0.5°C.")
    except Exception:
        feedback.append(f"❌ Could not parse Svalbard SST value: '{svalbard_sst_str}'.")

    # 5. Domain Knowledge / Mechanism (15 pts)
    # Valid answers: Gulf Stream, North Atlantic Drift, West Spitsbergen, Atlantic Water
    valid_mechanisms = ['gulf stream', 'spitsbergen', 'atlantic drift', 'atlantic water', 'amoc']
    if any(vm in mechanism for vm in valid_mechanisms):
        score += 15
        feedback.append(f"✅ Warming mechanism correctly identified as '{mechanism}'.")
    else:
        feedback.append(f"❌ Warming mechanism incorrect or missing ('{mechanism}').")

    # 6. VLM Verification for Map Projection (25 pts)
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if final:
            frames.append(final)
        
        vlm_resp = query_vlm(
            prompt=VLM_PROMPT,
            images=frames
        )
        
        if vlm_resp.get("success"):
            parsed = vlm_resp.get("parsed", {})
            used_polar = parsed.get("used_polar_projection", False)
            if used_polar:
                score += 25
                feedback.append("✅ VLM confirmed usage of a Polar map projection.")
            else:
                feedback.append("❌ VLM indicates equirectangular or non-polar map projection used.")
                feedback.append(f"   VLM Reasoning: {parsed.get('reasoning', '')}")
        else:
            feedback.append(f"⚠️ VLM check failed: {vlm_resp.get('error')}. Skipping VLM criteria.")
    else:
        feedback.append("⚠️ VLM not available for map projection verification.")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }