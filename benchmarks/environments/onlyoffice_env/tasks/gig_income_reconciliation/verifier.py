#!/usr/bin/env python3
"""
Verifier for Gig Income Reconciliation task

Checks that the agent correctly aggregated gig income data, calculated profit metrics,
and estimated self-employment taxes from messy notes.
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_gig_income_reconciliation(traj, env_info, task_info):
    """
    Verify gig income reconciliation spreadsheet.
    
    Expected data from notes:
    - Uber: $2535.70 total, 83 hours, $340 gas
    - DoorDash: $1872.95 total, 77 hours, $215 gas  
    - Instacart: $1746.80 total, 75 hours, $180 gas
    
    Calculated values:
    - Total earnings: $6155.45
    - Total hours: 235
    - Total gas: $735
    - Total profit: $5420.45
    - Tax owed (15.3%): $829.33
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/gig_income_analysis.xlsx"
    temp_dir = None
    
    try:
        # Create temp file for copying
        temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_gig_')
        temp_file_path = os.path.join(temp_dir, 'gig_income_analysis.xlsx')
        
        # Copy file from container
        try:
            copy_from_env(container_path, temp_file_path)
        except Exception as e:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Failed to copy spreadsheet from container: {str(e)}"
            }
        
        if not os.path.exists(temp_file_path):
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "❌ Spreadsheet file not found at expected location"
            }
            
        if os.path.getsize(temp_file_path) == 0:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "❌ Spreadsheet file is empty"
            }
        
        # Parse spreadsheet
        wb = parse_xlsx_file(temp_file_path)
        if not wb:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "❌ Could not parse spreadsheet file (may be corrupted)"
            }
        
        # Get the active sheet (or first sheet)
        sheet = wb.active
        feedback_parts = []
        score = 0.0
        
        # Expected values with tolerance for rounding
        expected = {
            'uber_earnings': 2535.70,
            'doordash_earnings': 1872.95,
            'instacart_earnings': 1746.80,
            'uber_hours': 83.0,
            'doordash_hours': 77.0,
            'instacart_hours': 75.0,
            'uber_gas': 340.0,
            'doordash_gas': 215.0,
            'instacart_gas': 180.0,
            'total_earnings': 6155.45,
            'total_hours': 235.0,
            'total_gas': 735.0,
            'total_profit': 5420.45,
            'tax_owed': 829.33
        }
        
        # Read all sheet data (first 50 rows, 15 columns should be plenty)
        data = get_sheet_data(wb, sheet.title, max_rows=50, max_cols=15)
        
        # Helper functions
        def safe_float(val):
            """Convert to float, handling None, strings, and errors"""
            if val is None:
                return None
            if isinstance(val, (int, float)):
                return float(val)
            if isinstance(val, str):
                # Remove $ , and other common formatting
                cleaned = re.sub(r'[\$,\s]', '', val)
                try:
                    return float(cleaned)
                except:
                    return None
            return None
        
        def find_values_in_sheet(keywords, exclude_keywords=None):
            """Find all numeric values in rows containing keywords"""
            found_values = []
            exclude_keywords = exclude_keywords or []
            
            for row_idx, row in enumerate(data):
                if not row:
                    continue
                    
                # Check if any cell in row contains keyword
                row_text = ' '.join([str(cell).lower() for cell in row if cell])
                
                has_keyword = any(kw.lower() in row_text for kw in keywords)
                has_exclude = any(ekw.lower() in row_text for ekw in exclude_keywords)
                
                if has_keyword and not has_exclude:
                    # Extract all numeric values from this row
                    for cell in row:
                        val = safe_float(cell)
                        if val is not None and val > 0:
                            found_values.append(val)
            
            return found_values
        
        def check_value_exists(target, tolerance_pct=2.0):
            """Check if a value (within tolerance) exists anywhere in the sheet"""
            tolerance = abs(target * tolerance_pct / 100.0)
            
            for row in data:
                for cell in row:
                    val = safe_float(cell)
                    if val is not None and abs(val - target) <= tolerance:
                        return True, val
            return False, None
        
        # Check 1: Three platforms mentioned (10 points)
        has_uber = any('uber' in str(cell).lower() for row in data for cell in row if cell)
        has_doordash = any('doordash' in str(cell).lower() or 'door dash' in str(cell).lower() 
                          for row in data for cell in row if cell)
        has_instacart = any('instacart' in str(cell).lower() or 'insta cart' in str(cell).lower() 
                           for row in data for cell in row if cell)
        
        platforms_found = sum([has_uber, has_doordash, has_instacart])
        if platforms_found == 3:
            score += 10
            feedback_parts.append("✅ All three platforms present (Uber, DoorDash, Instacart)")
        elif platforms_found == 2:
            score += 5
            feedback_parts.append(f"⚠️ Only 2/3 platforms found")
        else:
            feedback_parts.append(f"❌ Missing platforms (found {platforms_found}/3)")
        
        # Check 2: Uber earnings correct (~$2535.70) (12 points)
        uber_values = find_values_in_sheet(['uber'])
        found_uber_earnings = any(abs(v - expected['uber_earnings']) < 10 for v in uber_values)
        if found_uber_earnings:
            score += 12
            feedback_parts.append(f"✅ Uber earnings correct (~${expected['uber_earnings']:.2f})")
        else:
            feedback_parts.append(f"❌ Uber earnings incorrect (expected ~${expected['uber_earnings']:.2f})")
        
        # Check 3: DoorDash earnings correct (~$1872.95) (12 points)
        dd_values = find_values_in_sheet(['doordash', 'door dash'])
        found_dd_earnings = any(abs(v - expected['doordash_earnings']) < 10 for v in dd_values)
        if found_dd_earnings:
            score += 12
            feedback_parts.append(f"✅ DoorDash earnings correct (~${expected['doordash_earnings']:.2f})")
        else:
            feedback_parts.append(f"❌ DoorDash earnings incorrect (expected ~${expected['doordash_earnings']:.2f})")
        
        # Check 4: Instacart earnings correct (~$1746.80) (12 points)
        ic_values = find_values_in_sheet(['instacart', 'insta cart'])
        found_ic_earnings = any(abs(v - expected['instacart_earnings']) < 10 for v in ic_values)
        if found_ic_earnings:
            score += 12
            feedback_parts.append(f"✅ Instacart earnings correct (~${expected['instacart_earnings']:.2f})")
        else:
            feedback_parts.append(f"❌ Instacart earnings incorrect (expected ~${expected['instacart_earnings']:.2f})")
        
        # Check 5: Total hours calculated (235 hours) (10 points)
        exists, found_val = check_value_exists(expected['total_hours'], tolerance_pct=1.0)
        if exists:
            score += 10
            feedback_parts.append(f"✅ Total hours correct ({int(found_val)} hours)")
        else:
            feedback_parts.append(f"❌ Total hours not found (expected {int(expected['total_hours'])} hours)")
        
        # Check 6: Total earnings calculated (~$6155.45) (15 points)
        exists, found_val = check_value_exists(expected['total_earnings'], tolerance_pct=1.0)
        if exists:
            score += 15
            feedback_parts.append(f"✅ Total earnings correct (${found_val:.2f})")
        else:
            feedback_parts.append(f"❌ Total earnings not found (expected ${expected['total_earnings']:.2f})")
        
        # Check 7: Total gas expenses ($735) (10 points)
        exists, found_val = check_value_exists(expected['total_gas'], tolerance_pct=2.0)
        if exists:
            score += 10
            feedback_parts.append(f"✅ Total gas expenses correct (${found_val:.2f})")
        else:
            feedback_parts.append(f"❌ Total gas expenses not found (expected ${expected['total_gas']:.2f})")
        
        # Check 8: Total profit calculated (~$5420.45) (15 points)
        exists, found_val = check_value_exists(expected['total_profit'], tolerance_pct=1.5)
        if exists:
            score += 15
            feedback_parts.append(f"✅ Total profit calculated correctly (${found_val:.2f})")
        else:
            feedback_parts.append(f"❌ Total profit not found (expected ${expected['total_profit']:.2f})")
        
        # Check 9: Tax calculation (15.3% of profit = ~$829.33) (14 points)
        # Be more lenient here as they might calculate differently
        exists, found_val = check_value_exists(expected['tax_owed'], tolerance_pct=5.0)
        if exists:
            score += 14
            feedback_parts.append(f"✅ Estimated tax calculated correctly (${found_val:.2f})")
        else:
            # Check if any value in 800-900 range exists (partial credit)
            for row in data:
                for cell in row:
                    val = safe_float(cell)
                    if val and 800 <= val <= 900:
                        score += 7
                        feedback_parts.append(f"⚠️ Tax estimate in reasonable range (${val:.2f}), but not exact")
                        break
            else:
                feedback_parts.append(f"❌ Tax calculation not found (expected ~${expected['tax_owed']:.2f})")
        
        # Normalize score to 0-100
        score = min(score, 100)
        
        # Determine pass/fail (need 70% to pass)
        passed = score >= 70
        
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Verification complete. Passed: {passed}, Score: {score}")
        
        return {
            "passed": passed,
            "score": score / 100.0,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        if temp_dir:
            cleanup_temp_dir(temp_dir)