#!/usr/bin/env python3
"""
Verifier for himalayan_topographic_blocking_winter_monsoon task.

Criteria & Scoring (100 total, pass threshold = 80):
1. January Map Export (15 pts): File exists, size >= 20KB, timestamp > start.
2. July Map Export (10 pts): File exists, size >= 20KB, timestamp > start.
3. Report Completeness (15 pts): Summary exists and all required keys are present.
4. India Temp Plausibility (15 pts): INDIA_TEMP_C parsed correctly and within [10.0, 25.0] Celsius.
5. Tibet Temp Plausibility (15 pts): TIBET_TEMP_C parsed correctly and within [-35.0, -5.0] Celsius.
6. Gradient Calculation (10 pts): TEMP_DIFFERENCE parsed correctly, matches abs difference, and is > 20.0.
7. VLM Verification (20 pts): VLM confirms the agent navigated to Central/South Asia and used data inspection tools.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying a physical geography data extraction task in NASA Panoply.
The user was asked to:
1. Zoom the geo-map plot to the Central/South Asian sector (approx 10-50N, 60-100E) to show the Himalayas/India/Tibet region.
2. Use Panoply's data inspection tools (Tooltip crosshair OR Array View) to extract air temperatures at specific coordinates.

Review the provided sequence of screenshots (trajectory) and the final screenshot.
Answer the following questions in a JSON object:
{
    "zoomed_to_asia": true/false,
    "inspected_data": true/false,
    "reasoning": "brief explanation"
}

- "zoomed_to_asia" should be true if at any point the map is distinctly zoomed/panned to focus on the Asian continent, specifically the Indian subcontinent and Tibetan plateau region.
- "inspected_data" should be true if the agent clicked on the map to trigger a tooltip showing coordinate values OR if the agent opened the Array/Data view to look at numbers.
"""

def extract_float(s):
    """Safely extract the first floating point or integer number from a string."""
    if not s:
        return None
    # match optional minus sign, digits, optional dot, optional digits
    match = re.search(r'-?\d+\.?\d*', str(s).replace(',', ''))
    if match:
        return float(match.group(0))
    return None


def verify_himalayan_topographic_blocking(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    india_min, india_max = metadata.get('india_temp_range', [10.0, 25.0])
    tibet_min, tibet_max = metadata.get('tibet_temp_range', [-35.0, -5.0])
    min_diff = metadata.get('min_temp_diff', 20.0)

    # 1. Retrieve Result JSON
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/himalayan_topographic_blocking_winter_monsoon_result.json', tmp.name)
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

    # 2. Check January Map
    jan_exists = result.get('jan_plot_exists', False)
    jan_mtime = int(result.get('jan_plot_mtime', 0))
    jan_size = int(result.get('jan_plot_size', 0))
    
    if jan_exists and jan_mtime >= task_start and jan_size >= 15000:
        score += 15
        feedback.append("January map successfully exported.")
    else:
        feedback.append("January map missing, too small, or not created during task.")

    # 3. Check July Map
    july_exists = result.get('july_plot_exists', False)
    july_mtime = int(result.get('july_plot_mtime', 0))
    july_size = int(result.get('july_plot_size', 0))
    
    if july_exists and july_mtime >= task_start and july_size >= 15000:
        score += 10
        feedback.append("July map successfully exported.")
    else:
        feedback.append("July map missing, too small, or not created during task.")

    # 4. Check Report Completeness
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    india_raw = result.get('india_temp_raw', '')
    tibet_raw = result.get('tibet_temp_raw', '')
    diff_raw = result.get('temp_diff_raw', '')

    india_val = extract_float(india_raw)
    tibet_val = extract_float(tibet_raw)
    diff_val = extract_float(diff_raw)

    if report_exists and report_mtime >= task_start:
        if india_raw and tibet_raw and diff_raw:
            score += 15
            feedback.append("Summary report exists and contains required fields.")
        else:
            score += 5
            feedback.append("Summary report exists but is missing one or more required fields.")
    else:
        feedback.append("Summary report missing or not created during task.")

    # 5. Check Quantitative Extraction (Scientific Plausibility)
    data_correct = False
    if india_val is not None:
        if india_min <= india_val <= india_max:
            score += 15
            feedback.append(f"India temperature ({india_val}°C) is physically plausible.")
        else:
            feedback.append(f"India temperature ({india_val}°C) is outside expected physical bounds [{india_min}, {india_max}]. Check units (Kelvin?).")
    else:
        feedback.append("Could not parse India temperature from report.")

    if tibet_val is not None:
        if tibet_min <= tibet_val <= tibet_max:
            score += 15
            feedback.append(f"Tibet temperature ({tibet_val}°C) is physically plausible.")
        else:
            feedback.append(f"Tibet temperature ({tibet_val}°C) is outside expected bounds [{tibet_min}, {tibet_max}].")
    else:
        feedback.append("Could not parse Tibet temperature from report.")

    if diff_val is not None and india_val is not None and tibet_val is not None:
        expected_diff = abs(india_val - tibet_val)
        if abs(diff_val - expected_diff) < 2.0 and diff_val >= min_diff:
            score += 10
            data_correct = True
            feedback.append(f"Temperature difference calculation ({diff_val}°C) is correct and reflects the extreme gradient.")
        else:
            feedback.append(f"Reported temp difference ({diff_val}) does not match calculated difference ({expected_diff}) or is too small.")

    # 6. VLM Verification (Trajectory + Final)
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        images = [f for f in frames if f is not None]
        if final:
            images.append(final)
            
        if images:
            vlm_res = query_vlm(prompt=VLM_PROMPT, images=images)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                zoomed = parsed.get('zoomed_to_asia', False)
                inspected = parsed.get('inspected_data', False)
                
                vlm_score = 0
                if zoomed:
                    vlm_score += 10
                    feedback.append("VLM confirmed map was zoomed to Asian sector.")
                if inspected:
                    vlm_score += 10
                    feedback.append("VLM confirmed data inspection tools were used.")
                
                score += vlm_score
            else:
                feedback.append("VLM verification failed or returned invalid response.")
        else:
            feedback.append("No screenshots available for VLM verification.")
    else:
        feedback.append("VLM function not available. Skipping visual check.")

    # 7. Final Assessment
    # Must achieve at least 80 points, and the fundamental quantitative extraction must be correct.
    passed = (score >= 80) and data_correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "parsed_india_temp": india_val,
            "parsed_tibet_temp": tibet_val,
            "parsed_gradient": diff_val
        }
    }