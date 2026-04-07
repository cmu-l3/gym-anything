#!/usr/bin/env python3
"""
Verifier for Regionalized Supply Chain Configuration task.

Verifies:
1. Product System creation.
2. Specific Default Provider links in the database:
   - "Corrugated board boxes" -> Electricity WECC
   - "Linerboard" -> Electricity SERC
3. CSV output generation.
4. Visual workflow (VLM).
"""

import json
import os
import tempfile
import logging
import re

logger = logging.getLogger(__name__)

# ── VLM Prompts ─────────────────────────────────────────────────────────────

TRAJECTORY_PROMPT = """You are verifying an agent configuring a supply chain in openLCA.
The goal is to set specific regional electricity providers for two processes.

Look for these steps:
1. Process Editor: Viewing a process (likely "Corrugated board boxes" or "Linerboard").
2. Inputs/Exchanges Tab: Editing the "Inputs" or "Exchanges" list.
3. Provider Selection: Clicking a "Default provider" column or selecting a specific provider from a list (e.g., looking for "WECC" or "SERC").
4. Product System: Creating or viewing a product system model graph.

JSON Output:
{
  "process_editor_opened": true/false,
  "provider_selection_visible": true/false,
  "regional_terms_seen": true/false,  // Did you see "WECC", "SERC", "Western", "Southeastern"?
  "product_system_created": true/false,
  "confidence": "low/medium/high"
}
"""

FINAL_STATE_PROMPT = """Analyze the final screenshot of the openLCA task.
Success looks like:
- A "Model Graph" view showing connected nodes.
- OR a "Results" view showing impact categories (Global Warming, etc.).
- OR a CSV file opened showing results.

JSON Output:
{
  "model_graph_visible": true/false,
  "results_visible": true/false,
  "csv_open": true/false
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

def verify_regionalized_supply_chain(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # 1. Load Results
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

    # 2. Check CSV Output (10 pts)
    if result.get("output_exists") and result.get("file_created_during_task"):
        score += 10
        feedback.append("Result CSV exported.")
    else:
        feedback.append("Result CSV missing or not created during task.")

    # 3. Check Product System Creation (10 pts)
    if result.get("ps_count", 0) > 0:
        score += 10
        feedback.append("Product System created.")
    else:
        feedback.append("No Product System found in database.")

    # 4. Verify Regional Links via DB Query (60 pts)
    # The DB query output string contains rows like: "Corrugated boxes | Electricity, at grid, WECC..."
    db_output = result.get("db_query_result", "")
    
    # Normalize string for easier matching
    db_clean = re.sub(r'\s+', ' ', db_output).lower()
    
    # Check Box -> WECC Link (30 pts)
    # Looking for row where Source has "corrugated" and Provider has "wecc"
    # Matches pattern roughly: "corrugated ... wecc" in the same logical row
    # Since we flattened it, we check if the combination exists in the dump.
    # A more robust check is parsing the lines if newline preserved, but let's try regex on the block.
    
    # We'll search for the specific logical pairings
    has_box_wecc = False
    has_liner_serc = False
    
    # Split by lines if possible (the jq dump might preserve \n as literal \n)
    lines = db_output.split('\\n') 
    if len(lines) == 1: lines = db_output.split('\n')
    
    for line in lines:
        line_lower = line.lower()
        # Debug feedback
        # feedback.append(f"DB Row: {line_lower}") 
        
        if "corrugated" in line_lower and "box" in line_lower:
            if "wecc" in line_lower:
                has_box_wecc = True
        
        if "linerboard" in line_lower:
            if "serc" in line_lower:
                has_liner_serc = True

    if has_box_wecc:
        score += 30
        feedback.append("Correct: 'Corrugated boxes' linked to WECC electricity.")
    else:
        feedback.append("Failed: 'Corrugated boxes' not linked to WECC electricity.")

    if has_liner_serc:
        score += 30
        feedback.append("Correct: 'Linerboard' linked to SERC electricity.")
    else:
        feedback.append("Failed: 'Linerboard' not linked to SERC electricity.")

    # 5. VLM Verification (20 pts)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        # Trajectory check
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, 5)
        traj_res = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
        
        if traj_res:
            if traj_res.get("process_editor_opened") or traj_res.get("provider_selection_visible"):
                score += 10
                feedback.append("VLM: Process editing observed.")
            if traj_res.get("regional_terms_seen"):
                score += 5
                feedback.append("VLM: Regional selection observed.")

        # Final state check
        final_img = get_final_screenshot(traj)
        final_res = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final_img)
        if final_res and (final_res.get("model_graph_visible") or final_res.get("results_visible")):
            score += 5
            feedback.append("VLM: Final results/model visible.")

    # 6. Final Verdict
    passed = (score >= 70) and has_box_wecc # Hard requirement: at least the main box config correct
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }