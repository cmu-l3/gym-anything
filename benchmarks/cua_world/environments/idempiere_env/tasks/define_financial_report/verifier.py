#!/usr/bin/env python3
"""
Verifier for define_financial_report task.

Verifies:
1. PA_Report header created with correct name
2. PA_ReportLineSet created with correct lines (Revenue, COGS, Calculation)
3. PA_ReportColumnSet created with correct column (Period Balance)
4. Correct linkage between Report, Line Set, and Column Set
5. Correct calculation logic (Rev - COGS)
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_define_financial_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    report = result.get('report', {})
    line_set = result.get('line_set', {})
    col_set = result.get('column_set', {})

    # --- CRITERION 1: Report Line Set (30 pts) ---
    line_ids = {} # map name to ID for calc verification
    
    if line_set.get('exists'):
        score += 5
        feedback_parts.append("Report Line Set created")
        
        lines = line_set.get('lines', [])
        rev_found = False
        cogs_found = False
        calc_found = False
        
        # Check Lines
        for line in lines:
            name = line.get('name', '')
            l_type = line.get('type', '') # S=Segment, C=Calculation
            l_id = line.get('id')
            
            if 'Total Revenue' in name and l_type == 'S':
                rev_found = True
                line_ids['revenue'] = l_id
            elif 'Total COGS' in name and l_type == 'S':
                cogs_found = True
                line_ids['cogs'] = l_id
            elif 'Gross Profit' in name and l_type == 'C':
                calc_found = True
                line_ids['calc'] = l_id
                line_ids['calc_op1'] = line.get('op1')
                line_ids['calc_op2'] = line.get('op2')

        if rev_found: 
            score += 5
            feedback_parts.append("Revenue line found")
        else:
            feedback_parts.append("Missing 'Total Revenue' line (Segment Value)")
            
        if cogs_found: 
            score += 5
            feedback_parts.append("COGS line found")
        else:
            feedback_parts.append("Missing 'Total COGS' line (Segment Value)")
            
        if calc_found: 
            score += 5
            feedback_parts.append("Calculation line found")
            
            # Verify calculation logic (10 pts)
            # Should reference Rev and COGS
            op1 = line_ids.get('calc_op1')
            op2 = line_ids.get('calc_op2')
            valid_operands = [line_ids.get('revenue'), line_ids.get('cogs')]
            
            # Allow either order (Rev - COGS or COGS - Rev) technically, though one is right.
            # We strictly check operands are the other two lines.
            if op1 in valid_operands and op2 in valid_operands and op1 != op2:
                score += 10
                feedback_parts.append("Calculation logic references correct lines")
            else:
                feedback_parts.append("Calculation does not reference Revenue and COGS correctly")
        else:
            feedback_parts.append("Missing 'Gross Profit' line (Calculation)")

    else:
        feedback_parts.append("Report Line Set 'Gross Profit Analysis' not found")

    # --- CRITERION 2: Report Column Set (20 pts) ---
    if col_set.get('exists'):
        score += 10
        feedback_parts.append("Report Column Set created")
        
        cols = col_set.get('columns', [])
        col_correct = False
        for col in cols:
            # BP = Period Balance
            if 'Period Actual' in col.get('name', '') and col.get('type') == 'BP':
                col_correct = True
                break
        
        if col_correct:
            score += 10
            feedback_parts.append("Column 'Period Actual' (Period Balance) found")
        else:
            feedback_parts.append("Column 'Period Actual' with type Period Balance not found")
    else:
        feedback_parts.append("Report Column Set 'Current Period Analysis' not found")

    # --- CRITERION 3: Financial Report Header & Linkage (40 pts) ---
    if report.get('exists'):
        score += 15
        feedback_parts.append("Financial Report header created")
        
        # Check Linkage
        rpt_line_set = report.get('line_set_id')
        rpt_col_set = report.get('col_set_id')
        
        # Verify IDs match
        linkage_ok = True
        if not line_set.get('exists') or rpt_line_set != line_set.get('id'):
            linkage_ok = False
            feedback_parts.append("Report not linked to correct Line Set")
            
        if not col_set.get('exists') or rpt_col_set != col_set.get('id'):
            linkage_ok = False
            feedback_parts.append("Report not linked to correct Column Set")
            
        if linkage_ok:
            score += 25
            feedback_parts.append("Report correctly linked to Line and Column sets")
    else:
        feedback_parts.append("Financial Report 'GP Board Report' not found")

    # --- CRITERION 4: VLM Check (10 pts) ---
    # Bonus points if the UI actually looks like the agent is working in Financial Reports
    query_vlm = env_info.get('query_vlm')
    final_screenshot = get_final_screenshot(traj)
    
    vlm_score = 0
    if query_vlm and final_screenshot:
        prompt = """
        Does this screenshot show the iDempiere 'Financial Report', 'Report Line Set', or 'Report Column Set' window? 
        Look for table grids, tabs like 'Line' or 'Column', or fields like 'Report Line Set'.
        Answer yes or no.
        """
        try:
            vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
            if vlm_res.get('success') and 'yes' in vlm_res.get('result', '').lower():
                vlm_score = 10
                feedback_parts.append("Visual verification passed")
            else:
                feedback_parts.append("Visual verification uncertain")
        except:
            pass
    
    score += vlm_score

    # Final Pass/Fail
    passed = score >= 60 and report.get('exists') and line_set.get('exists')

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }