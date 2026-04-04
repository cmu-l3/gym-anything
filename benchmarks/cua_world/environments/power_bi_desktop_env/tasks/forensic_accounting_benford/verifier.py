#!/usr/bin/env python3
"""
Verifier for Forensic Accounting Benford's Law Task.

Scoring Criteria:
1. File Saved (10 pts): Fraud_Detection.pbix exists.
2. File Freshness (10 pts): Modified during task.
3. Data Cleaning (15 pts): Evidence of column manipulation (Leading_Digit).
4. Benford Logic (25 pts): Usage of LOG10 in DataModel.
5. Visual Config (20 pts): Combo Chart present.
6. VLM Verification (20 pts): Chart visually matches Benford distribution (decreasing curve).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_benford_analysis(traj, env_info, task_info):
    """
    Verify the Power BI task results using file analysis and VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function missing."}

    # 1. Retrieve JSON Result from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    try:
        copy_from_env("C:/Users/Docker/Desktop/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Programmatic Checks (80 pts max) ---

    # Criterion 1 & 2: File Existence and Freshness (20 pts)
    if result.get('file_exists'):
        if result.get('file_created_during_task'):
            score += 20
            feedback.append("✅ File saved and modified during task.")
        else:
            score += 10
            feedback.append("⚠️ File exists but timestamp suggests it wasn't modified recently.")
    else:
        feedback.append("❌ Fraud_Detection.pbix not found.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # Criterion 3: Data Cleaning / Leading Digit (15 pts)
    # Check if 'Leading_Digit' was found in DataModel keywords
    keywords = result.get('model_keywords_found', [])
    if "Leading_Digit" in keywords:
        score += 15
        feedback.append("✅ 'Leading_Digit' column/measure detected.")
    else:
        feedback.append("❌ Could not find 'Leading_Digit' in data model.")

    # Criterion 4: Benford Logic (LOG10) (25 pts)
    if "LOG10" in keywords:
        score += 25
        feedback.append("✅ 'LOG10' function detected (Benford formula).")
    elif "Benford" in keywords:
        # Partial credit if they named it right but we missed the formula logic
        score += 10
        feedback.append("⚠️ 'Benford' measure found, but 'LOG10' not confirmed.")
    else:
        feedback.append("❌ No evidence of Benford formula (LOG10).")

    # Criterion 5: Visual Configuration (20 pts)
    visuals = result.get('visual_types', [])
    combo_charts = ["lineClusteredColumnComboChart", "lineStackedColumnComboChart"]
    if any(v in visuals for v in combo_charts):
        score += 20
        feedback.append("✅ Combo Chart (Line + Column) detected.")
    elif "columnChart" in visuals and "lineChart" in visuals:
        score += 10
        feedback.append("⚠️ Separate Line and Column charts found (Combo preferred).")
    elif visuals:
        score += 5
        feedback.append(f"⚠️ Charts found but not Combo type: {visuals}")
    else:
        feedback.append("❌ No recognized charts in report.")

    # --- VLM Verification (20 pts max) ---
    # We look for the visual shape of Benford's law: High bar at 1, decreasing to 9.
    
    vlm_score = 0
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot:
        prompt = """
        Analyze this Power BI report screenshot.
        I am looking for a Benford's Law analysis chart.
        
        1. Is there a bar chart or combo chart visible?
        2. Do the bars follow a rapidly decreasing pattern from left to right (digit 1 is highest (~30%), digit 9 is lowest (~5%))?
        3. Is there a line overlaying the bars (Expected vs Actual)?
        
        Answer JSON: {"chart_present": bool, "decreasing_pattern": bool, "line_overlay": bool}
        """
        
        try:
            vlm_resp = query_vlm(prompt=prompt, image=final_screenshot)
            if vlm_resp.get('success'):
                parsed = vlm_resp.get('parsed', {})
                if parsed.get('chart_present'):
                    vlm_score += 5
                if parsed.get('decreasing_pattern'):
                    vlm_score += 10
                if parsed.get('line_overlay'):
                    vlm_score += 5
                
                if vlm_score == 20:
                    feedback.append("✅ VLM confirms Benford distribution pattern.")
                elif vlm_score > 0:
                    feedback.append(f"⚠️ VLM partially confirms visual ({vlm_score}/20).")
                else:
                    feedback.append("❌ VLM did not see the expected chart pattern.")
            else:
                feedback.append("⚠️ VLM query failed, skipping visual verification.")
                # Give benefit of doubt if programmatic passed
                if score >= 60:
                    vlm_score = 10 
        except Exception:
            feedback.append("⚠️ VLM error.")
    
    score += vlm_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": "\n".join(feedback)
    }