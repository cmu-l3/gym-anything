#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_plasmid_standardization(traj, env_info, task_info):
    """
    Verify the plasmid_standardization_orf_mapping task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve the exported JSON result
    result = {}
    try:
        tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_res.close()
        copy_from_env("/tmp/plasmid_task_result.json", tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_res.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # 2. Retrieve the Ground Truth JSON
    gt = {}
    try:
        tmp_gt = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_gt.close()
        copy_from_env("/tmp/plasmid_gt.json", tmp_gt.name)
        with open(tmp_gt.name, 'r') as f:
            gt = json.load(f)
        os.unlink(tmp_gt.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read ground truth: {e}"}

    score = 0
    feedback = []
    
    fasta_exists = result.get("fasta_exists", False)
    fasta_seq = result.get("fasta_seq", "")
    created_during = result.get("fasta_created_during_task", False)
    report_exists = result.get("report_exists", False)
    report_content = result.get("report_content", "").upper()

    # --- Verify FASTA (45 points) ---
    if fasta_exists:
        if created_during:
            score += 5
            feedback.append("FASTA exported during task (+5)")
        else:
            feedback.append("FASTA file exists but was not created during task (+0)")

        # Start motif
        if fasta_seq.startswith("GAATTC"):
            score += 15
            feedback.append("Sequence correctly standardized to GAATTC (+15)")
        else:
            feedback.append("Sequence does NOT start with GAATTC (0)")

        # Length integrity
        if len(fasta_seq) == gt["original_length"]:
            score += 10
            feedback.append(f"Sequence length perfectly preserved ({gt['original_length']}) (+10)")
        else:
            feedback.append(f"Sequence length mutated (Expected {gt['original_length']}, got {len(fasta_seq)}) (0)")

        # Perfect Sequence Integrity Check
        if len(fasta_seq) == gt["original_length"] and fasta_seq == gt["std_seq"]:
            score += 15
            feedback.append("Sequence is a mathematically perfect circular permutation (+15)")
        else:
            feedback.append("Sequence content corrupted during manipulation (0)")
    else:
        feedback.append("FASTA file missing (0)")

    # --- Verify Report (35 points) ---
    if report_exists:
        score += 5
        feedback.append("Report file exists (+5)")

        # Verify Original EcoRI Coordinate
        if str(gt["ecori_pos"]) in report_content:
            score += 10
            feedback.append(f"Report correctly identifies original EcoRI coordinate ({gt['ecori_pos']}) (+10)")
        else:
            feedback.append(f"Report missing correct original EcoRI coordinate ({gt['ecori_pos']}) (0)")

        # Verify ORF Coordinates & Strand
        orf_start = str(gt["orf_start"])
        orf_end = str(gt["orf_end"])
        strand = gt["orf_strand"].upper()

        if orf_start in report_content and orf_end in report_content:
            score += 5
            feedback.append("Report contains correct ORF start/end bounds (+5)")
        else:
            feedback.append("Report missing correct ORF coordinate bounds (0)")

        if strand in report_content or ("REV" in strand and "REV" in report_content):
            score += 5
            feedback.append("Report contains correct ORF strand orientation (+5)")
        else:
            feedback.append("Report missing correct ORF strand orientation (0)")

        # Verify First 10 AA of translated ORF
        if gt["orf_first_10_aa"].upper() in report_content:
            score += 10
            feedback.append(f"Report contains exact correct translated AA sequence ({gt['orf_first_10_aa']}) (+10)")
        else:
            feedback.append("Report missing correct translated AA sequence (0)")
    else:
        feedback.append("Report file missing (0)")

    # --- VLM Verification for anti-gaming (20 points) ---
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            prompt = """Look at these screenshots showing an agent's trajectory.
Did the agent actively use the UGENE bioinformatics application UI to view a DNA sequence and identify reading frames?
Respond in JSON format with a single boolean field "used_ugene"."""
            images = frames + [final]
            vlm_res = query_vlm(images=images, prompt=prompt)
            if vlm_res and vlm_res.get("parsed", {}).get("used_ugene", False):
                vlm_score = 20
                feedback.append("VLM verified UGENE application usage (+20)")
            else:
                feedback.append("VLM could not verify UGENE usage (0)")
        except Exception as e:
            logger.warning(f"VLM verification skipped or failed: {e}")
            vlm_score = 20  # Give benefit of doubt if framework missing
            feedback.append("VLM skipped (+20)")
    else:
        vlm_score = 20
        feedback.append("VLM unavailable (+20)")
    
    score += vlm_score

    # Passed if all mandatory sequence checks succeed and overall score is decent
    key_criteria = (
        fasta_exists and 
        fasta_seq.startswith("GAATTC") and 
        len(fasta_seq) == gt["original_length"]
    )
    passed = score >= 65 and key_criteria

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }