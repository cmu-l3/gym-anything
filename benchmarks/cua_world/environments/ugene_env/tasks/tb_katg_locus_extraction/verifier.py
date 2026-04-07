#!/usr/bin/env python3
"""
Verifier for tb_katg_locus_extraction task.

Verifies:
1. Expected files exist and were created during the task.
2. GenBank file is valid, contains KatG annotations, and matches expected extraction length.
3. Report file correctly identifies the minus/reverse strand.
4. VLM verifies trajectory indicates usage of UGENE for extraction.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_file_content(env_info, container_path, is_json=False):
    """Helper to copy a file from the container and read its content."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return None

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".tmp")
    tmp.close()
    
    try:
        copy_from_env(container_path, tmp.name)
        with open(tmp.name, 'r', encoding='utf-8', errors='ignore') as f:
            if is_json:
                return json.load(f)
            return f.read()
    except Exception as e:
        logger.error(f"Failed to read {container_path}: {e}")
        return None
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)


def verify_tb_katg_locus_extraction(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    # 1. Fetch Exported Metadata JSON
    result_meta = get_file_content(env_info, "/tmp/katg_task_result.json", is_json=True)
    if not result_meta:
        return {"passed": False, "score": 0, "feedback": "Failed to read task result metadata. Export script may have failed."}
        
    gb_exists = result_meta.get('gb_exists', False)
    report_exists = result_meta.get('report_exists', False)
    
    if not gb_exists and not report_exists:
        return {"passed": False, "score": 0, "feedback": "Neither the GenBank file nor the report file were found."}

    # Anti-gaming: Ensure files were actually created during task execution
    if result_meta.get('gb_created_during_task') or result_meta.get('report_created_during_task'):
        score += 10
        feedback_parts.append("Files created during task (+10)")
    else:
        feedback_parts.append("Files existed before task started (possible gaming)")

    # 2. Verify GenBank File
    gb_content = get_file_content(env_info, "/tmp/katG_locus.gb") if gb_exists else None
    
    if gb_content:
        # Check if it's a valid GenBank
        if "LOCUS" in gb_content[:500] and "ORIGIN" in gb_content:
            score += 10
            feedback_parts.append("Valid GenBank format (+10)")
            
            # Check for KatG/Rv1908c annotation preservation
            if "katG" in gb_content or "Rv1908c" in gb_content:
                score += 15
                feedback_parts.append("Annotations preserved (+15)")
            else:
                feedback_parts.append("Missing katG/Rv1908c annotations in export")
                
            # Check extraction sequence length
            # Extract sequence from ORIGIN block
            origin_match = re.search(r'ORIGIN\s+(.*?)(?:\/\/(.*)|$)', gb_content, re.DOTALL)
            if origin_match:
                raw_seq = origin_match.group(1)
                clean_seq = re.sub(r'[\d\s]', '', raw_seq)
                seq_len = len(clean_seq)
                
                expected_length = task_info.get("metadata", {}).get("expected_length", 2973)
                tolerance = task_info.get("metadata", {}).get("tolerance", 5)
                
                if abs(seq_len - expected_length) <= tolerance:
                    score += 25
                    feedback_parts.append(f"Correct extraction length ({seq_len} bp) (+25)")
                else:
                    feedback_parts.append(f"Incorrect length: {seq_len} bp (expected {expected_length} bp)")
        else:
            feedback_parts.append("Exported file is not in valid GenBank format")
    else:
        feedback_parts.append("GenBank export file is missing")

    # 3. Verify Report Accuracy
    report_content = get_file_content(env_info, "/tmp/extraction_report.txt") if report_exists else None
    
    if report_content:
        report_lower = report_content.lower()
        # Verify strand identification (katG is on the minus strand)
        if "minus" in report_lower or "reverse" in report_lower or "(-)" in report_lower or "- strand" in report_lower:
            score += 15
            feedback_parts.append("Correct strand identified in report (+15)")
        elif "plus" in report_lower or "forward" in report_lower or "(+)" in report_lower or "+ strand" in report_lower:
            feedback_parts.append("Incorrect strand identified in report (katG is on the minus strand)")
        else:
            feedback_parts.append("Strand orientation not clearly identified in report")
            
        # Verify mention of correct coordinates (2153889..2156111)
        if "2153889" in report_content and "2156111" in report_content:
            score += 5
            feedback_parts.append("Original coordinates identified (+5)")
    else:
        feedback_parts.append("Extraction report is missing")

    # 4. VLM Trajectory Verification
    vlm_score = 0
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """
        Examine these screenshots of an agent performing a bioinformatics task in UGENE.
        Task: Extracting the katG gene region from the Mycobacterium tuberculosis genome.
        
        Look for evidence that the agent:
        1. Used UGENE's interface (Sequence View, annotations panel).
        2. Searched for 'katG' or 'Rv1908c'.
        3. Selected a sequence region.
        4. Used export/save dialogs.
        
        Did the agent actually use UGENE to perform the work?
        Respond with JSON:
        {
            "ugene_used": true/false,
            "searched_gene": true/false,
            "region_selected": true/false,
            "confidence": "high/medium/low",
            "reasoning": "Brief explanation"
        }
        """
        
        try:
            vlm_response = query_vlm(images=frames, prompt=prompt)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("ugene_used"):
                    vlm_score += 10
                    if parsed.get("searched_gene") or parsed.get("region_selected"):
                        vlm_score += 10
                        feedback_parts.append("VLM verified UGENE interaction (+20)")
                    else:
                        feedback_parts.append("VLM verified UGENE open, but limited interaction (+10)")
                else:
                    feedback_parts.append("VLM did not detect UGENE usage")
            else:
                # Give partial credit if VLM fails but files are perfect
                vlm_score += 10 
                feedback_parts.append("VLM query failed, partial default score (+10)")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            vlm_score += 10
            
    score += vlm_score

    # Final Pass/Fail determination
    passed = score >= 70 and ("Correct extraction length" in str(feedback_parts))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }