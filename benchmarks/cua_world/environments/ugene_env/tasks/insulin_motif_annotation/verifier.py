#!/usr/bin/env python3
"""
Verifier for insulin_motif_annotation task.

Scores based on the presence of correctly structured motif annotations
in the exported GenBank file, validated against biological ground truth.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_insulin_motif_annotation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available"}
        
    # Read the exported task results
    result = {}
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_res.close()
    try:
        copy_from_env("/tmp/insulin_motif_result.json", tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result output: {e}"}
    finally:
        if os.path.exists(tmp_res.name):
            os.unlink(tmp_res.name)
            
    # Read dynamic Ground Truth
    gt = {}
    tmp_gt = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_gt.close()
    try:
        copy_from_env("/tmp/insulin_motif_gt.json", tmp_gt.name)
        with open(tmp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load dynamic GT, using fallbacks. Error: {e}")
        gt = {
            "TATA_box": 1,
            "E_box": 5,
            "GC_box": 2,
            "polyA_signal": 1,
            "CArG_box": 0
        }
    finally:
        if os.path.exists(tmp_gt.name):
            os.unlink(tmp_gt.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: GB File is valid (8 pts)
    if result.get("gb_exists") and result.get("gb_valid"):
        score += 8
        feedback_parts.append("GenBank output valid (+8)")
    else:
        feedback_parts.append("GenBank output missing/invalid (0)")
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback_parts)}
        
    valid_annots = result.get("valid_annotations", {})
    
    # Points breakdown per Motif
    motif_points = {
        "TATA_box": 12,
        "E_box": 15,
        "GC_box": 12,
        "polyA_signal": 12,
        "CArG_box": 14
    }
    
    distinct_groups_handled = 0
    
    for motif, max_pts in motif_points.items():
        expected = gt.get(motif, 0)
        actual = valid_annots.get(motif, 0)
        
        if actual > 0 or (expected == 0 and actual == 0):
            distinct_groups_handled += 1
            
        if expected == 0:
            if actual == 0:
                score += max_pts
                feedback_parts.append(f"{motif} correct: 0 found as expected (+{max_pts})")
            else:
                feedback_parts.append(f"{motif} incorrect: expected 0, but annotated {actual} (0)")
        else:
            if actual == expected:
                score += max_pts
                feedback_parts.append(f"{motif} correct: {actual}/{expected} found (+{max_pts})")
            elif actual > 0:
                partial = int(max_pts * (min(actual, expected) / expected))
                score += partial
                feedback_parts.append(f"{motif} partial: {actual}/{expected} found (+{partial})")
            else:
                feedback_parts.append(f"{motif} missing: 0/{expected} found (0)")
                
    # Distinct annotations groups processed correctly (8 pts)
    if distinct_groups_handled >= 5:
        score += 8
        feedback_parts.append("All distinct motif groups handled (+8)")
    elif distinct_groups_handled > 0:
        pts = distinct_groups_handled
        score += pts
        feedback_parts.append(f"Some distinct motif groups handled (+{pts})")
        
    # Report Scoring (19 pts total)
    report_text = result.get("report_content", "")
    if result.get("report_exists") and report_text:
        report_lower = report_text.lower()
        
        # Lists all motif names (9 pts)
        motifs_found = 0
        for m in ["tata", "e_box", "gc_box", "polya", "carg"]:
            if m.replace("_", "") in report_lower.replace("_", ""):
                motifs_found += 1
        r_score = int((motifs_found / 5) * 9)
        score += r_score
        feedback_parts.append(f"Report lists {motifs_found}/5 motifs (+{r_score})")
        
        # Reports the total correct numerical sum (5 pts)
        total_gt = sum(gt.values())
        total_actual = sum(result.get("annotations", {}).values())
        if str(total_gt) in report_text or str(total_actual) in report_text:
            score += 5
            feedback_parts.append("Report total count correct (+5)")
            
        # Has biological interpretation content (5 pts)
        interp_kw = ["insulin", "pancreas", "beta", "transcription", "promoter", "regulation", "expression", "disease", "diabetes", "mody"]
        kw_found = sum(1 for kw in interp_kw if kw in report_lower)
        if kw_found >= 2 and len(report_text.split()) > 15:
            score += 5
            feedback_parts.append("Report has sufficient biological interpretation (+5)")
        elif kw_found >= 1:
            score += 2
            feedback_parts.append("Report has weak biological interpretation (+2)")
    else:
        feedback_parts.append("Report missing/empty (0)")
        
    passed = score >= 60 and result.get("gb_valid", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }