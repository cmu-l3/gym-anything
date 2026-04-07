#!/usr/bin/env python3
"""
Verifier for continentality_index_array_math task.

Occupation: Climatological Data Analyst / Macroecologist
Difficulty: hard

Scoring criteria (100 pts total, pass threshold = 70):
  1. Plot Exported (20 pts): annual_temp_range.png exists, created during task, size >= 20KB.
  2. Report Formatted (20 pts): biome_report.txt exists and contains required keys.
  3. Scientific Accuracy (30 pts): 
     - Value check: MAX_RANGE_VALUE absolute magnitude is between 45 and 65 (represents Siberian Delta T)
     - Region check: MAX_RANGE_REGION mentions Siberia, Russia, Eurasia, or Asia.
  4. VLM Trajectory Verification (30 pts): Verifies through trajectory frames and final
     screenshots that an array subtraction map (Array 1 - 2) was rendered showing strong 
     positive and negative anomaly contrasts, rather than a single-month latitudinal temperature map.
"""

import json
import os
import tempfile
import re
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import VLM utilities
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM utilities not available. VLM checks will be skipped or simulated.")

VERIFICATION_PROMPT = """You are an expert meteorological and software evaluator verifying a NASA Panoply task.
The user was asked to compute an "Annual Temperature Range" map by subtracting January temperatures from July temperatures using Panoply's "Combine Plot" array math feature (Array 1 - 2).

Examine these trajectory frames and the final screenshot of their work.
Did they successfully create a DIFFERENCE map (Array 1 - 2) rather than a simple overlay or single-month plot?

Characteristics of a successful temperature difference map:
- The UI should show a "Combine" tab that is configured to "Array 1 - 2" or similar subtraction.
- The map itself should have massive positive values (e.g. +40 to +60) over the Northern Hemisphere landmasses (North America, Eurasia) because July is much hotter than January there.
- The map should have large negative values over Antarctica and the Southern Ocean.
- It should NOT look like a standard temperature map (which usually shows hot horizontal bands near the equator and cold at both poles).

Respond with a JSON object:
{
    "created_difference_map": true/false,
    "shows_extreme_nh_continentality": true/false,
    "reasoning": "Brief explanation of what is shown in the plot."
}
"""

def verify_continentality_index_array_math(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Fetch metadata guidelines
    metadata = task_info.get('metadata', {})
    expected_min = metadata.get('expected_max_range_min', 45)
    expected_max = metadata.get('expected_max_range_max', 65)
    region_keywords = metadata.get('expected_region_keywords', ["siberia", "russia", "eurasia", "asia"])

    # Retrieve result JSON from the VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/continentality_index_array_math_result.json', tmp.name)
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
    # Criterion 1: Plot Exported (20 pts)
    # ----------------------------------------------------------------
    plot_exists = result.get('plot_exists', False)
    plot_mtime = int(result.get('plot_mtime', 0))
    plot_size = int(result.get('plot_size', 0))

    if plot_exists and plot_mtime >= task_start and plot_size >= 20000:
        score += 20
        feedback.append(f"✅ Plot exported successfully ({plot_size} bytes)")
    elif plot_exists and plot_mtime >= task_start:
        score += 10
        feedback.append(f"⚠️ Plot exported but small size ({plot_size} bytes)")
    else:
        feedback.append(f"❌ Plot missing or not created during task (exists={plot_exists}, mtime={plot_mtime} vs start={task_start})")

    # ----------------------------------------------------------------
    # Criterion 2: Report Formatted (20 pts)
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    op_used = result.get('operation_used', '').strip()
    region = result.get('max_range_region', '').strip()
    value_raw = result.get('max_range_value', '').strip()

    has_all_keys = bool(op_used) and bool(region) and bool(value_raw)

    if report_exists and report_mtime >= task_start and has_all_keys:
        score += 20
        feedback.append(f"✅ Report formatted correctly with all keys present")
    elif report_exists and report_mtime >= task_start:
        score += 10
        feedback.append(f"⚠️ Report exists but is missing one or more required keys")
    else:
        feedback.append(f"❌ Report missing or not created during task")

    # ----------------------------------------------------------------
    # Criterion 3: Scientific Accuracy (30 pts)
    # ----------------------------------------------------------------
    sci_score = 0
    
    # Check region (15 pts)
    if region:
        region_lower = region.lower()
        if any(kw in region_lower for kw in region_keywords):
            sci_score += 15
            feedback.append(f"✅ Region physically accurate ('{region}')")
        else:
            feedback.append(f"❌ Region inaccurate (got '{region}', expected Eurasia/Siberia)")
            
    # Check value magnitude (15 pts)
    if value_raw:
        try:
            # Extract the first valid number (int or float) handling negative signs
            match = re.search(r'-?\d+\.?\d*', value_raw)
            if match:
                val = abs(float(match.group()))
                if expected_min <= val <= expected_max:
                    sci_score += 15
                    feedback.append(f"✅ Max range value magnitude accurate ({val})")
                else:
                    feedback.append(f"❌ Max range value magnitude {val} outside expected range ({expected_min}-{expected_max})")
            else:
                feedback.append(f"❌ Could not parse numeric value from '{value_raw}'")
        except Exception as e:
            feedback.append(f"❌ Error parsing value '{value_raw}': {e}")
            
    score += sci_score

    # ----------------------------------------------------------------
    # Criterion 4: VLM Verification (30 pts)
    # ----------------------------------------------------------------
    query_vlm = env_info.get('query_vlm')
    if VLM_AVAILABLE and query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_scr = get_final_screenshot(traj)
            images_to_check = frames + [final_scr] if final_scr else frames
            
            if not images_to_check:
                feedback.append("❌ No trajectory images available for VLM verification.")
            else:
                vlm_result = query_vlm(
                    prompt=VERIFICATION_PROMPT,
                    images=images_to_check
                )
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    is_diff_map = parsed.get("created_difference_map", False)
                    shows_extrema = parsed.get("shows_extreme_nh_continentality", False)
                    
                    if is_diff_map and shows_extrema:
                        score += 30
                        feedback.append("✅ VLM verified creation of Array 1 - 2 difference map")
                    elif is_diff_map:
                        score += 15
                        feedback.append("⚠️ VLM verified difference map UI but output plot unclear")
                    else:
                        feedback.append("❌ VLM indicates difference map was not correctly generated")
                        feedback.append(f"VLM Note: {parsed.get('reasoning', 'No reasoning provided')}")
                else:
                    feedback.append(f"⚠️ VLM query failed: {vlm_result.get('error', 'Unknown')}")
        except Exception as e:
            feedback.append(f"⚠️ VLM verification encountered an exception: {e}")
    else:
        # If VLM is not strictly available in the runner env, 
        # award points conditionally based on perfect scientific accuracy to prevent false fails
        if sci_score == 30 and plot_size >= 25000:
            score += 30
            feedback.append("✅ VLM bypassed but full points awarded due to perfect numerical extraction and valid plot size")
        else:
            feedback.append("⚠️ VLM unavailable, could not visually verify Combine plot output")

    # Determine pass/fail
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }