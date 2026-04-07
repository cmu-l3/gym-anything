#!/usr/bin/env python3
import json
import os
import tempfile
import re

def verify_sickle_cell_rflp_genotyping(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # Criterion 1: Wild-type GenBank File
    if result.get("wt_gb_exists", False):
        score += 10
        feedback_parts.append("WT GB exists (+10)")
    else:
        feedback_parts.append("WT GB missing (0)")
        
    # Criterion 2: Mutant GenBank File
    if result.get("mut_gb_exists", False):
        score += 10
        feedback_parts.append("Mut GB exists (+10)")
    else:
        feedback_parts.append("Mut GB missing (0)")
        
    # Criterion 3: Wild-type DdeI annotation count
    wt_count = result.get("wt_ddei_count", 0)
    if wt_count == 2:
        score += 15
        feedback_parts.append("WT has 2 DdeI sites (+15)")
    elif wt_count > 0:
        score += 5
        feedback_parts.append(f"WT has {wt_count} DdeI sites (+5)")
    else:
        feedback_parts.append("WT has 0 DdeI sites (0)")
        
    # Criterion 4: Mutant DdeI annotation count
    mut_count = result.get("mut_ddei_count", 0)
    if mut_count == 1:
        score += 15
        feedback_parts.append("Mut has 1 DdeI site (+15)")
    elif mut_count > 0:
        score += 5
        feedback_parts.append(f"Mut has {mut_count} DdeI sites (+5)")
    else:
        feedback_parts.append("Mut has 0 DdeI sites (0)")
        
    # Criterion 5, 6, 7, 8: Report Analysis
    if result.get("report_exists", False):
        score += 10
        feedback_parts.append("Report exists (+10)")
        
        content = result.get("report_content", "").lower()
        
        # Site counts check
        has_2 = bool(re.search(r'\b2\b|two', content))
        has_1 = bool(re.search(r'\b1\b|one', content))
        if has_2 and has_1:
            score += 10
            feedback_parts.append("Report mentions 2 and 1 sites (+10)")
        else:
            feedback_parts.append("Report missing site counts (0)")
            
        # Fragment lengths check
        has_100 = bool(re.search(r'\b100\b', content))
        has_97  = bool(re.search(r'\b97\b', content))
        has_203 = bool(re.search(r'\b203\b', content))
        has_300 = bool(re.search(r'\b300\b', content))
        
        if has_100 and has_97 and has_203 and has_300:
            score += 15
            feedback_parts.append("Report has exact fragment lengths (+15)")
        elif has_100 and (has_97 or has_300):
            score += 5
            feedback_parts.append("Report has some fragment lengths (+5)")
        else:
            feedback_parts.append("Report missing exact fragment lengths (0)")
            
        # Diagnostic Conclusion Check
        if any(w in content for w in ["loss", "lost", "merge", "merg", "destroy", "larger", "smaller"]):
            score += 15
            feedback_parts.append("Report includes correct diagnostic conclusion (+15)")
        else:
            feedback_parts.append("Report missing diagnostic conclusion (0)")
    else:
        feedback_parts.append("Report missing (0)")
        
    # Pass condition requires minimum score and presence of core artifacts
    passed = score >= 70 and result.get("report_exists", False) and (result.get("wt_gb_exists", False) or result.get("mut_gb_exists", False))
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }