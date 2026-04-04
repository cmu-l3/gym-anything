#!/usr/bin/env python3
"""
Verifier for Legacy POS Rescue task
Comprehensive validation of data cleaning, deduplication, and VIP identification
"""

import sys
import os
import re
import logging
from collections import defaultdict

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    cleanup_verification_temp,
    parse_csv_file
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_name_for_comparison(name):
    """Normalize name for fuzzy duplicate detection"""
    if not name:
        return ""
    # Remove punctuation, convert to lowercase, remove extra spaces
    normalized = re.sub(r'[^\w\s]', '', str(name).lower())
    normalized = ' '.join(normalized.split())
    # Sort words to catch "John Smith" vs "Smith John"
    words = sorted(normalized.split())
    return ' '.join(words)


def parse_amount(amount_str):
    """Extract numeric value from currency string"""
    if isinstance(amount_str, (int, float)):
        return float(amount_str)
    if not amount_str:
        return 0.0
    # Remove currency symbols and text
    cleaned = re.sub(r'[^\d\.]', '', str(amount_str))
    try:
        return float(cleaned) if cleaned else 0.0
    except:
        return 0.0


def is_date_standardized(date_str):
    """Check if date matches YYYY-MM-DD format"""
    if not date_str:
        return False
    pattern = r'^\d{4}-\d{2}-\d{2}$'
    return bool(re.match(pattern, str(date_str)))


def is_name_standardized(name):
    """Check if name is in Title Case and properly trimmed"""
    if not name:
        return False
    name_str = str(name)
    # Check no leading/trailing spaces
    if name_str != name_str.strip():
        return False
    # Check Title Case (first letter of each word capitalized)
    words = name_str.split()
    for word in words:
        if not word:
            continue
        if word[0].islower():
            return False
        if len(word) > 1 and word[1:].isupper():
            return False
    return True


def verify_legacy_pos_rescue(traj, env_info, task_info):
    """
    Verify legacy POS rescue task completion.
    
    Checks:
    1. Duplicates removed (8-15 customers deduplicated)
    2. Names standardized (Title Case, trimmed)
    3. Dates uniform (YYYY-MM-DD format)
    4. Amounts clean (numeric, no currency symbols)
    5. CLV calculated correctly
    6. VIP logic correct (top 20% by spending)
    7. Export format compliance
    8. Data preserved (revenue matches)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # First, parse the original file to establish baseline
    original_path = "/home/ga/Documents/old_pos_export.csv"
    success_orig, original_data, error_orig, temp_dir_orig = copy_and_parse_spreadsheet(
        original_path,
        copy_from_env,
        file_format='csv'
    )
    
    if not success_orig:
        logger.warning(f"Could not load original file for comparison: {error_orig}")
        original_data = None
    
    # Try to load cleaned file (multiple possible names)
    cleaned_path_options = [
        "/home/ga/Documents/cleaned_customer_data.csv",
        "/home/ga/Documents/cleaned_customer_data.ods",
        "/home/ga/Documents/old_pos_export.csv",  # In case they modified in place
        "/home/ga/Documents/old_pos_export.ods"
    ]
    
    success = False
    cleaned_data = None
    temp_dir_cleaned = None
    
    for path in cleaned_path_options:
        file_format = 'ods' if path.endswith('.ods') else 'csv'
        success, cleaned_data, error, temp_dir_cleaned = copy_and_parse_spreadsheet(
            path,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"Found cleaned data at: {path}")
            break
    
    if not success:
        cleanup_verification_temp(temp_dir_orig)
        return {"passed": False, "score": 0, "feedback": f"Failed to load cleaned file: {error}"}
    
    try:
        # Get sheet data
        original_sheet = None
        if original_data:
            original_sheet_name = list(original_data['sheets'].keys())[0]
            original_sheet = original_data['sheets'][original_sheet_name]
        
        cleaned_sheet_name = list(cleaned_data['sheets'].keys())[0]
        cleaned_sheet = cleaned_data['sheets'][cleaned_sheet_name]
        
        criteria_passed = 0
        total_criteria = 8
        feedback_parts = []
        
        # Extract data from cleaned sheet
        cleaned_rows = []
        for row in cleaned_sheet:
            if not row:
                continue
            row_data = {}
            for i, cell in enumerate(row):
                value = cell.get('value') if isinstance(cell, dict) else cell
                if i == 0:
                    row_data['col0'] = value
                elif i == 1:
                    row_data['col1'] = value
                elif i == 2:
                    row_data['col2'] = value
                elif i == 3:
                    row_data['col3'] = value
                elif i == 4:
                    row_data['col4'] = value
                elif i == 5:
                    row_data['col5'] = value
            if any(row_data.values()):
                cleaned_rows.append(row_data)
        
        # Skip header row
        if cleaned_rows:
            cleaned_rows = cleaned_rows[1:]
        
        # Criterion 1: Check duplicate reduction
        duplicates_removed = False
        if original_sheet:
            # Count unique normalized names in original
            original_normalized = set()
            for row in original_sheet[1:]:  # Skip header
                if row and len(row) > 0:
                    name_cell = row[0]
                    name = name_cell.get('value') if isinstance(name_cell, dict) else name_cell
                    if name:
                        original_normalized.add(normalize_name_for_comparison(name))
            
            # Count unique names in cleaned (look for CleanedName column)
            cleaned_unique = set()
            for row_data in cleaned_rows:
                # Check multiple columns for cleaned name
                for col_key in ['col0', 'col1', 'col2']:
                    name = row_data.get(col_key)
                    if name and isinstance(name, str) and len(name) > 2:
                        cleaned_unique.add(normalize_name_for_comparison(name))
                        break
            
            original_count = len(original_normalized)
            cleaned_count = len(cleaned_unique)
            reduction = original_count - cleaned_count
            
            if 8 <= reduction <= 20:  # Allow some flexibility
                criteria_passed += 1
                duplicates_removed = True
                feedback_parts.append(f"✅ Duplicates removed: {reduction} customers deduplicated ({original_count}→{cleaned_count})")
            else:
                feedback_parts.append(f"❌ Deduplication issue: {reduction} removed (expected 8-20), original={original_count}, cleaned={cleaned_count}")
        else:
            feedback_parts.append("⚠️ Cannot verify deduplication (original file unavailable)")
        
        # Criterion 2: Check name standardization
        names_standardized = True
        non_standard_names = []
        for i, row_data in enumerate(cleaned_rows[:10]):  # Check first 10
            for col_key in ['col0', 'col1']:
                name = row_data.get(col_key)
                if name and isinstance(name, str) and len(name) > 2:
                    if not is_name_standardized(name):
                        names_standardized = False
                        non_standard_names.append(name)
                    break
        
        if names_standardized:
            criteria_passed += 1
            feedback_parts.append("✅ Names standardized (Title Case, trimmed)")
        else:
            feedback_parts.append(f"❌ Names not standardized: {non_standard_names[:3]}")
        
        # Criterion 3: Check date format standardization
        dates_standardized = True
        non_standard_dates = []
        for i, row_data in enumerate(cleaned_rows[:10]):  # Check first 10
            for col_key in ['col2', 'col3']:
                date = row_data.get(col_key)
                if date and str(date).count('-') >= 2:  # Likely a date
                    if not is_date_standardized(date):
                        dates_standardized = False
                        non_standard_dates.append(date)
                    break
        
        if dates_standardized and len(non_standard_dates) == 0:
            criteria_passed += 1
            feedback_parts.append("✅ Dates standardized (YYYY-MM-DD format)")
        else:
            feedback_parts.append(f"❌ Dates not standardized: {non_standard_dates[:3]}")
        
        # Criterion 4: Check amounts are numeric (no currency symbols)
        amounts_clean = True
        non_numeric_amounts = []
        amount_values = []
        for i, row_data in enumerate(cleaned_rows[:20]):  # Check first 20
            for col_key in ['col3', 'col4']:
                amount = row_data.get(col_key)
                if amount is not None:
                    # Check if it's numeric
                    try:
                        float_val = float(amount)
                        amount_values.append(float_val)
                        # Check it's not a string with symbols
                        if isinstance(amount, str) and ('$' in amount or 'USD' in amount):
                            amounts_clean = False
                            non_numeric_amounts.append(amount)
                        break
                    except (ValueError, TypeError):
                        if str(amount).strip():  # Not empty
                            amounts_clean = False
                            non_numeric_amounts.append(amount)
                        break
        
        if amounts_clean:
            criteria_passed += 1
            feedback_parts.append("✅ Amounts clean (numeric, no currency symbols)")
        else:
            feedback_parts.append(f"❌ Amounts not clean: {non_numeric_amounts[:3]}")
        
        # Criterion 5: Check CLV calculation (simplified check)
        # Look for patterns suggesting aggregation was done
        clv_calculated = False
        if len(cleaned_rows) < len(original_sheet) - 10:  # Significant row reduction suggests aggregation
            clv_calculated = True
            criteria_passed += 1
            feedback_parts.append("✅ Customer data aggregated (CLV calculation implied)")
        else:
            # Check if there are SUMIF-like patterns or unique customer rows
            unique_customers_in_cleaned = set()
            for row_data in cleaned_rows:
                for col_key in ['col0', 'col1']:
                    name = row_data.get(col_key)
                    if name and isinstance(name, str) and len(name) > 2:
                        unique_customers_in_cleaned.add(normalize_name_for_comparison(name))
                        break
            
            if len(unique_customers_in_cleaned) < len(cleaned_rows) * 0.8:  # Less than 80% unique suggests aggregation
                clv_calculated = True
                criteria_passed += 1
                feedback_parts.append("✅ CLV calculation detected")
            else:
                feedback_parts.append("❌ CLV calculation not evident (transactions not aggregated)")
        
        # Criterion 6: Check VIP logic (look for VIP_Status column with VIP and Regular values)
        vip_logic_correct = False
        vip_count = 0
        regular_count = 0
        for row_data in cleaned_rows:
            for col_key in ['col4', 'col5']:
                status = row_data.get(col_key)
                if status:
                    status_str = str(status).strip().upper()
                    if 'VIP' in status_str:
                        vip_count += 1
                    elif 'REGULAR' in status_str or 'NORMAL' in status_str:
                        regular_count += 1
        
        total_with_status = vip_count + regular_count
        if total_with_status > 0:
            vip_percentage = vip_count / total_with_status
            # Top 20% means VIP should be around 15-25% (allowing some tolerance)
            if 0.15 <= vip_percentage <= 0.30:
                vip_logic_correct = True
                criteria_passed += 1
                feedback_parts.append(f"✅ VIP logic correct: {vip_count} VIP, {regular_count} Regular ({vip_percentage*100:.1f}% VIP)")
            else:
                feedback_parts.append(f"❌ VIP percentage off: {vip_percentage*100:.1f}% (expected ~20%)")
        else:
            feedback_parts.append("❌ VIP_Status column not found or empty")
        
        # Criterion 7: Check export format (required columns present)
        format_compliant = False
        # Check if we have expected number of columns (at least 5)
        max_cols = max(len([k for k, v in row_data.items() if v is not None]) for row_data in cleaned_rows[:5])
        if max_cols >= 5:
            format_compliant = True
            criteria_passed += 1
            feedback_parts.append(f"✅ Export format compliant ({max_cols} columns)")
        else:
            feedback_parts.append(f"❌ Export format incomplete ({max_cols} columns, expected ≥5)")
        
        # Criterion 8: Check data preservation (revenue sum matches)
        data_preserved = False
        if original_sheet:
            # Sum original amounts
            original_total = 0.0
            for row in original_sheet[1:]:
                if len(row) > 2:
                    amount_cell = row[2]
                    amount = amount_cell.get('value') if isinstance(amount_cell, dict) else amount_cell
                    original_total += parse_amount(amount)
            
            # Sum cleaned amounts
            cleaned_total = 0.0
            for row_data in cleaned_rows:
                for col_key in ['col3', 'col4']:
                    amount = row_data.get(col_key)
                    if amount is not None:
                        try:
                            cleaned_total += float(amount)
                            break
                        except:
                            pass
            
            if original_total > 0:
                difference_pct = abs(original_total - cleaned_total) / original_total
                if difference_pct <= 0.02:  # Within 2% tolerance
                    data_preserved = True
                    criteria_passed += 1
                    feedback_parts.append(f"✅ Data preserved: ${original_total:.2f} → ${cleaned_total:.2f}")
                else:
                    feedback_parts.append(f"❌ Revenue mismatch: ${original_total:.2f} → ${cleaned_total:.2f} ({difference_pct*100:.1f}% diff)")
            else:
                feedback_parts.append("⚠️ Cannot verify revenue preservation (original amounts not parsed)")
        else:
            feedback_parts.append("⚠️ Cannot verify revenue preservation (original file unavailable)")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "duplicates_removed": duplicates_removed,
                "names_standardized": names_standardized,
                "dates_standardized": dates_standardized,
                "amounts_clean": amounts_clean,
                "clv_calculated": clv_calculated,
                "vip_logic_correct": vip_logic_correct,
                "format_compliant": format_compliant,
                "data_preserved": data_preserved
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    
    finally:
        cleanup_verification_temp(temp_dir_orig)
        cleanup_verification_temp(temp_dir_cleaned)
