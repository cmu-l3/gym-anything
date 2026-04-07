#!/usr/bin/env python3
"""
Verifier for Circular Economy Closed-Loop task.

Criteria:
1. File Verification (30 pts):
   - CSV result exists, created during task, contains GWP data.
2. Database Verification (40 pts):
   - Processes created (Manufacturing, Use, Recycling).
   - Flows created (rPET, Scrap).
   - Product System exists.
3. VLM Verification (30 pts):
   - Validates the visual structure of the Model Graph (loop) or the Process Editor (inputs).

Pass Threshold: 60/100
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

# ── VLM Prompts ─────────────────────────────────────────────────────────────

TRAJECTORY_PROMPT = """You are analyzing screenshots of an agent modeling a circular economy in openLCA.

Expected Workflow:
1. Creating Flows: Agent creating 'rPET Flake' or 'Scrap Bottle'.
2. Creating Processes: Agent editing 'Bottle Manufacturing', 'Recycling', etc.
3. Linking: Agent adding inputs/outputs to connect the loop (e.g., Recycling output -> Manufacturing input).
4. Model Graph: Viewing a Product System graph showing connected nodes.
5. Calculation: Running LCIA and viewing results.

Assess:
- FLOWS_CREATED: Did the agent create custom flows?
- PROCESSES_DEFINED: Did the agent define manufacturing/recycling processes?
- LOOP_VISUALIZED: Was a model graph visible showing connections?
- RESULTS_EXPORTED: Did the agent export data?

Return JSON:
{
  "flows_created": true/false,
  "processes_defined": true/false,
  "loop_visualized": true/false,
  "results_exported": true/false,
  "confidence": "low"/"medium"/"high",
  "observations": "brief summary"
}"""

FINAL_STATE_PROMPT = """Analyze the final screenshot of the openLCA task.

Look for:
1. A Result View showing "Global Warming" or "GWP" values.
2. A Product System Graph showing a circular or multi-step chain.
3. A Process Editor showing inputs of both "PET" (Virgin) and "rPET" (Recycled).

Return JSON:
{
  "results_visible": true/false,
  "graph_visible": true/false,
  "mixed_inputs_visible": true/false,
  "confidence": "low"/"medium"/"high"
}"""

# ── Helper Functions ────────────────────────────────────────────────────────

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

def verify_circular_economy(traj, env_info, task_info):
    """Verify circular economy task completion."""
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    # 1. Load JSON Result
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

    # 2. File Verification (30 pts)
    if result.get('result_file_exists') and result.get('file_created_during_task'):
        score += 15
        feedback.append("Result file created.")
        
        if result.get('content_has_gwp'):
            score += 15
            feedback.append("Result contains GWP data.")
        else:
            feedback.append("Result missing GWP keywords.")
    else:
        feedback.append("No result file created.")

    # 3. Database Verification (40 pts)
    # Check Product System
    if result.get('product_system_count', 0) >= 1:
        score += 10
        feedback.append("Product System created.")
    
    # Check Process Names
    proc_dump = result.get('process_names_dump', "").lower()
    required_procs = ["manufactur", "recycl", "use"]
    procs_found = sum(1 for p in required_procs if p in proc_dump)
    
    if procs_found >= 3:
        score += 20
        feedback.append("All 3 required processes found (Mfg, Use, Recycle).")
    elif procs_found > 0:
        score += 10
        feedback.append(f"Some processes found ({procs_found}/3).")
        
    # Check Flow Names
    flow_dump = result.get('flow_names_dump', "").lower()
    if "rpet" in flow_dump or "scrap" in flow_dump:
        score += 10
        feedback.append("Custom flows (rPET/Scrap) found.")

    # 4. VLM Verification (30 pts)
    # Trajectory Analysis
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    vlm_traj = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
    vlm_final = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final_img)
    
    vlm_score = 0
    if vlm_traj:
        if vlm_traj.get('processes_defined'): vlm_score += 5
        if vlm_traj.get('loop_visualized'): vlm_score += 10
    
    if vlm_final:
        if vlm_final.get('results_visible'): vlm_score += 10
        if vlm_final.get('graph_visible') or vlm_final.get('mixed_inputs_visible'): vlm_score += 5
        
    score += vlm_score
    if vlm_score > 0:
        feedback.append(f"Visual verification passed ({vlm_score} pts).")

    # Final tally
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "vlm_analysis": vlm_traj,
            "db_structure": {
                "procs": procs_found,
                "flows": "rpet" in flow_dump
            }
        }
    }