#!/usr/bin/env python3
"""
Verifier for Multimodal Commute Planner task
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_header_row(data, required_headers):
    """
    Find the row containing headers
    
    Args:
        data: 2D list of cell values
        required_headers: List of required header keywords
    
    Returns:
        Tuple of (row_index, header_mapping) or (None, None)
    """
    for row_idx, row in enumerate(data):
        row_lower = [str(cell).strip().lower() if cell else "" for cell in row]
        
        # Check if this row contains most required headers
        header_mapping = {}
        for req_header in required_headers:
            for col_idx, cell_text in enumerate(row_lower):
                if req_header in cell_text:
                    header_mapping[req_header] = col_idx
                    break
        
        # If we found most headers, this is likely the header row
        if len(header_mapping) >= len(required_headers) - 1:  # Allow one missing
            return row_idx, header_mapping
    
    return None, None


def extract_neighborhood_data(data, header_row_idx, header_mapping):
    """
    Extract neighborhood data from rows after header
    
    Returns:
        Dict of neighborhood -> {time, daily, monthly, backup, method}
    """
    neighborhoods_data = {}
    
    neighborhood_col = header_mapping.get("neighborhood")
    method_col = header_mapping.get("method", header_mapping.get("primary"))
    time_col = header_mapping.get("time")
    daily_col = header_mapping.get("daily", header_mapping.get("cost"))
    monthly_col = header_mapping.get("monthly")
    backup_col = header_mapping.get("backup")
    
    if neighborhood_col is None:
        return neighborhoods_data
    
    # Look at rows after header
    for row_idx in range(header_row_idx + 1, min(len(data), header_row_idx + 20)):
        row = data[row_idx]
        
        if len(row) <= neighborhood_col or not row[neighborhood_col]:
            continue
        
        neighborhood_name = str(row[neighborhood_col]).strip().lower()
        
        # Check if this row contains a neighborhood name
        matched_name = None
        if "riverside" in neighborhood_name:
            matched_name = "riverside"
        elif "oakmont" in neighborhood_name:
            matched_name = "oakmont"
        elif "downtown" in neighborhood_name:
            matched_name = "downtown"
        
        if not matched_name:
            continue
        
        # Extract values from this row
        try:
            time_val = float(row[time_col]) if time_col is not None and len(row) > time_col and row[time_col] else None
        except (ValueError, TypeError):
            time_val = None
        
        try:
            daily_val = float(str(row[daily_col]).replace('$', '').replace(',', '').strip()) if daily_col is not None and len(row) > daily_col and row[daily_col] else None
        except (ValueError, TypeError):
            daily_val = None
        
        try:
            monthly_val = float(str(row[monthly_col]).replace('$', '').replace(',', '').strip()) if monthly_col is not None and len(row) > monthly_col and row[monthly_col] else None
        except (ValueError, TypeError):
            monthly_val = None
        
        backup_val = str(row[backup_col]).strip() if backup_col is not None and len(row) > backup_col and row[backup_col] else ""
        method_val = str(row[method_col]).strip() if method_col is not None and len(row) > method_col and row[method_col] else ""
        
        neighborhoods_data[matched_name] = {
            "time": time_val,
            "daily": daily_val,
            "monthly": monthly_val,
            "backup": backup_val,
            "method": method_val
        }
    
    return neighborhoods_data


def search_for_recommendation(data):
    """
    Search entire spreadsheet for recommendation text
    
    Returns:
        True if recommendation found mentioning a neighborhood
    """
    recommendation_keywords = ["best", "recommend", "choose", "suggested", "option", "select"]
    neighborhood_names = ["riverside", "oakmont", "downtown"]
    
    for row in data:
        for cell in row:
            if cell:
                cell_text = str(cell).lower()
                has_keyword = any(kw in cell_text for kw in recommendation_keywords)
                has_neighborhood = any(name in cell_text for name in neighborhood_names)
                
                if has_keyword and has_neighborhood:
                    return True
    
    return False


def verify_multimodal_commute_planner(traj, env_info, task_info):
    """
    Verify multimodal commute planner spreadsheet
    
    Returns:
        dict with keys: passed (bool), score (float 0-1), feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "Copy function not available"
        }
    
    filepath = "/home/ga/Documents/Spreadsheets/commute_comparison.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_commute_')
    
    try:
        # Copy and parse
        success, workbook, error = copy_and_parse_document(
            filepath, copy_from_env, 'xlsx'
        )
        
        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Could not load spreadsheet: {error}"
            }
        
        # Get first sheet (or look for one with actual data)
        sheet_name = workbook.sheetnames[0]
        
        # Try all sheets if first one doesn't have data
        data = None
        for sheet_name in workbook.sheetnames:
            temp_data = get_sheet_data(workbook, sheet_name, max_rows=50, max_cols=15)
            if temp_data and len(temp_data) > 1:
                # Check if this sheet has actual table data (not just instructions)
                has_multiple_filled_rows = sum(1 for row in temp_data if any(cell for cell in row)) > 3
                if has_multiple_filled_rows:
                    data = temp_data
                    break
        
        if not data:
            # Fallback to first sheet
            sheet_name = workbook.sheetnames[0]
            data = get_sheet_data(workbook, sheet_name, max_rows=50, max_cols=15)
        
        if not data or len(data) < 2:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "Spreadsheet is empty or has insufficient data"
            }
        
        feedback_parts = []
        score_components = {}
        
        # === 1. Find and Check Header Row (15%) ===
        required_headers = ["neighborhood", "method", "time", "daily", "monthly", "backup"]
        header_row_idx, header_mapping = find_header_row(data, required_headers)
        
        if header_mapping and len(header_mapping) >= 5:
            feedback_parts.append(f"✅ Found header row with {len(header_mapping)}/6 required columns")
            score_components['headers'] = 0.15
        elif header_mapping and len(header_mapping) >= 4:
            feedback_parts.append(f"⚠️ Found header row but missing some columns ({len(header_mapping)}/6)")
            score_components['headers'] = 0.10
        else:
            feedback_parts.append("❌ Could not find proper header row with required columns")
            score_components['headers'] = 0.0
        
        if header_row_idx is None:
            # Can't proceed without headers
            total_score = score_components['headers']
            return {
                "passed": False,
                "score": total_score,
                "feedback": " | ".join(feedback_parts)
            }
        
        # === 2. Extract Neighborhood Data ===
        neighborhoods_data = extract_neighborhood_data(data, header_row_idx, header_mapping)
        
        # === 3. Check Three Neighborhoods Present (15%) ===
        required_neighborhoods = ["riverside", "oakmont", "downtown"]
        found_neighborhoods = [n for n in required_neighborhoods if n in neighborhoods_data]
        
        if len(found_neighborhoods) == 3:
            feedback_parts.append("✅ All three neighborhoods present (Riverside, Oakmont, Downtown)")
            score_components['neighborhoods'] = 0.15
        elif len(found_neighborhoods) == 2:
            feedback_parts.append(f"⚠️ Only 2 neighborhoods found: {', '.join(found_neighborhoods)}")
            score_components['neighborhoods'] = 0.10
        else:
            feedback_parts.append(f"❌ Missing neighborhoods (found: {', '.join(found_neighborhoods) if found_neighborhoods else 'none'})")
            score_components['neighborhoods'] = 0.0
        
        # === 4. Check Time Data (15%) ===
        expected_times = {"riverside": 45, "oakmont": 38, "downtown": 25}
        time_correct = 0
        time_errors = []
        
        for neighborhood, expected_time in expected_times.items():
            if neighborhood in neighborhoods_data:
                actual_time = neighborhoods_data[neighborhood]["time"]
                if actual_time is not None:
                    if abs(actual_time - expected_time) <= 2:
                        time_correct += 1
                    else:
                        time_errors.append(f"{neighborhood.capitalize()}: {actual_time} min (expected ~{expected_time})")
                else:
                    time_errors.append(f"{neighborhood.capitalize()}: missing time")
        
        if time_correct == 3:
            feedback_parts.append("✅ Time data correct for all neighborhoods")
            score_components['time'] = 0.15
        elif time_correct == 2:
            feedback_parts.append(f"⚠️ Time mostly correct ({time_correct}/3): {'; '.join(time_errors)}")
            score_components['time'] = 0.10
        else:
            feedback_parts.append(f"❌ Time data incorrect: {'; '.join(time_errors) if time_errors else 'all missing'}")
            score_components['time'] = 0.0
        
        # === 5. Check Daily Cost Data (15%) ===
        expected_daily = {"riverside": 4.50, "oakmont": 3.50, "downtown": 0}
        daily_correct = 0
        daily_errors = []
        
        for neighborhood, expected_cost in expected_daily.items():
            if neighborhood in neighborhoods_data:
                actual_cost = neighborhoods_data[neighborhood]["daily"]
                if actual_cost is not None:
                    if abs(actual_cost - expected_cost) <= 0.10:
                        daily_correct += 1
                    else:
                        daily_errors.append(f"{neighborhood.capitalize()}: ${actual_cost:.2f} (expected ${expected_cost})")
                else:
                    daily_errors.append(f"{neighborhood.capitalize()}: missing cost")
        
        if daily_correct == 3:
            feedback_parts.append("✅ Daily cost data correct for all neighborhoods")
            score_components['daily'] = 0.15
        elif daily_correct == 2:
            feedback_parts.append(f"⚠️ Daily cost mostly correct ({daily_correct}/3): {'; '.join(daily_errors)}")
            score_components['daily'] = 0.10
        else:
            feedback_parts.append(f"❌ Daily cost incorrect: {'; '.join(daily_errors) if daily_errors else 'all missing'}")
            score_components['daily'] = 0.0
        
        # === 6. Check Monthly Cost Calculations (25%) ===
        expected_monthly = {"riverside": 99.0, "oakmont": 77.0, "downtown": 0.0}
        monthly_correct = 0
        monthly_errors = []
        
        for neighborhood, expected_cost in expected_monthly.items():
            if neighborhood in neighborhoods_data:
                actual_cost = neighborhoods_data[neighborhood]["monthly"]
                if actual_cost is not None:
                    if abs(actual_cost - expected_cost) <= 5.0:
                        monthly_correct += 1
                    else:
                        monthly_errors.append(f"{neighborhood.capitalize()}: ${actual_cost:.2f} (expected ~${expected_cost})")
                else:
                    monthly_errors.append(f"{neighborhood.capitalize()}: missing monthly cost")
        
        if monthly_correct == 3:
            feedback_parts.append("✅ Monthly cost calculations correct (formulas working)")
            score_components['monthly'] = 0.25
        elif monthly_correct == 2:
            feedback_parts.append(f"⚠️ Monthly costs mostly correct ({monthly_correct}/3): {'; '.join(monthly_errors)}")
            score_components['monthly'] = 0.17
        elif monthly_correct == 1:
            feedback_parts.append(f"⚠️ Most monthly costs incorrect: {'; '.join(monthly_errors)}")
            score_components['monthly'] = 0.08
        else:
            feedback_parts.append(f"❌ Monthly costs missing or incorrect: {'; '.join(monthly_errors) if monthly_errors else 'all missing'}")
            score_components['monthly'] = 0.0
        
        # === 7. Check Backup Plans (10%) ===
        backup_present = 0
        backup_errors = []
        
        for neighborhood in required_neighborhoods:
            if neighborhood in neighborhoods_data:
                backup = neighborhoods_data[neighborhood]["backup"]
                if backup and len(backup) > 3:
                    backup_present += 1
                else:
                    backup_errors.append(f"{neighborhood.capitalize()}: missing backup")
        
        if backup_present == 3:
            feedback_parts.append("✅ Backup plans provided for all neighborhoods")
            score_components['backup'] = 0.10
        elif backup_present == 2:
            feedback_parts.append(f"⚠️ Most backup plans present ({backup_present}/3)")
            score_components['backup'] = 0.07
        elif backup_present == 1:
            feedback_parts.append(f"⚠️ Few backup plans present ({backup_present}/3)")
            score_components['backup'] = 0.03
        else:
            feedback_parts.append(f"❌ Backup plans missing: {'; '.join(backup_errors)}")
            score_components['backup'] = 0.0
        
        # === 8. Check Recommendation (5%) ===
        recommendation_found = search_for_recommendation(data)
        
        if recommendation_found:
            feedback_parts.append("✅ Recommendation provided")
            score_components['recommendation'] = 0.05
        else:
            feedback_parts.append("⚠️ No clear recommendation found")
            score_components['recommendation'] = 0.0
        
        # === Calculate final score ===
        total_score = sum(score_components.values())
        passed = total_score >= 0.70  # 70% threshold
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": total_score,
            "feedback": feedback
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)
