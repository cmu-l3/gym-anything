#!/usr/bin/env python3
"""
Verifier for create_pipeline_report task.

VERIFICATION METRICS:
1. Report Existence & Name (20 pts)
2. Report Type & Primary Module (20 pts)
3. Columns Selected (15 pts)
4. Group By Confguration (15 pts)
5. Conditions/Filters Configuration (15 pts)
6. VLM Trajectory Check (15 pts) - Ensures workflow was executed
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying if an AI agent successfully created a report in Vtiger CRM.

Look at these trajectory screenshots and the final screenshot.
Did the agent use the Reports module to create or edit a report?
Specifically, look for evidence of navigating the report builder (tabs for Report Details, Columns, Filters, etc.) and interacting with report settings.

Respond strictly in JSON format:
{
    "interacted_with_reports_module": true/false,
    "navigated_report_wizard": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what is seen in the screenshots"
}
"""

def verify_create_pipeline_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Read metadata expectations
    metadata = task_info.get('metadata', {})
    expected_module = metadata.get('expected_module', 'Potentials').lower()
    expected_columns = metadata.get('expected_columns', ['potentialname', 'amount', 'sales_stage', 'closingdate'])

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    report_found = result.get('report_found', False)
    newly_created = result.get('newly_created', False)
    
    # 1. Report Existence (Anti-Gaming Check included)
    if report_found and newly_created:
        score += 20
        feedback_parts.append("✅ New report 'Q4 Pipeline Summary' successfully created")
    elif report_found:
        feedback_parts.append("❌ Report found, but it was not created during this task (pre-existing)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    else:
        feedback_parts.append("❌ Target report 'Q4 Pipeline Summary' not found in database")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Report Type & Module
    r_type = result.get('report_type', '').lower()
    r_module = result.get('primary_module', '').lower()
    
    if r_type == 'summary':
        score += 10
        feedback_parts.append("✅ Report type is Summary")
    else:
        feedback_parts.append(f"❌ Incorrect report type: {r_type} (expected summary)")
        
    if r_module == expected_module:
        score += 10
        feedback_parts.append(f"✅ Primary module is {expected_module.title()}")
    else:
        feedback_parts.append(f"❌ Incorrect module: {r_module} (expected {expected_module})")

    # 3. Columns Selected
    r_columns = result.get('columns', '').lower()
    matched_columns = 0
    for col in expected_columns:
        if col in r_columns:
            matched_columns += 1
            
    if matched_columns >= 4:
        score += 15
        feedback_parts.append("✅ All expected columns selected")
    elif matched_columns >= 2:
        score += 7
        feedback_parts.append(f"⚠️ Partial columns selected ({matched_columns}/{len(expected_columns)})")
    else:
        feedback_parts.append("❌ Required columns missing")

    # 4. Group By Confguration
    r_group_by = result.get('group_by', '').lower()
    if 'sales_stage' in r_group_by:
        score += 15
        feedback_parts.append("✅ Report grouped by Sales Stage")
    else:
        feedback_parts.append("❌ Report grouping missing or incorrect")

    # 5. Conditions/Filters Configuration
    cond_basic = result.get('conditions', '').lower()
    cond_adv = result.get('conditions_adv', '').lower()
    all_conds = cond_basic + " || " + cond_adv
    
    # Looking for 'amount', a greater-than comparator (often 'g' or 'greater than' in Vtiger), and '5000'
    if 'amount' in all_conds and '5000' in all_conds:
        # Vtiger uses 'g' or 'h' for greater than in the DB, just verify presence of the fields/values
        score += 15
        feedback_parts.append("✅ Amount filter condition > 5000 applied")
    else:
        feedback_parts.append("❌ Amount > 5000 filter missing or incorrect")

    # 6. VLM Verification
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            images = frames + [final_frame] if final_frame else frames
            
            if images:
                vlm_result = query_vlm(images=images, prompt=VLM_PROMPT)
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    if parsed.get('interacted_with_reports_module') and parsed.get('navigated_report_wizard'):
                        score += 15
                        feedback_parts.append("✅ VLM verified interaction with Report Wizard")
                    else:
                        feedback_parts.append("❌ VLM did not observe Report Wizard workflow")
                else:
                    feedback_parts.append("⚠️ VLM evaluation failed")
            else:
                feedback_parts.append("⚠️ No screenshots available for VLM")
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        feedback_parts.append(f"⚠️ VLM verification error: {e}")

    # Final Evaluation
    # Key criteria: Report must exist, be a summary, and be on Potentials
    key_criteria_met = report_found and newly_created and (r_type == 'summary') and (r_module == expected_module)
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }