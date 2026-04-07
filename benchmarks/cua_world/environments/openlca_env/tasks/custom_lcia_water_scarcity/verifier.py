#!/usr/bin/env python3
"""
Verifier for Custom LCIA Water Scarcity task.

The agent must:
1. Create a custom LCIA method ("Regional Water Scarcity").
2. Define an impact category ("Water Scarcity Potential").
3. Assign characterization factors to >= 3 flows.
4. Run a calculation and export results.

Scoring (100 pts):
- Method Created (15 pts)
- Category Defined correctly (15 pts)
- Characterization Factors >= 3 (20 pts)
- Product System/Calculation run (10 pts implied by result file)
- Result CSV exists and valid (20 pts)
- VLM Verification (20 pts)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

# ── VLM Prompts ───────────────────────────────────────────────────────────────

TRAJECTORY_PROMPT = """You are analyzing screenshots of an agent creating a custom Life Cycle Impact Assessment (LCIA) method in openLCA.

Expected workflow:
1. Navigation: Opening "Impact assessment methods" -> New method.
2. Method Editor: Naming it "Regional Water Scarcity" (or similar).
3. Category Editor: Creating "Water Scarcity Potential" category.
4. Factors: Searching for water flows (e.g., "Water, fresh") and assigning numbers.
5. Calculation: Running a product system with this new method.

Assess:
- METHOD_EDITOR_OPEN: Was the LCIA method editor visible?
- FACTORS_ADDED: Did you see the agent adding flows/factors (searching for water)?
- CALCULATION_RUN: Was a calculation dialog visible where the custom method was selected?
- MEANINGFUL_PROGRESSION: Does the sequence show actual editing work?

Return JSON:
{
  "method_editor_open": true/false,
  "factors_added": true/false,
  "calculation_run": true/false,
  "meaningful_progression": true/false,
  "confidence": "low"/"medium"/"high",
  "observations": "brief description"
}"""

FINAL_FRAME_PROMPT = """Analyze the final screenshot of the openLCA task.

Expected final state:
- A CSV file showing results, OR
- The openLCA "LCIA Results" view showing "Water Scarcity Potential".

Check:
- RESULTS_VISIBLE: Are impact results visible?
- CUSTOM_CATEGORY: Is "Water Scarcity" or "Regional Water" visible in the results?
- NUMERIC_VALUES: Are there calculated numbers?

Return JSON:
{
  "results_visible": true/false,
  "custom_category": true/false,
  "numeric_values": true/false,
  "confidence": "low"/"medium"/"high"
}"""

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result and result.get("success"):
            return result.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM error: {e}")
    return None

def verify_custom_lcia_water_scarcity(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result JSON
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    score = 0
    feedback = []

    # 1. Database Verification (50 pts total)
    if result.get('method_found'):
        score += 15
        feedback.append("Custom LCIA method created.")
    else:
        feedback.append("Custom LCIA method NOT found in database.")

    if result.get('category_found'):
        score += 15
        feedback.append("Impact category 'Water Scarcity' defined.")
    
    factors = result.get('factors_count', 0)
    try:
        factors = int(factors)
    except:
        factors = 0
        
    if factors >= 3:
        score += 20
        feedback.append(f"Characterization factors defined ({factors} flows).")
    elif factors > 0:
        score += 10
        feedback.append(f"Insufficient characterization factors ({factors}/3).")
    else:
        feedback.append("No characterization factors found.")

    # 2. Result File Verification (30 pts total)
    if result.get('result_file_exists') and result.get('result_file_created_during_task'):
        score += 10
        if result.get('result_has_content') and result.get('result_has_keyword'):
            score += 20
            feedback.append("Result CSV exported with correct content.")
        elif result.get('result_has_content'):
            score += 10
            feedback.append("Result CSV exists but missing specific keywords.")
        else:
            feedback.append("Result CSV exists but appears empty.")
    else:
        feedback.append("No new result CSV found.")

    # 3. VLM Verification (20 pts total)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        # Trajectory check
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, 4)
        traj_res = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
        
        if traj_res and traj_res.get('method_editor_open'):
            score += 10
            feedback.append("VLM verified method editing workflow.")
        
        # Final frame check
        final_img = get_final_screenshot(traj)
        final_res = _vlm_query(query_vlm, FINAL_FRAME_PROMPT, image=final_img)
        
        if final_res and (final_res.get('results_visible') or final_res.get('custom_category')):
            score += 10
            feedback.append("VLM verified final results.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }