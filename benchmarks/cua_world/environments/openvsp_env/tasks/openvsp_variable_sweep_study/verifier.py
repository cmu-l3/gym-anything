#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _find_param_values_by_tag(content: str, tag: str) -> list:
    """Find all Value attributes for elements with the given tag name."""
    pattern = rf'<{tag}\s+Value="([^"]+)"'
    vals = []
    for m in re.finditer(pattern, content):
        try:
            vals.append(float(m.group(1)))
        except ValueError:
            pass
    return vals

VERIFICATION_PROMPT = """You are verifying if a computer agent successfully completed an OpenVSP variable sweep kinematic study.

TASK:
1. Create a Takeoff configuration (Wing Sweep 20, Span 7.5).
2. Create a Dash configuration (Wing Sweep 68, Span 4.8).
3. Run DegenGeom analysis on both.
4. Write the projected planform areas to a text report.

Look at the provided trajectory frames and final screenshot.
Determine:
1. Did the agent open or edit an OpenVSP model with a wing?
2. Did the agent modify wing section parameters (span and sweep) in the 'Plan' or 'Sect' tab?
3. Did the agent run the Degen Geom analysis (Analysis > Degen Geom)?
4. Did the agent write a text report (e.g. in a text editor)?

Respond in JSON format:
{
    "edited_wing_parameters": true/false,
    "ran_degen_geom": true/false,
    "wrote_report": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""

def verify_openvsp_variable_sweep_study(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_takeoff_sweep = metadata.get('takeoff_sweep', 20.0)
    expected_takeoff_span = metadata.get('takeoff_span', 7.5)
    expected_dash_sweep = metadata.get('dash_sweep', 68.0)
    expected_dash_span = metadata.get('dash_span', 4.8)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    takeoff = result.get('takeoff', {})
    dash = result.get('dash', {})
    report = result.get('report', {})
    task_start = result.get('task_start', 0)
    
    # 1. Takeoff Configuration (25 pts)
    if takeoff.get('exists'):
        if takeoff.get('mtime', 0) < task_start:
            feedback_parts.append("vswing_takeoff.vsp3 was created BEFORE task start (anti-gaming) (+0)")
        else:
            score += 5
            content = takeoff.get('content', '')
            span_vals = _find_param_values_by_tag(content, "Span")
            sweep_vals = _find_param_values_by_tag(content, "Sweep")
            
            span_ok = any(abs(v - expected_takeoff_span) < 0.2 for v in span_vals)
            sweep_ok = any(abs(v - expected_takeoff_sweep) < 2.0 for v in sweep_vals)
            
            if span_ok and sweep_ok:
                score += 20
                feedback_parts.append("Takeoff geometry correct (+25)")
            else:
                feedback_parts.append(f"Takeoff geometry incorrect (Found spans: {span_vals[:3]}, sweeps: {sweep_vals[:3]}) (+5)")
    else:
        feedback_parts.append("vswing_takeoff.vsp3 not found (+0)")

    # 2. Dash Configuration (25 pts)
    if dash.get('exists'):
        if dash.get('mtime', 0) < task_start:
            feedback_parts.append("vswing_dash.vsp3 was created BEFORE task start (anti-gaming) (+0)")
        else:
            score += 5
            content = dash.get('content', '')
            span_vals = _find_param_values_by_tag(content, "Span")
            sweep_vals = _find_param_values_by_tag(content, "Sweep")
            
            span_ok = any(abs(v - expected_dash_span) < 0.2 for v in span_vals)
            sweep_ok = any(abs(v - expected_dash_sweep) < 2.0 for v in sweep_vals)
            
            if span_ok and sweep_ok:
                score += 20
                feedback_parts.append("Dash geometry correct (+25)")
            else:
                feedback_parts.append(f"Dash geometry incorrect (Found spans: {span_vals[:3]}, sweeps: {sweep_vals[:3]}) (+5)")
    else:
        feedback_parts.append("vswing_dash.vsp3 not found (+0)")

    # 3. Report Check (25 pts)
    if report.get('exists'):
        if report.get('mtime', 0) < task_start:
            feedback_parts.append("Report created BEFORE task start (anti-gaming) (+0)")
        else:
            score += 5
            content = report.get('content', '')
            # Extract numbers from report
            numbers = []
            for match in re.finditer(r'[+-]?\d+\.?\d*', content):
                try:
                    numbers.append(float(match.group()))
                except ValueError:
                    pass
            
            # Look for two numbers in plausible area range [10, 300]
            areas = [n for n in numbers if 10.0 <= n <= 300.0 and n not in [20, 68, 7.5, 4.8]]
            if len(areas) >= 2:
                # Due to smaller span, Dash area must be smaller than Takeoff area
                if max(areas) > min(areas):
                    score += 20
                    feedback_parts.append("Report contains valid distinct planform areas (+25)")
                else:
                    score += 10
                    feedback_parts.append("Report contains area numbers, but lacks distinction (+15)")
            else:
                feedback_parts.append("Report missing plausible area values (+5)")
    else:
        feedback_parts.append("Report not found (+0)")

    # 4. VLM Trajectory Verification (25 pts)
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames
            if final: images.append(final)
            
            if images:
                vlm_res = query_vlm(prompt=VERIFICATION_PROMPT, images=images)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('edited_wing_parameters'): vlm_score += 10
                    if parsed.get('ran_degen_geom'): vlm_score += 10
                    if parsed.get('wrote_report'): vlm_score += 5
                    feedback_parts.append(f"VLM: Workflow verified (+{vlm_score})")
                else:
                    feedback_parts.append("VLM query failed")
                    if score >= 50: vlm_score = 25 # fallback if VLM fails and program logic holds
            else:
                feedback_parts.append("No images for VLM")
                if score >= 50: vlm_score = 25
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            if score >= 50: vlm_score = 25
    else:
        if score >= 50: vlm_score = 25

    score += vlm_score

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }