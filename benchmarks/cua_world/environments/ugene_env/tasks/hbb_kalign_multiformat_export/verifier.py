#!/usr/bin/env python3
"""
Verifier for hbb_kalign_multiformat_export task.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hbb_kalign_multiformat_export(traj, env_info, task_info):
    """
    Verifies the multiple sequence alignment and multi-format export task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected metadata
    metadata = task_info.get('metadata', {})
    expected_seq_count = metadata.get('expected_sequence_count', 8)
    min_len = metadata.get('expected_alignment_length_min', 140)
    max_len = metadata.get('expected_alignment_length_max', 200)

    # Retrieve result file from the environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Check for anti-gaming (do-nothing check)
    any_new_files = (
        result["fasta"]["new"] or 
        result["phy"]["new"] or 
        result["aln"]["new"] or 
        result["report"]["new"]
    )
    
    if not any_new_files:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No output files were created during the task execution."
        }

    valid_formats_count = 0
    aln_lengths = []

    # 1. FASTA Evaluation (20 points total)
    if result["fasta"]["exists"]:
        if result["fasta"]["valid"]:
            score += 12
            valid_formats_count += 1
            feedback_parts.append("Aligned FASTA format valid (+12)")
            
            if result["fasta"]["seq_count"] == expected_seq_count:
                score += 8
                feedback_parts.append("FASTA seq count correct (+8)")
            else:
                feedback_parts.append(f"FASTA seq count incorrect ({result['fasta']['seq_count']}) (0)")
                
            if result["fasta"]["aln_length"] > 0:
                aln_lengths.append(result["fasta"]["aln_length"])
        else:
            feedback_parts.append("FASTA file exists but format invalid (0)")
    else:
        feedback_parts.append("FASTA file missing (0)")

    # 2. PHYLIP Evaluation (20 points total)
    if result["phy"]["exists"]:
        if result["phy"]["valid"]:
            score += 12
            valid_formats_count += 1
            feedback_parts.append("PHYLIP format valid (+12)")
            
            if result["phy"]["seq_count"] == expected_seq_count:
                score += 8
                feedback_parts.append("PHYLIP seq count correct (+8)")
            else:
                feedback_parts.append(f"PHYLIP seq count incorrect ({result['phy']['seq_count']}) (0)")
                
            if result["phy"]["aln_length"] > 0:
                aln_lengths.append(result["phy"]["aln_length"])
        else:
            feedback_parts.append("PHYLIP file exists but format invalid (0)")
    else:
        feedback_parts.append("PHYLIP file missing (0)")

    # 3. ClustalW Evaluation (20 points total)
    if result["aln"]["exists"]:
        if result["aln"]["valid"]:
            score += 12
            valid_formats_count += 1
            feedback_parts.append("ClustalW ALN format valid (+12)")
            
            if result["aln"]["seq_count"] == expected_seq_count:
                score += 8
                feedback_parts.append("ClustalW seq count correct (+8)")
            else:
                feedback_parts.append(f"ClustalW seq count incorrect ({result['aln']['seq_count']}) (0)")
                
            if result["aln"]["aln_length"] > 0:
                aln_lengths.append(result["aln"]["aln_length"])
        else:
            feedback_parts.append("ClustalW file exists but format invalid (0)")
    else:
        feedback_parts.append("ClustalW ALN file missing (0)")

    # 4. Cross-format consistency (15 points total)
    if len(aln_lengths) >= 2:
        if len(set(aln_lengths)) == 1:
            score += 10
            feedback_parts.append("Alignment lengths are consistent across exported formats (+10)")
            
            # Check if length is biologically plausible
            if min_len <= aln_lengths[0] <= max_len:
                score += 5
                feedback_parts.append("Alignment length is biologically plausible (+5)")
            else:
                feedback_parts.append(f"Alignment length {aln_lengths[0]} outside expected range ({min_len}-{max_len}) (0)")
        else:
            feedback_parts.append("Alignment lengths are inconsistent across formats (0)")
    else:
        feedback_parts.append("Not enough valid formats to check length consistency (0)")

    # 5. Report Evaluation (25 points total)
    if result["report"]["exists"]:
        score += 5
        feedback_parts.append("Identity report exists (+5)")
        
        content = result["report"]["content"]
        
        # Check for sequence count (8)
        if re.search(r'\b8\b', content):
            score += 5
            feedback_parts.append("Report mentions correct sequence count (+5)")
        
        # Check for alignment length (any plausible length)
        if re.search(fr'\b(?:1[4-9]\d|200)\b', content):
            score += 5
            feedback_parts.append("Report mentions a plausible alignment length (+5)")
            
        # Check for identity percentages (should be at least 5-7 pairwise values)
        # Look for numbers between 40 and 100 optionally followed by %
        pct_matches = re.findall(r'\b([4-9]\d|100)(?:\.\d+)?\s*%?', content)
        if len(pct_matches) >= 5:
            score += 10
            feedback_parts.append("Report contains multiple pairwise identity percentages (+10)")
        elif len(pct_matches) > 0:
            score += 5
            feedback_parts.append("Report contains some identity percentages (+5)")
    else:
        feedback_parts.append("Identity report missing (0)")

    # Normalize score strictly to 100 maximum
    score = min(score, 100)
    
    # Require at least 2 alignment formats to be successfully exported to pass
    passed = score >= 60 and valid_formats_count >= 2

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }