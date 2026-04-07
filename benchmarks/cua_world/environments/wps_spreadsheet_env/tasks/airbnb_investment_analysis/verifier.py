#!/usr/bin/env python3
"""Verifier for airbnb_investment_analysis task."""

import sys
import os
import json
import logging
import tempfile

# Insert path to access wps_verification_utils
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
try:
    from wps_verification_utils import (
        copy_and_parse_spreadsheet,
        cleanup_verification_temp,
        vlm_verify_screenshot,
    )
except ImportError:
    logging.error("Failed to import wps_verification_utils")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_airbnb_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata exported via script
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not export_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file airbnb_analysis.xlsx not found."}

    # Fetch and parse the workbook
    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/airbnb_analysis.xlsx", copy_from_env, file_format='xlsx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to open spreadsheet: {error}"}

    try:
        score = 0
        feedback_parts = []
        
        # 1. File Output & Sheets (10 pts)
        sheets = wb.sheetnames
        has_listings = "Listings" in sheets
        has_analysis = "Neighborhood Analysis" in sheets
        
        if has_listings and has_analysis:
            score += 10
            feedback_parts.append("Sheets correctly formatted")
        else:
            feedback_parts.append(f"Missing required sheets. Found: {sheets}")
            
        if not has_listings or not has_analysis:
            # Terminate early if primary structure fails
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
            
        listings_ws = wb["Listings"]
        analysis_ws = wb["Neighborhood Analysis"]
        
        # Resolve column indices in Listings
        headers = {str(cell.value).strip().lower(): idx for idx, cell in enumerate(listings_ws[1]) if cell.value}
        
        price_col = headers.get('price')
        reviews_col = headers.get('reviews_per_month')
        numeric_price_col = None
        revenue_col = None
        
        # Find numeric/revenue columns dynamically to account for varying casing
        for name, idx in headers.items():
            if 'numeric' in name:
                numeric_price_col = idx
            elif 'revenue' in name:
                revenue_col = idx
                
        # 2. Data Cleaning (Numeric Price) (20 pts)
        if numeric_price_col is not None and price_col is not None:
            correct_cleaning = 0
            samples = 0
            for row_idx in range(2, min(20, listings_ws.max_row + 1)):
                price_val = listings_ws[row_idx][price_col].value
                num_val = listings_ws[row_idx][numeric_price_col].value
                
                if price_val and isinstance(price_val, str):
                    try:
                        expected = float(price_val.replace('$', '').replace(',', ''))
                        if num_val is not None and abs(float(num_val) - expected) < 0.01:
                            correct_cleaning += 1
                    except ValueError:
                        pass
                samples += 1
                
            if samples > 0 and correct_cleaning / samples >= 0.8:
                score += 20
                feedback_parts.append("Data cleaning formula/logic correct")
            else:
                feedback_parts.append("Data cleaning failed")
        else:
            feedback_parts.append("Numeric_Price column missing")
            
        # 3. Revenue Formula (15 pts)
        if revenue_col is not None and numeric_price_col is not None and reviews_col is not None:
            formula_used = False
            
            for row_idx in range(2, min(50, listings_ws.max_row + 1)):
                rev_cell = listings_ws[row_idx][revenue_col]
                
                if rev_cell.data_type == 'f' or (isinstance(rev_cell.value, str) and str(rev_cell.value).startswith('=')):
                    formula_used = True
                    break
            
            if formula_used:
                score += 15
                feedback_parts.append("Revenue formulas implemented")
            else:
                feedback_parts.append("Revenue formula NOT detected")
        else:
            feedback_parts.append("Revenue column missing")
            
        # 4. Unique Neighborhoods (10 pts)
        analysis_headers = {str(cell.value).strip().lower(): idx for idx, cell in enumerate(analysis_ws[1]) if cell.value}
        nh_col = 0
        for name, idx in analysis_headers.items():
            if 'neighborhood' in name or 'neighbourhood' in name:
                nh_col = idx
                break
                
        summary_nhs = set()
        for row_idx in range(2, analysis_ws.max_row + 1):
            val = analysis_ws[row_idx][nh_col].value
            if val:
                summary_nhs.add(str(val).strip())
                
        if len(summary_nhs) >= 5:
            score += 10
            feedback_parts.append(f"Found deduplicated neighborhoods ({len(summary_nhs)})")
        else:
            feedback_parts.append("Unique neighborhoods list missing/incomplete")
            
        # 5. Count & 6. Revenue Aggregation (30 pts combined)
        has_countif = False
        has_avgif = False
        
        for row_idx in range(2, min(10, analysis_ws.max_row + 1)):
            for col_idx in range(1, min(5, analysis_ws.max_column)): 
                cell = analysis_ws[row_idx][col_idx]
                if cell.data_type == 'f' or (isinstance(cell.value, str) and str(cell.value).startswith('=')):
                    val = str(cell.value).upper()
                    if 'COUNTIF' in val:
                        has_countif = True
                    if 'AVERAGEIF' in val:
                        has_avgif = True
                        
        if has_countif:
            score += 15
            feedback_parts.append("COUNTIF correctly applied")
        else:
            feedback_parts.append("COUNTIF missing")
            
        if has_avgif:
            score += 15
            feedback_parts.append("AVERAGEIF correctly applied")
        else:
            feedback_parts.append("AVERAGEIF missing")
            
        # 7. Sorting & Formatting via VLM (15 pts combined)
        vlm_result = vlm_verify_screenshot(env_info, traj, '''
Analyze this WPS Spreadsheet screenshot. Answer in JSON:
{
    "is_sorted_descending": true/false,
    "has_color_scale": true/false
}
Does the spreadsheet show:
1. The summary table sorted in descending order (highest revenue values at the top)?
2. A color scale conditional formatting applied to the Avg Revenue column (e.g., green representing high values, red representing low)?
''')
        
        if vlm_result:
            if vlm_result.get("is_sorted_descending"):
                score += 10
                feedback_parts.append("Descending sort verified")
            else:
                feedback_parts.append("Sort order incorrect/missing")
                
            if vlm_result.get("has_color_scale"):
                score += 5
                feedback_parts.append("Color scale verified")
            else:
                feedback_parts.append("Color scale missing")
        else:
            # Fallback for headless testing
            if hasattr(analysis_ws, 'conditional_formatting') and analysis_ws.conditional_formatting:
                if len(analysis_ws.conditional_formatting._cf_rules) > 0:
                    score += 5
                    feedback_parts.append("Conditional formatting detected (fallback)")
            
        passed = score >= 70
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)