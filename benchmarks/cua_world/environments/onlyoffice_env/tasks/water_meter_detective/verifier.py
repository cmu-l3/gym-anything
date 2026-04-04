#!/usr/bin/env python3
"""
Verifier for Water Meter Detective task

Verifies that the user created a comprehensive water meter tracking spreadsheet
to investigate a suspected leak, including time-series data, calculations, and
documented findings from hypothesis testing (isolating fixtures).
"""

import sys
import os
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_water_meter_tracking(traj, env_info, task_info):
    """
    Verify water meter tracking spreadsheet.
    
    Checks:
    1. Headers present in Row 1 (Date, Time, Meter Reading, Usage, Hours, Rate, Notes)
    2. At least 6-7 data rows with dates spanning multiple days
    3. Meter readings are 6-digit numbers in realistic ascending sequence
    4. Usage calculations present (differences between consecutive readings)
    5. Rate calculations present (usage divided by hours)
    6. Testing notes mention isolating fixtures (toilet/bathroom)
    7. Summary section exists with findings about leak source
    
    Returns:
        dict: {"passed": bool, "score": float, "feedback": str}
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/water_meter_tracking.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_water_')

    try:
        # Copy the file from container
        temp_file_path = os.path.join(temp_dir, 'water_meter_tracking.xlsx')
        
        try:
            copy_from_env(container_path, temp_file_path)
        except Exception as e:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Failed to copy file: {str(e)}"
            }
        
        if not os.path.exists(temp_file_path) or os.path.getsize(temp_file_path) == 0:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "❌ File not found or empty at expected location"
            }
        
        # Parse the spreadsheet
        workbook = parse_xlsx_file(temp_file_path)
        if not workbook:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "❌ Failed to parse XLSX file - may be corrupted"
            }
        
        sheet = workbook.active
        feedback_parts = []
        score = 0.0
        max_score = 10.0
        
        # === Check 1: Headers present in Row 1 (1.5 points) ===
        expected_keywords = ['date', 'time', 'meter', 'reading', 'usage', 'hour', 'rate', 'note']
        row1_values = []
        
        for cell in sheet[1]:
            if cell.value:
                row1_values.append(str(cell.value).lower().strip())
        
        # Count how many expected keywords appear in headers
        keywords_found = sum(1 for keyword in expected_keywords 
                           if any(keyword in header for header in row1_values))
        
        if keywords_found >= 6:
            score += 1.5
            feedback_parts.append(f"✅ Headers comprehensive ({keywords_found}/8 keywords found)")
        elif keywords_found >= 4:
            score += 1.0
            feedback_parts.append(f"⚠️ Headers partial ({keywords_found}/8 keywords)")
        else:
            feedback_parts.append(f"❌ Headers insufficient ({keywords_found}/8 keywords)")
        
        # === Check 2: Data rows present (at least 6 rows, 1.5 points) ===
        data_row_count = 0
        for row_idx in range(2, 11):  # Check rows 2-10
            row_has_data = False
            for col_idx in range(1, 8):  # Check first 7 columns
                val = sheet.cell(row=row_idx, column=col_idx).value
                if val is not None and val != '':
                    row_has_data = True
                    break
            if row_has_data:
                data_row_count += 1
        
        if data_row_count >= 6:
            score += 1.5
            feedback_parts.append(f"✅ Sufficient data rows ({data_row_count} rows)")
        elif data_row_count >= 4:
            score += 0.75
            feedback_parts.append(f"⚠️ Some data rows ({data_row_count} rows, expected 6-7)")
        else:
            feedback_parts.append(f"❌ Insufficient data ({data_row_count} rows)")
        
        # === Check 3: Meter readings are realistic 6-digit numbers (1.5 points) ===
        # Find meter reading column (look for "meter" or "reading" in headers)
        meter_col = None
        for col_idx in range(1, 8):
            header = sheet.cell(row=1, column=col_idx).value
            if header and isinstance(header, str):
                header_lower = header.lower()
                if 'meter' in header_lower or 'reading' in header_lower:
                    meter_col = col_idx
                    break
        
        if meter_col is None:
            meter_col = 3  # Default guess (typically column C)
        
        meter_readings = []
        for row_idx in range(2, min(10, 2 + data_row_count)):
            val = sheet.cell(row=row_idx, column=meter_col).value
            if val and isinstance(val, (int, float)):
                meter_readings.append(float(val))
        
        # Validate: 6-digit numbers between 800,000-900,000
        valid_readings = [r for r in meter_readings if 800000 <= r <= 900000]
        
        # Check ascending order (readings should increase over time)
        is_ascending = True
        if len(meter_readings) > 1:
            for i in range(len(meter_readings) - 1):
                if meter_readings[i] >= meter_readings[i + 1]:
                    is_ascending = False
                    break
        
        if len(valid_readings) >= 5 and is_ascending:
            score += 1.5
            feedback_parts.append(f"✅ Meter readings valid & sequential ({len(valid_readings)} readings)")
        elif len(valid_readings) >= 4:
            score += 0.75
            feedback_parts.append(f"⚠️ Most readings valid ({len(valid_readings)} readings)")
        else:
            feedback_parts.append(f"❌ Meter readings invalid ({len(valid_readings)}/6+)")
        
        # === Check 4: Usage calculations present (2.0 points) ===
        # Find usage column
        usage_col = None
        for col_idx in range(1, 8):
            header = sheet.cell(row=1, column=col_idx).value
            if header and isinstance(header, str) and 'usage' in header.lower():
                usage_col = col_idx
                break
        
        if usage_col is None:
            usage_col = 4  # Default guess
        
        usage_values = []
        for row_idx in range(3, min(10, 3 + data_row_count)):  # Start at row 3 (skip first data row)
            val = sheet.cell(row=row_idx, column=usage_col).value
            if val and isinstance(val, (int, float)):
                usage_values.append(float(val))
        
        # Valid usage: positive, reasonable (50-500 gallons per 12-hour period)
        valid_usage = [u for u in usage_values if 50 <= u <= 600]
        
        if len(valid_usage) >= 5:
            score += 2.0
            feedback_parts.append(f"✅ Usage calculations present ({len(valid_usage)} values)")
        elif len(valid_usage) >= 3:
            score += 1.0
            feedback_parts.append(f"⚠️ Some usage calculations ({len(valid_usage)} values)")
        else:
            feedback_parts.append(f"❌ Usage calculations missing/invalid ({len(valid_usage)}/5+)")
        
        # === Check 5: Rate calculations present (2.0 points) ===
        # Find rate column (look for "rate" or "gal" + "hour")
        rate_col = None
        for col_idx in range(1, 8):
            header = sheet.cell(row=1, column=col_idx).value
            if header and isinstance(header, str):
                header_lower = header.lower()
                if 'rate' in header_lower or ('gal' in header_lower and 'hour' in header_lower):
                    rate_col = col_idx
                    break
        
        if rate_col is None:
            rate_col = 6  # Default guess
        
        rate_values = []
        for row_idx in range(3, min(10, 3 + data_row_count)):
            val = sheet.cell(row=row_idx, column=rate_col).value
            if val and isinstance(val, (int, float)):
                rate_values.append(float(val))
        
        # Valid rate: positive, reasonable (10-50 gallons/hour typical)
        valid_rates = [r for r in rate_values if 5 <= r <= 60]
        
        if len(valid_rates) >= 5:
            score += 2.0
            feedback_parts.append(f"✅ Rate calculations present ({len(valid_rates)} values)")
        elif len(valid_rates) >= 3:
            score += 1.0
            feedback_parts.append(f"⚠️ Some rate calculations ({len(valid_rates)} values)")
        else:
            feedback_parts.append(f"❌ Rate calculations missing/invalid ({len(valid_rates)}/5+)")
        
        # === Check 6: Summary section with findings (1.5 points) ===
        summary_found = False
        leak_finding_found = False
        
        # Search rows 10-25 and all columns for summary keywords
        summary_keywords = ['summary', 'finding', 'conclusion', 'investigation', 'total', 'average']
        leak_keywords = ['leak', 'toilet', 'bathroom', 'isolated', 'reduced', 'drop', 'guest', 'gal/hr', 'gallons/hour']
        
        for row_idx in range(10, 26):
            for col_idx in range(1, 8):
                cell_val = sheet.cell(row=row_idx, column=col_idx).value
                if cell_val and isinstance(cell_val, str):
                    cell_lower = cell_val.lower()
                    if any(kw in cell_lower for kw in summary_keywords):
                        summary_found = True
                    if any(kw in cell_lower for kw in leak_keywords):
                        leak_finding_found = True
        
        if summary_found and leak_finding_found:
            score += 1.5
            feedback_parts.append("✅ Summary section with leak findings present")
        elif summary_found or leak_finding_found:
            score += 0.75
            feedback_parts.append("⚠️ Partial summary (missing complete findings)")
        else:
            feedback_parts.append("❌ No summary/conclusion section found")
        
        # === Final Assessment ===
        passed = score >= 7.0  # 70% threshold for passing
        
        feedback = " | ".join(feedback_parts)
        feedback += f" | Final Score: {score:.1f}/{max_score}"
        
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
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)