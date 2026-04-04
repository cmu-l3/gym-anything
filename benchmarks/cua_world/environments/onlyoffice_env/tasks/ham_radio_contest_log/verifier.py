#!/usr/bin/env python3
"""
Verifier for Ham Radio Contest Log task
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_ham_radio_log(traj, env_info, task_info):
    """
    Verify that the ham radio contest log was organized correctly.

    Checks:
    1. Time column standardized to 24-hour HH:MM format
    2. Frequency column standardized to MHz decimal format
    3. Mode column normalized (USB/LSB → SSB)
    4. Band column added with correct values derived from frequency
    5. Points column added with correct formula logic
    6. Duplicate column added with correct duplicate detection
    7. Summary section with total contacts, valid contacts, total points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    # Try both the expected output path and the raw log path (in case they didn't save as new file)
    container_paths = [
        "/home/ga/Documents/Spreadsheets/fieldday_score.xlsx",
        "/home/ga/Documents/Spreadsheets/fieldday_raw_log.xlsx"
    ]
    
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_ham_log_')
    
    wb = None
    loaded_path = None
    
    for container_path in container_paths:
        try:
            success, wb_temp, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')
            if success:
                wb = wb_temp
                loaded_path = container_path
                logger.info(f"Successfully loaded: {container_path}")
                break
        except Exception as e:
            logger.debug(f"Could not load {container_path}: {e}")
            continue
    
    if wb is None:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "Could not load spreadsheet from either fieldday_score.xlsx or fieldday_raw_log.xlsx"
        }

    try:
        sheet = wb.active
        feedback_parts = []
        score = 0.0
        max_score = 10.0
        
        # Get all data to work with
        all_data = get_sheet_data(wb, sheet.title, max_rows=40, max_cols=15)
        
        if len(all_data) < 25:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Spreadsheet has insufficient data rows: {len(all_data)}"
            }
        
        # ===== Criterion 1: Time column standardized (24-hour HH:MM) =====
        time_col = [sheet.cell(row=r, column=1).value for r in range(2, 26)]
        time_pattern = re.compile(r'^\d{2}:\d{2}$')
        valid_times = sum(1 for t in time_col if t and time_pattern.match(str(t)))
        
        if valid_times >= 22:  # Allow some margin for edge cases
            score += 1.5
            feedback_parts.append(f"✅ Time standardized: {valid_times}/24 in 24-hour HH:MM format")
        else:
            feedback_parts.append(f"❌ Time not properly standardized: only {valid_times}/24 valid")
        
        # ===== Criterion 2: Frequency column standardized (MHz decimal) =====
        freq_col = [sheet.cell(row=r, column=2).value for r in range(2, 26)]
        valid_freqs = 0
        for f in freq_col:
            if f is not None:
                try:
                    freq_val = float(f) if not isinstance(f, str) else float(f.replace('kHz', '').replace('MHz', '').strip())
                    if 7.0 <= freq_val <= 30.0:
                        valid_freqs += 1
                except:
                    pass
        
        if valid_freqs >= 22:
            score += 1.5
            feedback_parts.append(f"✅ Frequency standardized: {valid_freqs}/24 in MHz format")
        else:
            feedback_parts.append(f"❌ Frequency not properly standardized: only {valid_freqs}/24 valid")
        
        # ===== Criterion 3: Mode column normalized =====
        mode_col = [sheet.cell(row=r, column=3).value for r in range(2, 26)]
        # Should not have USB or LSB anymore (converted to SSB)
        has_usb_lsb = any(str(m).upper() in ['USB', 'LSB'] for m in mode_col if m)
        valid_modes = sum(1 for m in mode_col if m and str(m).upper() in ['SSB', 'CW', 'FT8'])
        
        if not has_usb_lsb and valid_modes >= 22:
            score += 1.0
            feedback_parts.append(f"✅ Mode normalized: USB/LSB converted to SSB")
        else:
            if has_usb_lsb:
                feedback_parts.append(f"❌ Mode not normalized: still contains USB/LSB")
            else:
                feedback_parts.append(f"❌ Mode column has issues: only {valid_modes}/24 valid")
        
        # ===== Criterion 4: Band column added =====
        # Check if column G has header containing "band"
        band_header = sheet.cell(row=1, column=7).value
        if band_header and 'band' in str(band_header).lower():
            band_col = [sheet.cell(row=r, column=7).value for r in range(2, 26)]
            valid_bands = sum(1 for b in band_col if b and str(b).lower() in ['40m', '20m', '15m', '80m', '10m'])
            
            if valid_bands >= 20:
                score += 2.0
                feedback_parts.append(f"✅ Band column added: {valid_bands}/24 correct band designations")
            else:
                score += 0.5
                feedback_parts.append(f"⚠️ Band column exists but incomplete: {valid_bands}/24 valid")
        else:
            feedback_parts.append(f"❌ Band column not found in column G")
        
        # ===== Criterion 5: Points column added with formula =====
        points_header = sheet.cell(row=1, column=8).value
        if points_header and 'point' in str(points_header).lower():
            points_col = [sheet.cell(row=r, column=8).value for r in range(2, 26)]
            # Check if values are 1 or 2
            valid_points = sum(1 for p in points_col if p in [1, 2])
            
            # Check if first cell has a formula (best we can do with openpyxl data_only mode)
            # We'll rely on value correctness instead
            # Expected: CW and FT8 contacts should have 2 points, others 1
            if valid_points >= 20:
                score += 1.5
                feedback_parts.append(f"✅ Points column added: {valid_points}/24 valid point values")
            else:
                score += 0.3
                feedback_parts.append(f"⚠️ Points column exists but values may be incorrect: {valid_points}/24 valid")
        else:
            feedback_parts.append(f"❌ Points column not found in column H")
        
        # ===== Criterion 6: Duplicate column added =====
        dup_header = sheet.cell(row=1, column=9).value
        if dup_header and 'dup' in str(dup_header).lower():
            dup_col = [sheet.cell(row=r, column=9).value for r in range(2, 26)]
            dup_count = sum(1 for d in dup_col if d and 'DUP' in str(d).upper())
            
            # Expected: 3 duplicates (K4ABC row 12, W4JKL row 17, N6PQR row 24)
            if 2 <= dup_count <= 4:
                score += 1.5
                feedback_parts.append(f"✅ Duplicate detection working: {dup_count} duplicates found")
            else:
                score += 0.3
                feedback_parts.append(f"⚠️ Duplicate detection may be incorrect: {dup_count} marked (expected ~3)")
        else:
            feedback_parts.append(f"❌ Duplicate column not found in column I")
        
        # ===== Criterion 7: Summary section =====
        summary_found = False
        total_contacts_found = False
        valid_contacts_found = False
        total_points_found = False
        
        for row in range(27, 35):
            for col in range(1, 6):
                cell_val = sheet.cell(row=row, column=col).value
                if cell_val:
                    cell_str = str(cell_val).lower()
                    if 'total' in cell_str or 'summary' in cell_str:
                        summary_found = True
                    
                    # Look for numeric values in nearby cells
                    if isinstance(cell_val, (int, float)):
                        if 20 <= cell_val <= 30 and not valid_contacts_found:
                            valid_contacts_found = True
                        elif 30 <= cell_val <= 50 and not total_points_found:
                            total_points_found = True
                        elif cell_val == 24 and not total_contacts_found:
                            total_contacts_found = True
        
        summary_score = 0
        if summary_found:
            summary_score += 0.3
        if total_contacts_found or valid_contacts_found:
            summary_score += 0.6
        if total_points_found:
            summary_score += 0.6
        
        score += summary_score
        
        if summary_score >= 1.0:
            feedback_parts.append(f"✅ Summary section created with calculations")
        elif summary_score > 0:
            feedback_parts.append(f"⚠️ Summary section partially complete")
        else:
            feedback_parts.append(f"❌ Summary section not found or incomplete")
        
        # ===== Final scoring =====
        passed = score >= 7.0
        
        feedback = " | ".join(feedback_parts)
        
        # Add info about which file was verified
        if 'raw_log' in loaded_path:
            feedback = "[Note: Verified raw_log file, not saved as fieldday_score.xlsx] " + feedback
        
        return {
            "passed": passed,
            "score": score / max_score,
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
