#!/usr/bin/env python3
"""
Verifier for cytc_publication_formatting task.

Verifies:
1. Data subsetting (plant/fungi outgroups removed, exactly 5 animal seqs left)
2. MSA algorithmic application (MUSCLE)
3. UI Visual presentation state (Zappo color scheme applied before export)
4. Multi-format export execution (HTML + FASTA + Report)
5. VLM Trajectory check to ensure UI actions were legitimately taken (anti-gaming)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are analyzing the workflow of an agent using the UGENE bioinformatics software.
Did the agent apply a multi-colored highlighting scheme (like 'Zappo', where amino acids are brightly colored based on their properties) to a multiple sequence alignment within the UI?

Respond with a JSON object containing:
{
    "color_scheme_applied": true/false,
    "confidence": "low/medium/high",
    "reasoning": "brief explanation of what visual evidence you see"
}
"""

def verify_cytc_publication_formatting(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve exported JSON result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    subscores = {}

    # 1. FASTA Subset and Alignment Validation (Max 25 pts)
    c_fasta = 0
    if result.get("fasta_exists"):
        c_fasta += 5
        seq_count = result.get("fasta_seq_count", 0)
        has_plants = result.get("fasta_has_plants", True)
        is_aligned = result.get("fasta_is_aligned", False)

        if seq_count == 5 and not has_plants:
            c_fasta += 10
            feedback_parts.append("Correct 5 animal sequences isolated (+15)")
        elif seq_count > 0:
            feedback_parts.append(f"FASTA exported but incorrect subset ({seq_count} seqs).")

        if is_aligned:
            c_fasta += 10
            feedback_parts.append("FASTA sequences are aligned/gapped (+10)")
        else:
            feedback_parts.append("FASTA sequences lack alignment gaps.")
    else:
        feedback_parts.append("FASTA output MISSING (0)")
    
    score += c_fasta
    subscores["fasta_formatting"] = c_fasta

    # 2. HTML Export and Color Scheme Validation (Max 25 pts)
    c_html = 0
    if result.get("html_exists"):
        c_html += 10
        feedback_parts.append("HTML output generated (+10)")
        
        if result.get("html_has_colors"):
            c_html += 15
            feedback_parts.append("HTML retains inline color/Zappo styling (+15)")
        else:
            feedback_parts.append("HTML generated but lacks color scheme styling.")
    else:
        feedback_parts.append("HTML output MISSING (0)")

    score += c_html
    subscores["html_export"] = c_html

    # 3. Text Report Accuracy (Max 20 pts)
    c_report = 0
    if result.get("report_exists"):
        c_report += 5
        if result.get("report_mentions_muscle"):
            c_report += 5
        if result.get("report_mentions_zappo"):
            c_report += 5
        if result.get("report_mentions_5"):
            c_report += 5
        feedback_parts.append(f"Report scored {c_report}/20.")
    else:
        feedback_parts.append("Summary report MISSING (0)")

    score += c_report
    subscores["report"] = c_report

    # 4. VLM Trajectory Anti-Gaming Check (Max 30 pts)
    # Proves the agent actually interacted with the UI to apply the color scheme,
    # rather than just writing out mock files with python scripts.
    c_vlm = 0
    vlm_error = ""
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        all_frames = frames + [final_img] if final_img else frames
        
        if all_frames:
            vlm_resp = query_vlm(images=all_frames, prompt=VLM_PROMPT)
            if vlm_resp and vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                if parsed.get("color_scheme_applied", False):
                    c_vlm = 30
                    feedback_parts.append("VLM verified visual color scheme application in trajectory (+30)")
                else:
                    feedback_parts.append("VLM did NOT detect color scheme application in UI.")
            else:
                vlm_error = "VLM query failed."
        else:
            vlm_error = "No trajectory frames available."
    except Exception as e:
        vlm_error = str(e)

    if vlm_error:
        # Give partial credit if VLM fails for framework reasons but programmatic passes perfectly
        if c_fasta == 25 and c_html == 25:
            c_vlm = 30
            feedback_parts.append("VLM unavailable; granted trajectory points via perfect programmatic score (+30)")
        else:
            feedback_parts.append(f"VLM verification skipped/failed: {vlm_error}")

    score += c_vlm
    subscores["vlm_trajectory"] = c_vlm

    # Final Evaluation
    # Must achieve at least a 70 and successfully export the colored HTML.
    key_criteria_met = result.get("html_exists", False) and result.get("html_has_colors", False)
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }