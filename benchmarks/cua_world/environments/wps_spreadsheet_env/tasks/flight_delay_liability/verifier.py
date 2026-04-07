#!/usr/bin/env python3
"""
Verifier for flight_delay_liability task.
Evaluates nested logical formulas, cross-sheet references, 
and correct aggregations based on pre-computed ground truth.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_flight_delay_liability(traj, env_info, task_info):
    """
    Verification strategy:
    1. File was modified.
    2. Status and Payout columns exist and logic matches ground truth (sampled rows).
    3. Status/Payout use formulas (IF).
    4. Liability Summary sheet exists.
    5. Summary values match ground truth aggregations.
    6. Summary formulas use aggregation functions (COUNTIF, SUMIF).
    7. Payout columns are currency formatted.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
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

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}
        
    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Target file was not found."}

    score = 0
    feedback_parts = []
    max_score = 100
    
    # 1. Check if file was actually modified (anti-gaming)
    if result.get("file_modified"):
        feedback_parts.append("✅ File modified")
        score += 5
    else:
        feedback_parts.append("❌ File not saved/modified")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Check Sample Evaluated Values (Columns J and K)
    samples = result.get("sample_evaluations", [])
    if not samples:
        feedback_parts.append("❌ No data found in Flights sheet")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    status_correct = 0
    payout_correct = 0
    uses_if = False
    
    for s in samples:
        # Check Status
        if str(s["Agent_Status"]).strip().lower() == str(s["GT_Status"]).strip().lower():
            status_correct += 1
        # Check Payout
        try:
            if float(s["Agent_Payout"] or 0) == float(s["GT_Payout"]):
                payout_correct += 1
        except:
            pass
            
        # Check formulas
        if s["Status_Formula"] and isinstance(s["Status_Formula"], str) and "IF" in s["Status_Formula"].upper():
            uses_if = True
        if s["Payout_Formula"] and isinstance(s["Payout_Formula"], str) and "IF" in s["Payout_Formula"].upper():
            uses_if = True

    status_acc = status_correct / len(samples)
    payout_acc = payout_correct / len(samples)
    
    if status_acc >= 0.95:
        score += 15
        feedback_parts.append("✅ Status logic correct")
    else:
        feedback_parts.append(f"❌ Status logic incorrect ({status_acc*100:.0f}% match)")
        
    if payout_acc >= 0.95:
        score += 15
        feedback_parts.append("✅ Payout logic correct")
    else:
        feedback_parts.append(f"❌ Payout logic incorrect ({payout_acc*100:.0f}% match)")

    if uses_if:
        score += 10
        feedback_parts.append("✅ Used formulas (IF) for classification")
    else:
        feedback_parts.append("❌ Did not use formulas (IF) for classification")

    # 3. Check Liability Summary Sheet
    if not result.get("has_summary_sheet"):
        feedback_parts.append("❌ 'Liability Summary' sheet missing")
        passed = score >= 70
        return {"passed": passed, "score": score, "feedback": " | ".join(feedback_parts)}

    score += 10
    feedback_parts.append("✅ 'Liability Summary' sheet exists")

    # 4. Check Aggregations and Formatting
    summary_vals = result.get("summary_values", {})
    summary_forms = result.get("summary_formulas", {})
    ground_truth = result.get("ground_truth", {})
    formats = result.get("formatting", {})
    
    target_airlines = ["AA", "DL", "UA", "WN", "B6"]
    
    agg_matches = 0
    agg_total = len(target_airlines) * 4
    uses_agg_formulas = False
    currency_formatted = False

    for al in target_airlines:
        gt = ground_truth.get(al, {})
        ag = summary_vals.get(al, {})
        fm = summary_forms.get(al, {})
        fmt = formats.get(al, "")

        if not gt or not ag:
            continue
            
        try:
            if int(ag.get("Total_Flights") or 0) == gt.get("Total_Flights"): agg_matches += 1
            if int(ag.get("Severely_Delayed") or 0) == gt.get("Severely_Delayed"): agg_matches += 1
            if float(ag.get("Total_Payout") or 0) == gt.get("Total_Payout"): agg_matches += 1
            if abs(float(ag.get("Avg_Payout") or 0) - gt.get("Avg_Payout")) < 1.0: agg_matches += 1
        except:
            pass

        # Check for aggregate formulas
        forms_str = str(fm.get("Total_Flights","")) + str(fm.get("Total_Payout",""))
        if "COUNTIF" in forms_str.upper() or "SUMIF" in forms_str.upper():
            uses_agg_formulas = True
            
        # Check formatting (Excel stores currency as strings with $ or special format codes)
        if "$" in str(fmt) or "€" in str(fmt) or "£" in str(fmt) or "Currency" in str(fmt):
            currency_formatted = True

    agg_acc = agg_matches / agg_total if agg_total > 0 else 0
    if agg_acc >= 0.9:
        score += 25
        feedback_parts.append("✅ Summary aggregations correct")
    elif agg_acc > 0:
        partial = int(25 * agg_acc)
        score += partial
        feedback_parts.append(f"⚠️ Summary aggregations partially correct ({agg_acc*100:.0f}%)")
    else:
        feedback_parts.append("❌ Summary aggregations missing/incorrect")

    if uses_agg_formulas:
        score += 10
        feedback_parts.append("✅ Used aggregation formulas (COUNTIF/SUMIF)")
    else:
        feedback_parts.append("❌ Aggregation formulas not detected")

    if currency_formatted:
        score += 10
        feedback_parts.append("✅ Currency formatting applied")
    else:
        feedback_parts.append("❌ Currency formatting missing")

    # Final pass/fail determination (must have high score and correct logic)
    passed = score >= 70 and status_acc >= 0.9 and payout_acc >= 0.9 and agg_acc > 0.5
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }