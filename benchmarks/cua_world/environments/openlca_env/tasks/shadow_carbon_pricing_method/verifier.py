#!/usr/bin/env python3
"""
Verifier for Shadow Carbon Pricing Method task.

Scoring Criteria (100 points total):
1. Method Creation (DB Check):
   - Method 'Shadow Carbon Price 2026' exists: 20 pts
   - Category 'Carbon Liability' exists: 10 pts
2. Characterization Factors (DB Check):
   - CO2 factor ~0.10 exists: 10 pts
   - Methane factor ~2.80 exists: 10 pts
   - NOx factor ~0.50 exists: 10 pts
3. Execution & Result (File Check):
   - Output CSV exists and created during task: 10 pts
   - Output contains 'Carbon Liability' header: 10 pts
   - Output contains non-zero numeric values: 10 pts
4. Visual Verification (VLM):
   - Trajectory shows interaction with Method Editor or Results: 10 pts

Pass Threshold: 60 points (Must have at least partial method created + factors or file output)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

TRAJECTORY_PROMPT = """You are analyzing screenshots of an agent using openLCA.
The goal is to create a custom Impact Assessment Method.

Look for these specific screens:
1. **Impact Method Editor**: A form where the user enters "Shadow Carbon Price 2026".
2. **Impact Category Editor**: A tab (usually "Impact categories") where "Carbon Liability" is added.
3. **Characterization Factors**: A table where the user adds flows (Carbon dioxide, Methane) and types numbers (0.1, 2.8).
4. **Results View**: A final calculation result showing "Carbon Liability" in the table.

Assess:
- METHOD_EDITOR_OPEN: Did the agent open the method editor?
- FACTORS_ENTERED: Did you see numbers like 0.1, 2.8, or 0.5 being entered?
- RESULTS_CALCULATED: Did a result window appear at the end?

Return JSON:
{
  "method_editor_open": true/false,
  "factors_entered": true/false,
  "results_calculated": true/false,
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

def verify_shadow_carbon_pricing(traj, env_info, task_info):
    """Verify the creation of the custom LCIA method and calculation results."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load programmatic result
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Task result file not found."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    score = 0
    feedback = []

    # 1. Method Structure (30 pts)
    if result.get("method_exists"):
        score += 20
        feedback.append("Method 'Shadow Carbon Price 2026' created.")
    else:
        feedback.append("Method 'Shadow Carbon Price 2026' NOT found in database.")

    if result.get("category_exists"):
        score += 10
        feedback.append("Category 'Carbon Liability' created.")
    
    # 2. Factors (30 pts)
    factors_found = 0
    if result.get("factor_co2_ok"):
        score += 10
        factors_found += 1
        feedback.append("CO2 factor (0.10) verified.")
    if result.get("factor_ch4_ok"):
        score += 10
        factors_found += 1
        feedback.append("Methane factor (2.80) verified.")
    if result.get("factor_nox_ok"):
        score += 10
        factors_found += 1
        feedback.append("NOx factor (0.50) verified.")
    
    if factors_found == 0 and result.get("method_exists"):
        feedback.append("No correct characterization factors found.")

    # 3. Output File (30 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 10
        feedback.append("Output file created.")
        
        if result.get("has_category_name"):
            score += 10
            feedback.append("Output contains correct category name.")
        
        if result.get("has_numeric_values"):
            score += 10
            feedback.append("Output contains valid numeric results.")
    else:
        feedback.append("No output file generated.")

    # 4. VLM Verification (10 pts)
    # Only run if we are missing points, to confirm effort
    if score < 100:
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=5)
            vlm_res = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
            if vlm_res:
                if vlm_res.get("method_editor_open") or vlm_res.get("factors_entered"):
                    score = min(100, score + 10)
                    feedback.append("Visual evidence of method editing found.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }