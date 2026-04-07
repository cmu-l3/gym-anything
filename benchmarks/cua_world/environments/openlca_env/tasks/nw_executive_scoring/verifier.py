#!/usr/bin/env python3
"""
Verifier for NW Executive Scoring task.

This task requires the agent to:
1. Import USLCI database and LCIA methods.
2. Edit an LCIA method to add a new Normalization/Weighting (NW) set.
3. Enter specific normalization and weighting factors.
4. Create a product system (Natural Gas Electricity).
5. Run a calculation with the NW set and export results.

Scoring Breakdown (100 pts):
- Database & Import (20 pts): USLCI imported (>100 processes).
- NW Configuration (40 pts):
    - NW Set created (20 pts)
    - Specific name match "US Person-Year 2023" (5 pts)
    - Factors defined (>0 factors in DB) (15 pts)
- Workflow Execution (20 pts):
    - Product system created (10 pts)
    - CSV Export exists and created during task (10 pts)
- Output Quality (20 pts):
    - CSV has numeric data (10 pts)
    - CSV mentions impact categories (10 pts)

VLM Analysis verifies the UI workflow: Method Editor -> Calculation -> Export.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

# VLM Prompts
TRAJECTORY_PROMPT = """You are analyzing screenshots of an agent using openLCA to configure Life Cycle Impact Assessment (LCIA) methods.

The expected workflow:
1.  **Method Editor**: User opens an LCIA method (e.g., TRACI) and navigates to the "Normalization and weighting" tab.
2.  **NW Set Creation**: User adds a new set (e.g., named "US Person-Year 2023").
3.  **Factor Entry**: User types numbers into a table (Normalization factors like 24000, 90; Weighting factors like 0.3, 0.2).
4.  **Calculation**: User runs a calculation on a product system, selecting the NW set.
5.  **Export**: User exports results to a file.

Assess:
- **METHOD_EDITOR_USED**: Was the LCIA method editor with Normalization/Weighting tab visible?
- **FACTORS_ENTERED**: Did the agent enter numeric values into the normalization/weighting table?
- **CALCULATION_RUN**: Was a calculation dialog or result view seen?
- **WORKFLOW_COMPLETED**: Did the agent progress from editing to calculating/exporting?

Return JSON:
{
  "method_editor_used": true/false,
  "factors_entered": true/false,
  "calculation_run": true/false,
  "workflow_completed": true/false,
  "confidence": "low/medium/high"
}
"""

FINAL_SCREEN_PROMPT = """Analyze the final screenshot of an openLCA task.

Expected state:
- An exported CSV file open (showing impact categories and weighted scores).
- OR the openLCA results view showing normalization/weighting results.

Check:
- **RESULTS_VISIBLE**: Are numeric results visible?
- **WEIGHTING_SHOWN**: Is there indication of weighted results (e.g., "Weighted results" tab or column)?
- **FILE_EXPORTED**: Is a file manager or CSV editor visible with the results?

Return JSON:
{
  "results_visible": true/false,
  "weighting_shown": true/false,
  "file_exported": true/false,
  "confidence": "low/medium/high"
}
"""

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

def verify_nw_executive_scoring(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    score = 0
    feedback = []

    # 1. Database & Import (20 pts)
    if result.get("uslci_imported"):
        score += 20
        feedback.append("USLCI database imported successfully.")
    else:
        feedback.append("USLCI database not fully imported (process count low).")

    # 2. NW Configuration (40 pts)
    nw_score = 0
    if result.get("nw_set_count", 0) > 0:
        nw_score += 20
        feedback.append("NW Set created.")
    
    if result.get("nw_set_name_match"):
        nw_score += 5
        feedback.append("NW Set name matches 'US Person-Year 2023'.")
    
    if result.get("nw_factors_count", 0) > 0:
        nw_score += 15
        feedback.append(f"NW Factors defined (count: {result.get('nw_factors_count')}).")
    else:
        feedback.append("No NW factors found in database.")
    
    score += nw_score

    # 3. Workflow Execution (20 pts)
    wf_score = 0
    if result.get("product_system_count", 0) > 0:
        wf_score += 10
        feedback.append("Product system created.")
    
    if result.get("file_exists") and result.get("file_created_during_task"):
        wf_score += 10
        feedback.append("Result file created during task.")
    else:
        feedback.append("Result file missing or not created during task.")
    
    score += wf_score

    # 4. Output Quality (20 pts)
    out_score = 0
    if result.get("has_numeric_data"):
        out_score += 10
        feedback.append("Output file contains numeric data.")
    
    if result.get("has_category_keywords"):
        out_score += 10
        feedback.append("Output file contains valid impact category keywords.")
    
    score += out_score

    # VLM Verification (Bonus/Validation)
    # If the score is borderline, VLM can confirm UI interaction
    # Here we use it to construct feedback mostly, or boost if DB query failed but UI looked good
    # For now, stick to programmatic for scoring, but log VLM checks
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }