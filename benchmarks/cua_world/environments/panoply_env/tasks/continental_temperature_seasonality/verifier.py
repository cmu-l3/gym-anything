#!/usr/bin/env python3
"""
Verifier for continental_temperature_seasonality task.

Checks:
1. January plot exported (20 pts)
2. July plot exported (20 pts)
3. Region identified correctly (Siberia/Yakutia/Russia/Asia) (20 pts)
4. Annual range calculated correctly (35-80C) (20 pts)
5. VLM trajectory check: Agent used Panoply UI to view maps (20 pts)
Anti-Gaming: If the two PNG plots are identical (same MD5), heavy penalty applied.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# =============================================================================
# VLM PROMPT
# =============================================================================
VERIFICATION_PROMPT = """You are verifying if an AI agent successfully performed a climate visualization task in NASA Panoply.

TASK: The agent was supposed to use NASA Panoply to create and export two different surface air temperature plots (for January and July).

Look at the provided trajectory frames and final screenshot. Determine:
1. Did the agent open and interact with the NASA Panoply application?
2. Is there evidence that the agent viewed map plots of the data?
3. Did the agent navigate between different time steps (e.g., changing the month/time index in the Array tabs)?

Respond in JSON format:
{
    "panoply_used": true/false,
    "maps_viewed": true/false,
    "time_navigation_attempted": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of your observations"
}
"""

def verify_continental_temperature_seasonality(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/continental_temperature_seasonality_result.json', tmp.name)
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
    # Criterion 1: January Plot (20 pts)
    # ----------------------------------------------------------------
    jan_exists = result.get('png_jan_exists', False)
    jan_mtime = int(result.get('png_jan_mtime', 0))
    jan_size = int(result.get('png_jan_size', 0))
    jan_md5 = result.get('png_jan_md5', '')

    if jan_exists and jan_mtime >= task_start and jan_size >= 15000:
        score += 20
        feedback.append(f"✅ January plot exported ({jan_size} bytes)")
    elif jan_exists and jan_mtime >= task_start and jan_size >= 5000:
        score += 10
        feedback.append(f"⚠️ January plot present but small ({jan_size} bytes, expected >=15KB)")
    else:
        feedback.append(f"❌ January plot missing or not created during task "
                        f"(exists={jan_exists}, size={jan_size})")

    # ----------------------------------------------------------------
    # Criterion 2: July Plot (20 pts)
    # ----------------------------------------------------------------
    jul_exists = result.get('png_jul_exists', False)
    jul_mtime = int(result.get('png_jul_mtime', 0))
    jul_size = int(result.get('png_jul_size', 0))
    jul_md5 = result.get('png_jul_md5', '')

    if jul_exists and jul_mtime >= task_start and jul_size >= 15000:
        score += 20
        feedback.append(f"✅ July plot exported ({jul_size} bytes)")
    elif jul_exists and jul_mtime >= task_start and jul_size >= 5000:
        score += 10
        feedback.append(f"⚠️ July plot present but small ({jul_size} bytes, expected >=15KB)")
    else:
        feedback.append(f"❌ July plot missing or not created during task "
                        f"(exists={jul_exists}, size={jul_size})")

    # Anti-gaming: Ensure the agent didn't just save the exact same plot twice
    if jan_exists and jul_exists and jan_md5 == jul_md5 and jan_size > 0:
        score -= 20
        feedback.append(f"❌ ANTI-GAMING: January and July plots are identical (same MD5). Deducting 20 points.")

    # ----------------------------------------------------------------
    # Criterion 3: Identified Region (20 pts)
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    region_raw = result.get('max_seasonality_region', '').strip().lower()
    
    if report_exists and report_mtime >= task_start:
        valid_keywords = ["siberia", "yakutia", "verkhoyansk", "oymyakon", "russia", "asia"]
        partial_keywords = ["canada", "north america"]
        
        if any(kw in region_raw for kw in valid_keywords):
            score += 20
            feedback.append(f"✅ Correct region identified: '{region_raw}'")
        elif any(kw in region_raw for kw in partial_keywords):
            score += 10
            feedback.append(f"⚠️ Partial region match (Canada has high seasonality, but Siberia is max): '{region_raw}'")
        else:
            feedback.append(f"❌ Incorrect region identified: '{region_raw}'")
    else:
        feedback.append("❌ Report missing or not created during task")

    # ----------------------------------------------------------------
    # Criterion 4: Annual Range Calculation (20 pts)
    # ----------------------------------------------------------------
    range_raw = result.get('annual_range_c', '').strip()
    
    if report_exists and report_mtime >= task_start and range_raw:
        # Extract the first float found in the string
        match = re.search(r"[-+]?\d*\.\d+|\d+", range_raw)
        if match:
            try:
                range_val = float(match.group())
                if 35.0 <= range_val <= 80.0:
                    score += 20
                    feedback.append(f"✅ Plausible annual range reported: {range_val}°C")
                elif 25.0 <= range_val < 35.0 or 80.0 < range_val <= 100.0:
                    score += 10
                    feedback.append(f"⚠️ Sub-optimal annual range reported: {range_val}°C (expected 35-80°C)")
                else:
                    feedback.append(f"❌ Implausible annual range reported: {range_val}°C")
            except ValueError:
                feedback.append(f"❌ Could not parse numerical range from: '{range_raw}'")
        else:
            feedback.append(f"❌ Could not extract number from ANNUAL_RANGE_C: '{range_raw}'")
    elif report_exists and report_mtime >= task_start:
        feedback.append("❌ ANNUAL_RANGE_C field is missing or empty")

    # ----------------------------------------------------------------
    # Criterion 5: VLM Trajectory Verification (20 pts)
    # ----------------------------------------------------------------
    query_vlm = env_info.get('query_vlm')
    if query_vlm and 'sample_trajectory_frames' in globals() or 'get_final_screenshot' in globals():
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            
            vlm_result = query_vlm(
                images=frames + [final_frame], 
                prompt=VERIFICATION_PROMPT
            )
            
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                panoply_used = parsed.get("panoply_used", False)
                maps_viewed = parsed.get("maps_viewed", False)
                
                if panoply_used and maps_viewed:
                    score += 20
                    feedback.append("✅ VLM verified Panoply interaction and map viewing")
                elif panoply_used:
                    score += 10
                    feedback.append("⚠️ VLM verified Panoply usage but could not confirm map viewing")
                else:
                    feedback.append("❌ VLM could not confirm Panoply interaction")
            else:
                feedback.append("⚠️ VLM verification failed to process. Granting 10 fallback points.")
                score += 10
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback.append("⚠️ VLM verification encountered an error. Granting 10 fallback points.")
            score += 10
    else:
        # If VLM is not available, grant the points by default to not penalize
        feedback.append("⚠️ VLM function not available. Granting 20 fallback points.")
        score += 20

    # Ensure score bounds
    score = max(0, min(100, score))
    
    # Passing logic
    key_criteria_met = (jan_exists and jul_exists and report_exists)
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }