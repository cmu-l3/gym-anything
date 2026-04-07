#!/usr/bin/env python3
"""
Verifier for dmd_crispr_sgrna_discovery task.

Verification checks:
1. Files exist (GenBank and Text report)
2. GenBank format is valid
3. GenBank contains 'sgRNA_target' annotations
4. Both forward and reverse strands are targeted
5. Annotation coordinates are exactly 23bp long
6. Ground truth annotation count matches
7. Text report contains 23bp sequence candidates
"""

import os
import json
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dmd_crispr_sgrna_discovery(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    subscores = {}

    # 1. Retrieve the Task Result JSON
    task_result = {}
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_res.close()
    try:
        copy_from_env("/tmp/dmd_crispr_task_result.json", tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result JSON: {e}"}
    finally:
        os.unlink(tmp_res.name)

    # 2. Retrieve the Ground Truth JSON
    gt = {}
    tmp_gt = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_gt.close()
    try:
        copy_from_env("/tmp/dmd_crispr_gt.json", tmp_gt.name)
        with open(tmp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        gt = {"total_targets": 0, "target_length": 23}
        logger.warning(f"Failed to load GT JSON: {e}")
    finally:
        os.unlink(tmp_gt.name)

    # 3. Criterion: Files exist (10 pts)
    gb_exists = task_result.get("gb_exists", False)
    txt_exists = task_result.get("txt_exists", False)
    
    if gb_exists and txt_exists:
        score += 10
        feedback_parts.append("Output files exist (+10)")
    elif gb_exists:
        score += 5
        feedback_parts.append("GenBank file exists, text report missing (+5)")
    else:
        feedback_parts.append("GenBank file MISSING (0)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 4. Fetch the GenBank file contents
    gb_content = ""
    tmp_gb = tempfile.NamedTemporaryFile(delete=False, suffix=".gb")
    tmp_gb.close()
    try:
        copy_from_env("/tmp/dmd_targets.gb", tmp_gb.name)
        with open(tmp_gb.name, 'r') as f:
            gb_content = f.read()
    except Exception as e:
        pass
    finally:
        os.unlink(tmp_gb.name)

    # Criterion: GenBank format validity (10 pts)
    if "LOCUS" in gb_content and "FEATURES" in gb_content and "ORIGIN" in gb_content:
        score += 10
        feedback_parts.append("Valid GenBank format (+10)")
    else:
        feedback_parts.append("Invalid GenBank format (0)")

    # 5. Parse GenBank for sgRNA_target features
    # Standard GenBank feature lines:
    #      sgRNA_target    123..145
    #      sgRNA_target    complement(200..222)
    pattern = r"sgRNA_target\s+(?:complement\()?(\d+)\.\.(\d+)\)?"
    matches = list(re.finditer(pattern, gb_content))
    
    # Criterion: sgRNA_target features exist (20 pts)
    total_annotations = len(matches)
    if total_annotations > 0:
        score += 20
        feedback_parts.append(f"Found {total_annotations} 'sgRNA_target' annotations (+20)")
    else:
        feedback_parts.append("No 'sgRNA_target' annotations found (0)")

    # Analyze strands and lengths
    fwd_count = 0
    rev_count = 0
    exact_len_count = 0
    
    for m in matches:
        is_complement = "complement" in m.group(0)
        start = int(m.group(1))
        end = int(m.group(2))
        length = end - start + 1
        
        if is_complement:
            rev_count += 1
        else:
            fwd_count += 1
            
        if length == gt.get("target_length", 23):
            exact_len_count += 1

    # Criterion: Dual-strand targeting (15 pts)
    if total_annotations > 0:
        if fwd_count > 0 and rev_count > 0:
            score += 15
            feedback_parts.append(f"Dual-strand targeted (Fwd:{fwd_count}, Rev:{rev_count}) (+15)")
        else:
            score += 5
            feedback_parts.append(f"Only single strand targeted (Fwd:{fwd_count}, Rev:{rev_count}) (+5)")

    # Criterion: Coordinate Exactness (Lengths exactly 23bp) (20 pts)
    if total_annotations > 0:
        if exact_len_count == total_annotations:
            score += 20
            feedback_parts.append("All targets are exactly 23bp long (+20)")
        elif exact_len_count > 0:
            pct = exact_len_count / total_annotations
            pts = int(20 * pct)
            score += pts
            feedback_parts.append(f"Some targets ({exact_len_count}/{total_annotations}) are 23bp (+{pts})")
        else:
            # Check if they did 3bp (just the PAM)
            sample_len = 0
            if len(matches) > 0:
                sample_len = int(matches[0].group(2)) - int(matches[0].group(1)) + 1
            feedback_parts.append(f"Targets are not 23bp (found length {sample_len}) (0)")

    # Criterion: Ground Truth Match (15 pts)
    expected_total = gt.get("total_targets", 0)
    if total_annotations > 0 and expected_total > 0:
        if abs(total_annotations - expected_total) <= 2:
            score += 15
            feedback_parts.append(f"Total target count matches ground truth ({total_annotations}) (+15)")
        elif total_annotations > expected_total / 2:
            score += 7
            feedback_parts.append(f"Target count {total_annotations} (expected {expected_total}) (+7)")
        else:
            feedback_parts.append(f"Target count {total_annotations} differs significantly from expected {expected_total} (0)")

    # 6. Check Text Report (10 pts)
    if txt_exists:
        txt_content = ""
        tmp_txt = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
        tmp_txt.close()
        try:
            copy_from_env("/tmp/sgrna_candidates.txt", tmp_txt.name)
            with open(tmp_txt.name, 'r') as f:
                txt_content = f.read()
        except Exception:
            pass
        finally:
            os.unlink(tmp_txt.name)
            
        # Look for 23bp DNA sequences
        seq_matches = re.findall(r"\b[ACGTacgt]{23}\b", txt_content)
        valid_seqs = [s for s in seq_matches if s.upper().endswith("GG") or s.upper().startswith("CC")]
        
        if len(valid_seqs) >= 5:
            score += 10
            feedback_parts.append("Report contains valid 23bp candidates (+10)")
        elif len(valid_seqs) > 0:
            score += 5
            feedback_parts.append(f"Report contains {len(valid_seqs)} candidates (expected >= 5) (+5)")
        else:
            feedback_parts.append("Report does not contain valid 23bp target sequences (0)")
    else:
        if gb_exists:
            feedback_parts.append("Text report missing (0)")

    # Final pass logic
    passed = score >= 70 and total_annotations > 0 and exact_len_count > 0

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }