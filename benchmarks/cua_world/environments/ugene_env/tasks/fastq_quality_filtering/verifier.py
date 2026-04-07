#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def build_vlm_prompt():
    return """Examine these screenshots from a bioinformatics agent's trajectory in UGENE.
    
Task: Filter a FASTQ file by quality and export it to FASTA format.

Check for these indicators of workflow progression:
1. Did the agent use UGENE's FASTQ filtering tools (e.g., "Filter FASTQ" under the Tools -> NGS Data Analysis menu)?
2. Did the agent open or view the newly filtered FASTQ file within the UGENE UI?
3. Did the agent use the "Export" or "Save as" dialog to save the sequences in FASTA format?

Respond in JSON format with boolean keys and a brief reason:
{
    "used_ugene_filtering_tools": true/false,
    "viewed_filtered_reads": true/false,
    "used_export_dialog": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Briefly explain the evidence."
}
"""

def verify_fastq_quality_filtering(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/fastq_quality_filtering_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result JSON: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: FASTQ Filtering Quality & Count (40 pts) ---
    fq_reads = result.get("fq_reads", 0)
    raw_reads = result.get("raw_reads", 0)
    
    if result.get("fq_exists", False):
        if result.get("fq_created_during_task", False):
            score += 15
            feedback_parts.append("Filtered FASTQ created (+15)")
            
            # Verify mathematical conditions: All Q >= 20, and count strictly reduced but > 0
            if result.get("fq_all_qual_pass", False) and 0 < fq_reads < raw_reads:
                score += 25
                feedback_parts.append(f"Filtering successful: dropped low qual, kept {fq_reads}/{raw_reads} reads (+25)")
            elif fq_reads >= raw_reads:
                feedback_parts.append(f"Filtering failed: no reads removed ({fq_reads} kept) (0)")
            elif not result.get("fq_all_qual_pass", False):
                feedback_parts.append("Filtering failed: remaining reads contain average Q < 20 (0)")
            elif fq_reads == 0:
                feedback_parts.append("Filtering failed: 0 reads kept (0)")
        else:
            feedback_parts.append("Filtered FASTQ exists but was not created during task (anti-gaming) (0)")
    else:
        feedback_parts.append("Filtered FASTQ missing (0)")

    # --- Criterion 2: FASTA Format Conversion (30 pts) ---
    fa_reads = result.get("fa_reads", 0)
    if result.get("fa_exists", False):
        if result.get("fa_created_during_task", False):
            score += 10
            feedback_parts.append("FASTA file created (+10)")
            
            if result.get("fa_is_valid", False) and fa_reads == fq_reads and fa_reads > 0:
                score += 20
                feedback_parts.append(f"FASTA is valid and sequence count matches FASTQ ({fa_reads}) (+20)")
            else:
                feedback_parts.append(f"FASTA invalid or count mismatch (FASTA: {fa_reads}, FASTQ: {fq_reads}) (0)")
        else:
            feedback_parts.append("FASTA file exists but was not created during task (0)")
    else:
        feedback_parts.append("FASTA file missing (0)")

    # --- Criterion 3: QC Report Evaluation (10 pts) ---
    if result.get("rep_exists", False) and result.get("rep_created_during_task", False):
        score += 5
        feedback_parts.append("QC Report created (+5)")
        if result.get("rep_mentions_20", False):
            score += 5
            feedback_parts.append("Report mentions Q20 threshold (+5)")
    else:
        feedback_parts.append("QC Report missing (0)")

    # --- Criterion 4: VLM Trajectory Verification (20 pts) ---
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        if frames or final:
            images = frames + [final] if final else frames
            vlm_result = query_vlm(images=images, prompt=build_vlm_prompt())
            
            if vlm_result.get("success", False):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("used_ugene_filtering_tools", False):
                    score += 10
                    feedback_parts.append("VLM confirmed UGENE filtering tools used (+10)")
                if parsed.get("used_export_dialog", False):
                    score += 10
                    feedback_parts.append("VLM confirmed export dialog used (+10)")
        else:
            feedback_parts.append("No screenshots available for VLM verification (0)")
    except Exception as e:
        logger.warning(f"VLM verification failed or unavailable: {e}")
        feedback_parts.append("VLM verification skipped (0)")

    # --- Final Determination ---
    key_criteria_met = (
        result.get("fq_exists", False) and
        result.get("fq_all_qual_pass", False) and
        result.get("fa_exists", False) and
        result.get("fa_is_valid", False) and
        result.get("fq_reads", 0) > 0
    )

    # 75 points represents passing the mathematical FASTQ filtering AND the FASTA conversion
    passed = score >= 75 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }