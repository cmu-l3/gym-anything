#!/usr/bin/env python3
import os
import sys
import json
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_spreadsheet,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_call_center_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract JSON export
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Spreadsheet not found"}

    if not result.get('file_created_during_task'):
        return {"passed": False, "score": 0, "feedback": "Spreadsheet was not modified during task (anti-gaming check failed)"}

    # Extract and parse spreadsheet
    success, wb_formulas, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/call_center_data.xlsx", copy_from_env, file_format='xlsx'
    )
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse spreadsheet: {error}"}

    score = 0
    feedback_parts = []
    
    try:
        if "Performance_Summary" not in wb_formulas.sheetnames:
            return {"passed": False, "score": 0, "feedback": "Sheet 'Performance_Summary' not found"}

        score += 5
        feedback_parts.append("Sheet 'Performance_Summary' exists")

        ws_form = wb_formulas["Performance_Summary"]

        # 1. Check headers
        headers = []
        for c in range(1, 8):
            val = ws_form.cell(row=1, column=c).value
            headers.append(str(val).strip() if val else "")
            
        expected_headers = ["Agent_ID", "Agent_Name", "Total_Calls", "AHT_Minutes", "FCR_Percent", "Avg_CSAT", "Bonus_Eligible"]

        header_matches = sum([1 for i in range(7) if expected_headers[i].lower() in headers[i].lower()])
        if header_matches >= 6:
            score += 5
            feedback_parts.append("Headers match")
        else:
            feedback_parts.append(f"Headers mismatch: {headers}")

        # Find first row with data formulas
        data_row = 2
        for r in range(2, 22):
            if ws_form.cell(row=r, column=1).value is not None:
                cell_b = ws_form.cell(row=r, column=2)
                if cell_b.data_type == 'f' or (isinstance(cell_b.value, str) and cell_b.value.startswith('=')):
                    data_row = r
                    break

        def get_f(col):
            cell = ws_form.cell(row=data_row, column=col)
            if cell.data_type == 'f':
                return str(cell.value).upper()
            elif isinstance(cell.value, str) and cell.value.startswith('='):
                return cell.value.upper()
            return ""

        f_name = get_f(2)
        f_calls = get_f(3)
        f_aht = get_f(4)
        f_fcr = get_f(5)
        f_csat = get_f(6)
        f_bonus = get_f(7)

        # 2. VLOOKUP Logic
        if any(x in f_name for x in ['VLOOKUP', 'XLOOKUP', 'INDEX', 'FILTER', 'LOOKUP']):
            score += 10
            feedback_parts.append("Agent_Name formula found")
        else:
            feedback_parts.append("Agent_Name formula incorrect")

        # 3. Basic Aggregation Logic
        if any(x in f_calls for x in ['COUNTIF', 'SUMPRODUCT', 'FILTER']):
            score += 10
            feedback_parts.append("Total_Calls formula found")
        else:
            feedback_parts.append("Total_Calls formula incorrect")

        if any(x in f_aht for x in ['AVERAGE', 'SUM', 'PRODUCT']) and ('60' in f_aht):
            score += 10
            feedback_parts.append("AHT_Minutes formula found")
        else:
            feedback_parts.append("AHT_Minutes formula incorrect/missing /60")

        # 4. FCR Logic
        if any(x in f_fcr for x in ['COUNTIFS', 'SUMPRODUCT', 'FILTER']) or ('/' in f_fcr and 'COUNTIF' in f_fcr):
            score += 20
            feedback_parts.append("FCR_Percent formula found")
        else:
            feedback_parts.append("FCR_Percent formula incorrect")

        # 5. CSAT Logic
        if any(x in f_csat for x in ['AVERAGE', 'SUMPRODUCT', 'FILTER']):
            score += 15
            feedback_parts.append("Avg_CSAT formula found")
        else:
            feedback_parts.append("Avg_CSAT formula incorrect")

        # 6. Bonus Rules Logic
        if 'IF' in f_bonus and ('AND' in f_bonus or '*' in f_bonus):
            score += 15
            feedback_parts.append("Bonus_Eligible formula found")
        else:
            feedback_parts.append("Bonus_Eligible formula incorrect")

        # 7. Conditional Formatting Logic
        has_cf = False
        try:
            if hasattr(ws_form, 'conditional_formatting') and ws_form.conditional_formatting:
                for range_string in ws_form.conditional_formatting._cf_rules.keys():
                    if 'D' in range_string:
                        has_cf = True
                        break
        except Exception as e:
            logger.warning(f"Error checking conditional formatting: {e}")

        if has_cf:
            score += 10
            feedback_parts.append("Conditional formatting on AHT column found")
        else:
            feedback_parts.append("Conditional formatting missing")

        passed = score >= 80

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error during verification: {e}"}
    finally:
        cleanup_verification_temp(temp_dir)