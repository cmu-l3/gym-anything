#!/usr/bin/env python3
"""
Verifier for HIV-1 Gag-Pol Ribosomal Frameshift Annotation and Extraction.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hiv_frameshift(traj, env_info, task_info):
    """
    Verifies the HIV frameshift task completion using exported JSON data and VLM analysis.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_len = metadata.get('overlap_length', 208)
    expected_start = metadata.get('overlap_start', 2085)
    expected_end = metadata.get('overlap_end', 2292)

    score = 0
    feedback_parts = []
    
    # 1. Read exported results
    result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/hiv_frameshift_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read exported result: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to read task results. Agent likely did not save any files."
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    task_start = result.get('task_start_time', 0)
    
    # 2. Verify Annotated GenBank File (35 points total)
    gb_exists = result.get('gb_exists', False)
    gb_mtime = result.get('gb_mtime', 0)
    
    if gb_exists and gb_mtime >= task_start:
        score += 10
        feedback_parts.append("Annotated GB file created (+10)")
        
        has_feature = result.get('has_misc_feature', False)
        has_note = result.get('has_note', False)
        coords = result.get('feature_coords', [])
        
        if has_feature and has_note:
            score += 15
            feedback_parts.append("Custom misc_feature with correct note found (+15)")
            
            # Verify coordinates
            coords_correct = False
            for coord_str in coords:
                matches = re.findall(r'\d+', coord_str)
                if len(matches) == 2:
                    start, end = int(matches[0]), int(matches[1])
                    # Allow a small +/- 3bp tolerance for zero-indexing or slight selection variations
                    if abs(start - expected_start) <= 3 and abs(end - expected_end) <= 3:
                        coords_correct = True
                        break
            
            if coords_correct:
                score += 10
                feedback_parts.append(f"Annotation coordinates exactly match overlap (~{expected_start}..{expected_end}) (+10)")
            else:
                feedback_parts.append(f"Annotation coordinates incorrect. Expected ~{expected_start}..{expected_end}, got {coords}")
        else:
            feedback_parts.append("Missing 'misc_feature' or 'gag_pol_overlap' qualifier in GB file.")
    else:
        feedback_parts.append("Annotated GB file not found or not modified during task.")

    # 3. Verify FASTA Extraction (30 points total)
    fasta_exists = result.get('fasta_exists', False)
    fasta_mtime = result.get('fasta_mtime', 0)
    
    if fasta_exists and fasta_mtime >= task_start:
        score += 10
        feedback_parts.append("FASTA file extracted (+10)")
        
        seq_len = result.get('fasta_seq_length', 0)
        seq_content = result.get('fasta_content', "").upper()
        
        # Check Length (+10)
        if abs(seq_len - expected_len) <= 5:
            score += 10
            feedback_parts.append(f"FASTA sequence length correct ({seq_len}bp) (+10)")
        else:
            feedback_parts.append(f"FASTA length incorrect: expected {expected_len}, got {seq_len}")
            
        # Check Sequence content (+10)
        # The gag/pol overlap begins with the slippery sequence TTTTTTAGGGA
        if "TTTTTTAGGGA" in seq_content or "TTTTTT" in seq_content[:20]:
            score += 10
            feedback_parts.append("FASTA sequence matches expected overlap region (+10)")
        else:
            feedback_parts.append("FASTA sequence does not appear to be the frameshift region.")
    else:
        feedback_parts.append("FASTA file not found or not modified during task.")

    # 4. Verify Report Text (10 points)
    report_exists = result.get('report_exists', False)
    if report_exists:
        content = result.get('report_content', "")
        # Check if they mention the numbers roughly
        has_start = str(expected_start) in content or str(expected_start-1) in content or str(expected_start+1) in content
        has_end = str(expected_end) in content or str(expected_end-1) in content or str(expected_end+1) in content
        has_len = str(expected_len) in content
        
        if (has_start and has_end) or has_len:
            score += 10
            feedback_parts.append("Report file contains correct coordinates/length (+10)")
        else:
            score += 5
            feedback_parts.append("Report file exists but coordinates/length are missing or incorrect (+5)")
    else:
        feedback_parts.append("Report file not found.")

    # 5. VLM Trajectory Verification (25 points)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images and env_info.get('query_vlm'):
            prompt = """Analyze these screenshots of a user interacting with UGENE software.
            1. Is the user using UGENE to analyze DNA/RNA sequences? (True/False)
            2. Is there evidence of the user interacting with the Sequence View, Annotations editor, or exporting files? (True/False)
            
            Respond strictly with a JSON object:
            {"used_ugene": true/false, "interacted_with_sequence": true/false}
            """
            vlm_response = env_info['query_vlm'](images=images, prompt=prompt)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("used_ugene", False):
                    score += 10
                    feedback_parts.append("VLM confirmed UGENE usage (+10)")
                if parsed.get("interacted_with_sequence", False):
                    score += 15
                    feedback_parts.append("VLM confirmed sequence/annotation interaction (+15)")
            else:
                feedback_parts.append("VLM verification failed or returned invalid format.")
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        feedback_parts.append(f"VLM verification skipped/error: {e}")

    # Pass threshold: 75
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }