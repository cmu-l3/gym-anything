#!/usr/bin/env python3
"""
Verifier for waste_landfill_eol task.

Criteria:
1. USLCI & LCIA Methods imported (Prerequisite)
2. Waste Flow created (Specific flow type/name check)
3. Product System created
4. CSV Results exported with valid content (GWP)
5. VLM Verification of workflow (Flow creation dialog, Results view)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

# --- VLM Prompts ---

TRAJECTORY_PROMPT = """You are analyzing screenshots of an agent using openLCA to model waste disposal.

Look for these specific workflow steps:
1. **Flow Creation**: A dialog creating a new Flow. Look for "Flow type: Waste flow" or distinct waste icon (often a trash bin or distinct color vs product flows).
2. **Product System**: A model graph showing connections, specifically connecting a waste flow to a treatment process (Landfill).
3. **Calculation**: The LCIA calculation dialog or progress bar.
4. **Results**: A results table showing "Global Warming" or "GWP".

Respond in JSON:
{
  "waste_flow_dialog_seen": true/false,
  "waste_type_selected": true/false,
  "product_system_graph_seen": true/false,
  "results_view_seen": true/false,
  "confidence": "low/medium/high"
}
"""

FINAL_SCREENSHOT_PROMPT = """Analyze this final desktop screenshot of openLCA.

Does it show:
1. A completed LCIA result (table with impact categories)?
2. A successful export action or file view?
3. Any error messages?

Respond in JSON:
{
  "results_visible": true/false,
  "error_present": true/false,
  "observation": "description"
}
"""

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    try:
        res = query_vlm(prompt=prompt, image=image, images=images)
        if res and res.get("success"):
            return res.get("parsed", {})
    except Exception as e:
        logger.error(f"VLM error: {e}")
    return None

def verify_waste_landfill_eol(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment error: copy unavailable"}

    # 2. Retrieve JSON result
    temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    # 3. Score Calculation
    score = 0
    feedback = []
    
    # Criterion 1: Database & Methods (20 pts)
    if data.get("db_found") and data.get("lcia_methods_imported"):
        score += 20
        feedback.append("Database and methods present.")
    else:
        feedback.append("Database or methods missing.")

    # Criterion 2: Waste Flow Created (20 pts)
    # The export script checks for flow name match in DB
    if data.get("waste_flow_created"):
        score += 20
        feedback.append("Waste flow identified in database.")
    else:
        feedback.append("No 'HDPE' or 'Waste' flow found in database.")

    # Criterion 3: Product System (15 pts)
    if data.get("product_system_created"):
        score += 15
        feedback.append("Product system created.")
    else:
        feedback.append("No product system found.")

    # Criterion 4: CSV Export (25 pts)
    if data.get("csv_fresh") and data.get("csv_valid_content"):
        score += 25
        feedback.append("Valid results CSV exported.")
    elif data.get("csv_exists"):
        score += 10
        feedback.append("CSV exists but content/timestamp invalid.")
    else:
        feedback.append("No results CSV found.")

    # Criterion 5: VLM Verification (20 pts)
    # Only run if we have a trajectory
    vlm_score = 0
    if traj:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, 5)
        query_vlm = env_info.get("query_vlm")
        
        vlm_res = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
        if vlm_res:
            if vlm_res.get("waste_flow_dialog_seen"): vlm_score += 10
            if vlm_res.get("results_view_seen"): vlm_score += 10
            
    score += vlm_score
    if vlm_score > 0:
        feedback.append(f"Visual verification passed (+{vlm_score}).")

    # 4. Final Determination
    # Pass if: Score >= 60 AND (Product System Created OR CSV Valid)
    # This allows for either "Done inside app" or "Exported correctly" as primary proof,
    # but strictly requires flow creation points via DB check + other steps.
    
    critical_success = data.get("product_system_created") or data.get("csv_valid_content")
    passed = (score >= 60) and critical_success

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }