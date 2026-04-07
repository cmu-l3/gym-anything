#!/usr/bin/env python3
"""Verifier for museum_collection_logistics task."""

import sys
import os
import json
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_spreadsheet,
    cleanup_verification_temp
)
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_museum_logistics(traj, env_info, task_info):
    """Verify formula outputs, dashboard aggregations, and formatting."""
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Check general task execution parameters
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "moma_logistics.xlsx was not saved or not found."}
        
    if result.get('file_created_during_task', False):
        score += 10
        feedback_parts.append("File created during task (+10)")
    else:
        feedback_parts.append("Warning: File timestamp anomaly.")

    # Parse Excel file
    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/moma_logistics.xlsx", copy_from_env, file_format='xlsx'
    )

    if not success or wb is None:
        cleanup_verification_temp(temp_dir)
        return {"passed": False, "score": score, "feedback": f"Failed to open XLSX: {error}"}

    try:
        sheets = wb.sheetnames
        has_collection = "Collection" in sheets
        has_dashboard = "Logistics Dashboard" in sheets
        
        if has_collection and has_dashboard:
            score += 10
            feedback_parts.append("Required sheets present (+10)")
        else:
            feedback_parts.append(f"Missing sheets. Found: {sheets}")
            
        if has_collection:
            ws_coll = wb["Collection"]
            
            # Check Headers
            h_m = str(ws_coll.cell(row=1, column=13).value).strip()
            h_n = str(ws_coll.cell(row=1, column=14).value).strip()
            h_o = str(ws_coll.cell(row=1, column=15).value).strip()
            
            if h_m == "Crate_Type" and h_n == "Conservation_Flag" and h_o == "Handling_Category":
                score += 5
                feedback_parts.append("Headers match exactly (+5)")
            else:
                feedback_parts.append(f"Headers mismatch. Found: {h_m}, {h_n}, {h_o}")
                
            # Formatting checks (Row 1 Bold)
            is_bold = ws_coll.cell(row=1, column=1).font.bold if ws_coll.cell(row=1, column=1).font else False
            
            # Check AutoFilter
            has_autofilter = ws_coll.auto_filter is not None and ws_coll.auto_filter.ref is not None
            
            if is_bold:
                score += 5
                feedback_parts.append("Headers are bold (+5)")
            if has_autofilter:
                score += 5
                feedback_parts.append("AutoFilter applied (+5)")
                
            # Verify formulas mathematically (Data processing logic)
            m_correct, n_correct, o_correct = 0, 0, 0
            total_rows = 0
            
            # Reconstruct ground truth and calculate what should be in the dashboard
            gt_total = 0
            gt_oversize = 0
            gt_review = 0
            gt_heavy = 0
            gt_fragile = 0
            
            for row in range(2, ws_coll.max_row + 1):
                title = ws_coll.cell(row=row, column=1).value
                if title is None or str(title).strip() == "":
                    continue
                    
                total_rows += 1
                gt_total += 1
                
                # Fetch base data
                medium = str(ws_coll.cell(row=row, column=4).value or "")
                classification = str(ws_coll.cell(row=row, column=6).value or "")
                
                try:
                    h_val = float(ws_coll.cell(row=row, column=9).value or 0)
                except: h_val = 0
                try:
                    w_val = float(ws_coll.cell(row=row, column=10).value or 0)
                except: w_val = 0
                try:
                    weight_val = float(ws_coll.cell(row=row, column=12).value or 0)
                except: weight_val = 0
                
                # Expected logic
                exp_crate = "Oversize" if (h_val > 120 or w_val > 120) else "Standard"
                exp_cons = "Review" if "paper" in medium.lower() else "OK"
                exp_hand = "Heavy" if weight_val > 50 else ("Fragile" if classification == "Sculpture" else "Standard")
                
                # Aggregations
                if exp_crate == "Oversize": gt_oversize += 1
                if exp_cons == "Review": gt_review += 1
                if exp_hand == "Heavy": gt_heavy += 1
                if exp_hand == "Fragile": gt_fragile += 1
                
                # Actual
                act_crate = str(ws_coll.cell(row=row, column=13).value).strip()
                act_cons = str(ws_coll.cell(row=row, column=14).value).strip()
                act_hand = str(ws_coll.cell(row=row, column=15).value).strip()
                
                if act_crate == exp_crate: m_correct += 1
                if act_cons == exp_cons: n_correct += 1
                if act_hand == exp_hand: o_correct += 1
                
            if total_rows > 0:
                crate_acc = m_correct / total_rows
                cons_acc = n_correct / total_rows
                hand_acc = o_correct / total_rows
                
                if crate_acc > 0.95:
                    score += 15
                    feedback_parts.append("Crate logic correct (+15)")
                elif crate_acc > 0:
                    feedback_parts.append(f"Crate logic partial ({crate_acc:.0%})")
                    
                if cons_acc > 0.95:
                    score += 15
                    feedback_parts.append("Conservation logic correct (+15)")
                elif cons_acc > 0:
                    feedback_parts.append(f"Conservation logic partial ({cons_acc:.0%})")
                    
                if hand_acc > 0.95:
                    score += 15
                    feedback_parts.append("Handling logic correct (+15)")
                elif hand_acc > 0:
                    feedback_parts.append(f"Handling logic partial ({hand_acc:.0%})")
                    
            # Check Dashboard Aggregation
            if has_dashboard:
                ws_dash = wb["Logistics Dashboard"]
                dash_score = 0
                dash_points_per = 2
                
                # Helper to scan column A for a category and check column B
                def check_dashboard_val(expected_label, expected_count):
                    nonlocal dash_score
                    for r in range(1, 15):
                        lbl = str(ws_dash.cell(row=r, column=1).value or "").strip().lower()
                        if expected_label.lower() in lbl:
                            try:
                                val = int(float(ws_dash.cell(row=r, column=2).value or 0))
                                if val == expected_count:
                                    dash_score += dash_points_per
                                    return True
                            except:
                                pass
                    return False
                
                if check_dashboard_val("Total Items", gt_total): pass
                if check_dashboard_val("Oversize Crates", gt_oversize): pass
                if check_dashboard_val("Items for Review", gt_review): pass
                if check_dashboard_val("Heavy Items", gt_heavy): pass
                if check_dashboard_val("Fragile Items", gt_fragile): pass
                
                score += dash_score
                feedback_parts.append(f"Dashboard accuracy (+{dash_score}/10)")

        # VLM Trajectory Verification to ensure genuine use of WPS
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            
            vlm_prompt = """
            Look at this sequence of screenshots from an agent operating a desktop computer.
            Did the agent actively use WPS Spreadsheets to edit formulas, apply formatting, or organize sheets?
            Respond in JSON format:
            {
                "used_wps_spreadsheet": true/false,
                "reasoning": "Brief explanation"
            }
            """
            vlm_response = query_vlm(images=frames + [final] if final else frames, prompt=vlm_prompt)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("used_wps_spreadsheet", False):
                    score += 10
                    feedback_parts.append("VLM confirms genuine WPS usage (+10)")
                else:
                    feedback_parts.append("VLM did not detect WPS usage in trajectory.")
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error during verification: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)
        
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }