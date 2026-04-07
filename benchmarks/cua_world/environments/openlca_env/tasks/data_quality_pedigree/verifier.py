#!/usr/bin/env python3
"""
Verifier for Data Quality Pedigree task.

The agent must:
1. Create a DQ System with 5 specific indicators.
2. Assign it to a Coal Electricity process.
3. Score the process and at least 5 exchanges.
4. Export a CSV report.

Verification signals:
- Programmatic (Derby DB): Check TBL_DQ_SYSTEMS, TBL_PROCESSES, TBL_EXCHANGES.
- File: CSV content check.
- VLM: Visual confirmation of DQ editor usage.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

TRAJECTORY_PROMPT = """You are analyzing screenshots of an agent using OpenLCA to manage Data Quality (DQ).

Expected workflow:
1. Creating a Data Quality System (usually under "Indicators and parameters").
2. Defining 5 indicators (Reliability, Completeness, etc.).
3. Opening a Process (Coal/Electricity).
4. Assigning the DQ System to the process.
5. Entering scores (e.g., clicking cells in the "DQ" or "Data quality" column of the Inputs/Outputs table).
6. Exporting results (CSV/Excel).

Assess:
- DQ_SYSTEM_CREATED: Did the agent work in the DQ System editor?
- INDICATORS_DEFINED: Were 5 indicators visible?
- SCORES_ENTERED: Did the agent enter scores (e.g., (1;3;2;...)) in the exchange table?
- REPORT_EXPORTED: Was a file export performed?

Return JSON:
{
  "dq_system_created": true/false,
  "indicators_defined": true/false,
  "scores_entered": true/false,
  "report_exported": true/false,
  "confidence": "low"/"medium"/"high",
  "observations": "brief description"
}"""

FINAL_FRAME_PROMPT = """Analyze the final state of the OpenLCA task.

Look for:
- A CSV or text file containing Data Quality report data.
- The OpenLCA process editor showing Data Quality scores in the input/output table.
- The Data Quality System editor.

Check:
- DQ_COLUMNS_VISIBLE: Are there columns labeled "DQ" or "Data quality" with values like (1;2;3...)?
- FILE_CONTENT_VISIBLE: Is the exported report visible?
- COMPLETION: Does the task look finished?

Return JSON:
{
  "dq_columns_visible": true/false,
  "file_content_visible": true/false,
  "completion": true/false,
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


def verify_data_quality_pedigree(traj, env_info, task_info):
    """Verify Data Quality Pedigree task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # 1. Load Result JSON
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    score = 0
    feedback = []

    # ── Programmatic Checks (70 points) ───────────────────────────────────────

    # 1. DQ System Created (15 pts)
    dq_sys_count = result.get('dq_system_count', 0)
    if dq_sys_count >= 1:
        score += 15
        feedback.append("DQ System created.")
    else:
        feedback.append("No DQ System found in database.")

    # 2. Indicators Count (10 pts)
    # Ideally should be 5 indicators per system. If count >= 5, likely correct.
    dq_ind_count = result.get('dq_indicator_count', 0)
    if dq_ind_count >= 5:
        score += 10
        feedback.append("Indicators defined correctly.")
    elif dq_ind_count > 0:
        score += 5
        feedback.append(f"Some indicators defined ({dq_ind_count}), expected 5.")
    
    # 3. Process Assigned DQ (15 pts)
    proc_dq = result.get('process_with_dq_count', 0)
    if proc_dq >= 1:
        score += 15
        feedback.append("DQ System assigned to process.")
    else:
        feedback.append("No process found with DQ System assigned.")

    # 4. Exchanges Scored (20 pts)
    exch_dq = result.get('exchanges_with_dq_count', 0)
    if exch_dq >= 5:
        score += 20
        feedback.append(f"Exchanges scored ({exch_dq} >= 5).")
    elif exch_dq > 0:
        score += 10
        feedback.append(f"Too few exchanges scored ({exch_dq} < 5).")
    else:
        feedback.append("No exchanges scored.")

    # 5. File Export (10 pts)
    if result.get('file_exists') and result.get('file_created_during_task'):
        if result.get('has_dq_keywords') and result.get('has_process_keywords'):
            score += 10
            feedback.append("Valid report file exported.")
        else:
            score += 5
            feedback.append("Report file exists but missing content keywords.")
    else:
        feedback.append("Report file not found/not created.")

    # ── VLM Checks (30 points) ────────────────────────────────────────────────

    query_vlm = env_info.get('query_vlm')
    
    # Trajectory Check
    traj_score = 0
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        vlm_res = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
        
        if vlm_res:
            if vlm_res.get("dq_system_created"): traj_score += 10
            if vlm_res.get("scores_entered"): traj_score += 10
            if vlm_res.get("report_exported") and not result.get('file_exists'): 
                # Credit visual export if file check failed (e.g. wrong path)
                traj_score += 5
    
    score += traj_score
    if traj_score > 0:
        feedback.append(f"Visual verification passed ({traj_score} pts).")

    # Final Screenshot Check (10 pts bonus/confirmation)
    final_score = 0
    if query_vlm:
        from gym_anything.vlm import get_final_screenshot
        final_img = get_final_screenshot(traj)
        if final_img:
            vlm_final = _vlm_query(query_vlm, FINAL_FRAME_PROMPT, image=final_img)
            if vlm_final and vlm_final.get("dq_columns_visible"):
                final_score += 5
            if vlm_final and vlm_final.get("file_content_visible"):
                final_score += 5
    
    # Cap score at 100
    total_score = min(100, score + final_score)

    passed = total_score >= 60 and (dq_sys_count >= 1 or proc_dq >= 1)

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " ".join(feedback)
    }