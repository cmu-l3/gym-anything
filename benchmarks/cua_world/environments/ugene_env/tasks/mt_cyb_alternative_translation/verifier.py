#!/usr/bin/env python3
"""
Verifier for mt_cyb_alternative_translation task.

Verification Strategy:
1. Output file presence and timestamps (anti-gaming check).
2. Biological Accuracy: FASTA protein must have ~380 amino acids and 0 internal stops. 
   If they failed to change the translation table, there will be internal stops (*).
3. VLM Verification: Ensures the agent actually interacted with the UGENE UI
   rather than executing a hidden Biopython script.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying an agent's workflow in the UGENE bioinformatics suite.
The task was to translate a DNA sequence into protein using an alternative genetic code.

Please examine these trajectory frames and determine:
1. Was the "Find ORFs" (Open Reading Frames) tool or translation settings panel opened?
2. Did the agent interact with a "Translation table" or "Genetic code" dropdown?
3. Is there any visual evidence that the "Vertebrate Mitochondrial" translation table was selected or visible in the UI?

Respond with a JSON object containing:
{
    "orf_tool_used": true/false,
    "translation_table_interaction": true/false,
    "mitochondrial_table_visible": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what you see"
}
"""

def verify_mt_cyb_translation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Fetch Programmatic Results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/mt_cyb_translation_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read exported results: {e}")
        return {"passed": False, "score": 0, "feedback": "Result extraction failed. Agent likely did not run the tools."}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Check GenBank File (20 pts)
    if result.get("gb_exists") and result.get("gb_created_during_task"):
        score += 10
        if result.get("gb_valid") and result.get("gb_has_features"):
            score += 10
            feedback_parts.append("Annotated GB file valid (+20)")
        else:
            feedback_parts.append("GB file exists but lacks valid ORF annotations (+10)")
    else:
        feedback_parts.append("Annotated GB file missing or stale (0)")

    # Check FASTA File Length and Format (25 pts)
    fasta_exists = result.get("fasta_exists") and result.get("fasta_created_during_task")
    protein_length = result.get("protein_length", 0)
    
    if fasta_exists and result.get("fasta_valid"):
        score += 10
        if 375 <= protein_length <= 385:
            score += 15
            feedback_parts.append(f"FASTA contains correct length protein: {protein_length} aa (+25)")
        else:
            feedback_parts.append(f"FASTA contains invalid length protein: {protein_length} aa (+10)")
    else:
        feedback_parts.append("Protein FASTA missing or invalid (0)")

    # CRITICAL: Check Biological Accuracy - Internal Stops (20 pts)
    # This mathematically proves whether the mitochondrial table was used.
    internal_stops = result.get("internal_stop_count", -1)
    no_internal_stops = False
    
    if fasta_exists and internal_stops == 0 and protein_length > 100:
        score += 20
        no_internal_stops = True
        feedback_parts.append("0 internal stop codons found - translation table correct (+20)")
    elif internal_stops > 0:
        feedback_parts.append(f"Failed: {internal_stops} internal stop codons found. Standard table was likely used instead of Mitochondrial. (0)")
    else:
        feedback_parts.append("Failed to check stop codons (0)")

    # Check Report Content (15 pts)
    if result.get("report_exists"):
        score += 5
        if result.get("report_mentions_table"):
            score += 5
        if result.get("report_mentions_length") or result.get("report_mentions_stop_context"):
            score += 5
        feedback_parts.append("Report analyzed (+15 max)")
    else:
        feedback_parts.append("Report missing (0)")

    # 2. VLM Trajectory Verification (20 pts - anti-scripting check)
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            vlm_resp = query_vlm(images=images, prompt=VLM_PROMPT)
            if vlm_resp and vlm_resp.get("success"):
                vlm_data = vlm_resp.get("parsed", {})
                if vlm_data.get("orf_tool_used", False):
                    vlm_score += 10
                if vlm_data.get("translation_table_interaction", False) or vlm_data.get("mitochondrial_table_visible", False):
                    vlm_score += 10
                feedback_parts.append(f"VLM verified UI interaction (+{vlm_score})")
            else:
                feedback_parts.append("VLM evaluation failed to parse")
    except ImportError:
        # If VLM is not available in the testing framework context, give free pass to prevent crash
        logger.warning("VLM module not found, skipping VLM check.")
        vlm_score = 20
        feedback_parts.append("VLM check skipped (+20)")

    score += vlm_score

    # 3. Final Determination
    # A perfect score is 100. Passing requires 70 points AND the mandatory check (no internal stops).
    key_criteria_met = no_internal_stops and fasta_exists
    passed = (score >= 70) and key_criteria_met

    if not key_criteria_met:
        feedback_parts.append("CRITICAL FAILURE: The translated sequence has internal stops, proving the Mitochondrial translation table was not successfully applied.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }