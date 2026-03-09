#!/usr/bin/env python3
"""
Verifier for Lab Notebook Digitization task

This verifier checks that a biology student's handwritten lab notebook data
has been properly digitized into a clean, analysis-ready spreadsheet.
"""

import sys
import os
import logging
import tempfile
import re
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_string(s):
    """Normalize string for comparison (lowercase, strip whitespace)"""
    if s is None:
        return ""
    return str(s).lower().strip()


def is_valid_date_format(date_val):
    """Check if date is in YYYY-MM-DD format or a proper date object"""
    if date_val is None:
        return False
    
    # Check if it's a datetime object
    if hasattr(date_val, 'year') and hasattr(date_val, 'month'):
        return True
    
    # Check if it's a string in YYYY-MM-DD format
    date_str = str(date_val).strip()
    pattern = r'^\d{4}-\d{2}-\d{2}$'
    if re.match(pattern, date_str):
        # Verify it's a valid date
        try:
            datetime.strptime(date_str, '%Y-%m-%d')
            return True
        except ValueError:
            return False
    
    return False


def is_march_2024_date(date_val):
    """Check if date is in March 2024"""
    if hasattr(date_val, 'year') and hasattr(date_val, 'month'):
        return date_val.year == 2024 and date_val.month == 3
    
    date_str = str(date_val).strip()
    return '2024-03-' in date_str


def verify_lab_notebook_digitization(traj, env_info, task_info):
    """
    Verify lab notebook digitization task
    
    Checks:
    1. File exists and is valid XLSX
    2. Has proper column headers (date, treatment, mean_height)
    3. Dates standardized to YYYY-MM-DD format
    4. Treatment codes standardized (WW, DS)
    5. Unit conversion (mm to cm - values in correct range)
    6. Mean calculations present and reasonable
    7. Missing data handled appropriately
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    target_file = "/home/ga/Documents/lab_notebook_digitization/growth_data_cleaned.xlsx"
    
    # Initialize scoring
    score = 0
    max_score = 100
    feedback = []
    
    # Copy and parse the file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.xlsx')
    temp_path = temp_file.name
    temp_file.close()
    
    try:
        copy_from_env(target_file, temp_path)
        
        if not os.path.exists(temp_path) or os.path.getsize(temp_path) == 0:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Output file not found or empty: {target_file}"
            }
        
        workbook = parse_xlsx_file(temp_path)
        if not workbook:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "❌ Could not parse XLSX file - file may be corrupted"
            }
        
        score += 5  # Valid file format
        feedback.append("✅ File exists and is valid XLSX")
        
        # Get first sheet
        sheet_name = workbook.sheetnames[0]
        sheet = workbook[sheet_name]
        sheet_data = get_sheet_data(workbook, sheet_name, max_rows=50, max_cols=15)
        
        if len(sheet_data) < 2:
            return {
                "passed": False,
                "score": score / max_score,
                "feedback": " | ".join(feedback) + " | ❌ No data in spreadsheet (only headers or empty)"
            }
        
        # Find header row (skip instruction rows)
        header_row_idx = None
        headers = []
        for idx, row in enumerate(sheet_data):
            row_str = ' '.join([normalize_string(cell) for cell in row[:8]])
            # Look for a row that has date/day and treatment/mean keywords
            if any(kw in row_str for kw in ['date', 'day']) and \
               any(kw in row_str for kw in ['treatment', 'treat']):
                header_row_idx = idx
                headers = [normalize_string(h) for h in row]
                break
        
        if header_row_idx is None:
            return {
                "passed": False,
                "score": score / max_score,
                "feedback": " | ".join(feedback) + " | ❌ Could not find header row with 'date' and 'treatment' columns"
            }
        
        score += 5
        feedback.append(f"✅ Header row found at row {header_row_idx + 1}")
        
        # Check for required headers
        required_keywords = [
            (['date', 'day'], 'date/day column'),
            (['treatment', 'treat', 'group'], 'treatment column'),
            (['mean', 'avg', 'average'], 'mean/average column')
        ]
        
        found_columns = {}
        headers_found = 0
        
        for keywords, description in required_keywords:
            col_idx = None
            for idx, h in enumerate(headers):
                if any(kw in h for kw in keywords):
                    col_idx = idx
                    break
            
            if col_idx is not None:
                headers_found += 1
                found_columns[description] = col_idx
                score += 5
        
        if headers_found == len(required_keywords):
            feedback.append(f"✅ All required column headers present ({headers_found}/{len(required_keywords)})")
        else:
            feedback.append(f"⚠️ Only {headers_found}/{len(required_keywords)} required headers found")
        
        # Get data rows (after header)
        data_rows = sheet_data[header_row_idx + 1:]
        non_empty_rows = [row for row in data_rows if any(cell for cell in row[:8])]
        
        if len(non_empty_rows) < 4:
            feedback.append(f"⚠️ Only {len(non_empty_rows)} data rows found (expected at least 6)")
            score += 2
        elif len(non_empty_rows) < 6:
            feedback.append(f"⚠️ Found {len(non_empty_rows)} data rows (expected 6 for complete dataset)")
            score += 4
        else:
            feedback.append(f"✅ Sufficient data rows: {len(non_empty_rows)}")
            score += 5
        
        # Extract columns if found
        date_col = found_columns.get('date/day column')
        treatment_col = found_columns.get('treatment column')
        mean_col = found_columns.get('mean/average column')
        
        # Verify date standardization
        if date_col is not None and len(non_empty_rows) > 0:
            dates = [row[date_col] if len(row) > date_col else None for row in non_empty_rows]
            dates_standardized = sum(1 for d in dates if d and is_valid_date_format(d))
            dates_march_2024 = sum(1 for d in dates if d and is_march_2024_date(d))
            
            if dates_standardized >= len(non_empty_rows) * 0.8:
                score += 15
                feedback.append(f"✅ Dates properly standardized ({dates_standardized}/{len(non_empty_rows)} in YYYY-MM-DD format)")
            elif dates_standardized >= len(non_empty_rows) * 0.5:
                score += 8
                feedback.append(f"⚠️ Dates partially standardized ({dates_standardized}/{len(non_empty_rows)})")
            else:
                score += 3
                feedback.append(f"❌ Most dates not standardized ({dates_standardized}/{len(non_empty_rows)})")
            
            # Check if dates are in March 2024
            if dates_march_2024 >= len(non_empty_rows) * 0.8:
                score += 5
                feedback.append(f"✅ Dates are in correct month (March 2024)")
            else:
                feedback.append(f"⚠️ Some dates may not be in March 2024")
        
        # Verify treatment standardization
        if treatment_col is not None and len(non_empty_rows) > 0:
            treatments = [normalize_string(row[treatment_col]) if len(row) > treatment_col else "" for row in non_empty_rows]
            ww_count = sum(1 for t in treatments if t == 'ww')
            ds_count = sum(1 for t in treatments if t == 'ds')
            
            # Should have roughly equal numbers (3 WW, 3 DS for complete dataset)
            if ww_count >= 2 and ds_count >= 2:
                score += 10
                feedback.append(f"✅ Treatments standardized (WW: {ww_count}, DS: {ds_count})")
            elif ww_count >= 1 or ds_count >= 1:
                score += 5
                feedback.append(f"⚠️ Treatment codes partially standardized (WW: {ww_count}, DS: {ds_count})")
            else:
                # Check for variants
                variants = [t for t in treatments if any(kw in t for kw in ['well', 'water', 'control', 'drought', 'stress'])]
                if len(variants) >= 3:
                    score += 3
                    feedback.append(f"⚠️ Treatments present but not fully standardized to WW/DS")
                else:
                    feedback.append(f"❌ Treatment codes not properly standardized")
        
        # Verify unit conversion (check if mean values are in cm range, not mm)
        if mean_col is not None and len(non_empty_rows) > 0:
            means = []
            for row in non_empty_rows:
                if len(row) > mean_col:
                    val = row[mean_col]
                    if isinstance(val, (int, float)) and val > 0:
                        means.append(val)
            
            if means:
                # Values should be in cm range (2.5-4.5), not mm range (25-45)
                in_cm_range = sum(1 for m in means if 2.0 <= m <= 5.0)
                in_mm_range = sum(1 for m in means if 20.0 <= m <= 50.0)
                
                if in_cm_range >= len(means) * 0.8:
                    score += 15
                    feedback.append(f"✅ Unit conversion correct (values in cm range: {min(means):.2f}-{max(means):.2f})")
                elif in_mm_range >= len(means) * 0.5:
                    score += 3
                    feedback.append(f"❌ Values appear to be in mm, not cm (range: {min(means):.2f}-{max(means):.2f})")
                else:
                    score += 8
                    feedback.append(f"⚠️ Some values may need unit conversion (range: {min(means):.2f}-{max(means):.2f})")
            else:
                feedback.append("⚠️ No valid numeric mean values found")
        
        # Check for reasonable mean calculations
        if mean_col is not None and len(non_empty_rows) > 0:
            means = [row[mean_col] if len(row) > mean_col else None for row in non_empty_rows]
            valid_means = [m for m in means if isinstance(m, (int, float)) and 2.0 <= m <= 5.0]
            
            # Check if formulas are present (indirect check - look for consistency)
            # We can't directly check formulas with data_only=True, but we can check if values are reasonable
            if len(valid_means) >= len(non_empty_rows) * 0.6:
                score += 15
                feedback.append(f"✅ Mean calculations present and reasonable ({len(valid_means)} valid means)")
            elif len(valid_means) >= 2:
                score += 8
                feedback.append(f"⚠️ Some mean calculations present ({len(valid_means)})")
            else:
                feedback.append(f"❌ Mean calculations missing or invalid")
        
        # Check for missing data handling (look for blanks, N/A, or notes in data)
        missing_data_indicators = 0
        note_col = None
        
        # Look for a notes/flags column
        for idx, h in enumerate(headers):
            if any(kw in h for kw in ['note', 'flag', 'comment', 'remark']):
                note_col = idx
                break
        
        # Check all cells for missing data indicators
        for row in non_empty_rows:
            row_str = ' '.join([normalize_string(cell) for cell in row[:10]])
            if any(marker in row_str for marker in ['n/a', 'n/m', 'missing', 'wilt', 'none', '?']):
                missing_data_indicators += 1
        
        # Also check for blank cells in individual plant measurements
        # (columns between treatment and mean should have some blanks for missing data)
        blank_cells_in_data = 0
        for row in non_empty_rows:
            for cell_idx in range(min(len(row), 8)):
                if cell_idx not in [date_col, treatment_col, mean_col, note_col]:
                    cell_val = row[cell_idx] if len(row) > cell_idx else None
                    if cell_val is None or normalize_string(cell_val) == '':
                        blank_cells_in_data += 1
        
        if missing_data_indicators >= 2 or blank_cells_in_data >= 2:
            score += 10
            if note_col is not None:
                feedback.append(f"✅ Missing data properly handled with notes/flags column")
            else:
                feedback.append(f"✅ Missing data handled ({missing_data_indicators} indicators found)")
        elif missing_data_indicators >= 1 or blank_cells_in_data >= 1:
            score += 5
            feedback.append(f"⚠️ Some missing data handling present")
        else:
            score += 2
            feedback.append(f"⚠️ Missing data handling unclear (expected some blank/flagged cells)")
        
        # Bonus points for professional formatting (check if headers are bold)
        # This is harder to verify programmatically, but we can check some basics
        try:
            header_cell = sheet.cell(row=header_row_idx + 1, column=1)
            if header_cell.font and header_cell.font.bold:
                score += 5
                feedback.append("✅ Professional formatting (headers bold)")
            else:
                score += 2
        except:
            score += 2
        
        # Calculate final score
        final_score = min(score / max_score, 1.0)
        passed = final_score >= 0.70  # 70% threshold
        
        # Add summary
        summary = f"Final Score: {score}/{max_score} ({int(final_score * 100)}%)"
        feedback.append(summary)
        
        return {
            "passed": passed,
            "score": final_score,
            "feedback": " | ".join(feedback)
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except:
                pass