#!/usr/bin/env python3
"""Verifier for housing filtering analysis task."""

import json
import tempfile
import os
import re

def build_verifier_result(score, max_score, feedback_parts, pass_threshold=60):
    """Build standardized verifier result dict."""
    final_score = min(score, max_score)
    passed = final_score >= pass_threshold
    feedback = "; ".join([f for f in feedback_parts if f])
    return {
        "passed": passed,
        "score": final_score,
        "feedback": feedback
    }

def verify_housing_filtering_analysis(traj, env_info, task_info):
    """Verify housing filtering analysis was completed.
    
    Scoring Strategy (100 points total):
    - CSV File: 25 points
    - Plot Image: 10 points
    - Text Report: 35 points
    - Notebook Code/Execution: 30 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback = []

    # Get JSON result parsed by export_result.sh
    result = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read task result metadata: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result is None:
        return build_verifier_result(0, max_score, feedback)

    # 1. Verify CSV Data (25 points)
    if result.get('csv_exists'):
        if result.get('csv_created'):
            score += 5
            feedback.append("CSV created (+5)")
        
        if result.get('has_zone_id_col') and result.get('has_income_col') and result.get('has_filtering_index_col'):
            score += 10
            feedback.append("CSV has expected columns (+10)")
        else:
            feedback.append("CSV missing some expected columns")
            
        csv_rows = result.get('csv_rows', 0)
        if csv_rows >= 20:
            score += 10
            feedback.append(f"CSV has sufficient zones ({csv_rows}) (+10)")
        elif csv_rows >= 5:
            score += 5
            feedback.append(f"CSV has some zones ({csv_rows}) (+5)")
    else:
        feedback.append("CSV file missing")

    # 2. Verify Plot (10 points)
    if result.get('plot_exists'):
        if result.get('plot_created'):
            score += 5
            feedback.append("Chart created (+5)")
            
        if result.get('plot_size_kb', 0) >= 10:
            score += 5
            feedback.append("Chart file size is valid (+5)")
    else:
        feedback.append("Chart file missing")

    # 3. Verify Report Content (35 points)
    report_text = ""
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/home/ga/urbansim_projects/output/filtering_report.txt", temp_report.name)
        with open(temp_report.name, 'r') as f:
            report_text = f.read()
    except Exception:
        pass
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    if result.get('report_exists') and report_text:
        score += 5
        feedback.append("Report exists (+5)")
        
        # Check Pearson correlation
        corr_pattern = r'[-]?\d+\.\d+'
        has_correlation = False
        for match in re.findall(corr_pattern, report_text):
            try:
                val = float(match)
                if -1.0 <= val <= 1.0 and abs(val) < 0.999:
                    has_correlation = True
                    break
            except ValueError:
                pass
                
        if has_correlation or re.search(r'[Cc]orrelation.*[-]?\d+\.\d+', report_text):
            score += 10
            feedback.append("Report contains Pearson correlation (+10)")
        else:
            feedback.append("Report missing valid Pearson correlation value")
            
        # Check zone count
        if re.search(r'(\d+)\s*zone', report_text, re.IGNORECASE):
            score += 5
            feedback.append("Report mentions zone count (+5)")
            
        # Check median filtering index
        fi_pattern = r'[Mm]edian\s+filter.*?(\d+\.\d+)|filter.*?[Mm]edian.*?(\d+\.\d+)|median.*?index.*?(\d+\.\d+)'
        if re.search(fi_pattern, report_text, re.IGNORECASE) or re.search(r'filter.*?(\d+\.\d+)', report_text, re.IGNORECASE):
            score += 10
            feedback.append("Report contains median filtering index (+10)")
        else:
            feedback.append("Report missing median filtering index")
            
        # Check interpretation
        interp_keywords = ['support', 'suggest', 'indicate', 'evidence', 'confirm', 'consistent', 'filtering', 'hypothesis', 'show']
        interp_count = sum(1 for kw in interp_keywords if kw.lower() in report_text.lower())
        if interp_count >= 1:
            score += 5
            feedback.append("Report contains interpretation logic (+5)")
    else:
        feedback.append("Report file missing or empty")

    # 4. Verify Notebook Code & Execution (30 points)
    if result.get('notebook_exists') and result.get('notebook_modified'):
        score += 5
        feedback.append("Notebook edited (+5)")
        
    nb_analysis = result.get('notebook_analysis', {})
    
    code_pts = 0
    if nb_analysis.get('has_read_hdf'):
        code_pts += 5
    if nb_analysis.get('has_merge'):
        code_pts += 5
    if nb_analysis.get('has_corr'):
        code_pts += 5
    score += code_pts
    if code_pts > 0:
        feedback.append(f"Code features detected (+{code_pts})")
    
    num_exec = nb_analysis.get('num_executed_cells', 0)
    if num_exec >= 5:
        score += 10
        feedback.append("Notebook executed successfully (+10)")
    elif num_exec >= 2:
        score += 5
        feedback.append("Notebook partially executed (+5)")

    return build_verifier_result(score, max_score, feedback, pass_threshold=60)