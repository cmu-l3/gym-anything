#!/usr/bin/env python3
"""
Verifier for Backyard Beekeeping Log task

Checks that messy inspection notes have been cleaned and structured properly
into a beekeeping inspection log with standardized columns and summary formulas.
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
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_backyard_beekeeping_log(traj, env_info, task_info):
    """
    Verify that beekeeping inspection records have been properly cleaned and structured.

    Checks:
    1. Output file exists and can be parsed
    2. "Inspection_Log" worksheet exists
    3. Required columns are present
    4. Hive_ID values are standardized
    5. Frames_Of_Honey contains numeric values
    6. Queen_Seen has categorical values
    7. At least 7 data rows present (8 inspections expected)
    8. Summary statistics/formulas are present
    9. Pest alerts properly flagged
    10. Data appears cleaned (not just copied)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/beekeeping_log_2025.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_bee_')

    try:
        # Copy and parse the output spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Could not open output file beekeeping_log_2025.xlsx: {error}"
            }

        feedback_parts = []
        score = 0.0

        # Check if "Inspection_Log" worksheet exists
        if "Inspection_Log" not in wb.sheetnames:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "❌ Missing required worksheet 'Inspection_Log'. Found worksheets: " + ", ".join(wb.sheetnames)
            }

        sheet = wb["Inspection_Log"]
        feedback_parts.append("✅ Worksheet 'Inspection_Log' found")
        score += 0.08

        # Get header row (first row with data)
        header_row = None
        header_row_idx = 1
        
        for row_idx in range(1, 6):  # Check first 5 rows for header
            row_values = [cell.value for cell in sheet[row_idx] if cell.value]
            if len(row_values) >= 5:  # Must have at least 5 column headers
                header_row = [str(val).strip() if val else "" for val in row_values]
                header_row_idx = row_idx
                break
        
        if not header_row:
            return {
                "passed": False,
                "score": 0.1,
                "feedback": "❌ Could not find header row with column names"
            }

        # Check required columns exist (case-insensitive, flexible matching)
        required_cols = {
            "date": ["date", "inspection_date", "inspectiondate"],
            "hive_id": ["hive_id", "hiveid", "hive", "hive_name"],
            "queen_seen": ["queen_seen", "queenseen", "queen", "queen_status"],
            "frames_of_honey": ["frames_of_honey", "framesofhoney", "honey_frames", "honeyframes", "frames_honey", "honey"],
            "brood_pattern": ["brood_pattern", "broodpattern", "brood"],
            "pest_alert": ["pest_alert", "pestalert", "pest", "pests", "mites"],
            "action_needed": ["action_needed", "actionneeded", "action", "actions", "next_steps"]
        }

        header_lower = [h.lower().replace(" ", "_") for h in header_row]
        found_cols = {}
        
        for col_key, col_variations in required_cols.items():
            col_idx = None
            for variation in col_variations:
                if variation in header_lower:
                    col_idx = header_lower.index(variation)
                    found_cols[col_key] = col_idx
                    break
            
            if col_idx is None:
                feedback_parts.append(f"❌ Missing required column: {col_key}")
                score += 0.01
        
        missing_cols = set(required_cols.keys()) - set(found_cols.keys())
        
        if missing_cols:
            return {
                "passed": False,
                "score": min(score, 0.2),
                "feedback": " | ".join(feedback_parts) + f" | Missing: {', '.join(missing_cols)}"
            }
        
        feedback_parts.append("✅ All required columns present")
        score += 0.15

        # Extract data rows (start after header)
        data_start_row = header_row_idx + 1
        data_rows = []
        
        for row_idx in range(data_start_row, min(data_start_row + 20, sheet.max_row + 1)):
            row_data = {}
            has_data = False
            
            for col_key, col_idx in found_cols.items():
                cell_value = sheet.cell(row=row_idx, column=col_idx + 1).value
                row_data[col_key] = cell_value
                if cell_value is not None and str(cell_value).strip():
                    has_data = True
            
            if has_data:
                # Check if this looks like a data row (has hive_id or date)
                if row_data.get('hive_id') or row_data.get('date'):
                    data_rows.append(row_data)

        # Check minimum number of data rows (should have ~8 inspection records)
        if len(data_rows) < 6:
            feedback_parts.append(f"⚠️ Expected 8 inspection records, found only {len(data_rows)}")
            score += 0.05
        else:
            feedback_parts.append(f"✅ Found {len(data_rows)} inspection records")
            score += 0.12

        if len(data_rows) == 0:
            return {
                "passed": False,
                "score": min(score, 0.3),
                "feedback": " | ".join(feedback_parts) + " | No data rows found"
            }

        # Check Hive_ID standardization
        hive_values = [str(row['hive_id']).strip() for row in data_rows if row.get('hive_id')]
        unique_hives = set(hive_values)
        
        # Should have only 2 unique hive identifiers (standardized)
        if len(unique_hives) > 3:
            feedback_parts.append(f"⚠️ Hive_ID not fully standardized: {len(unique_hives)} unique values found")
            score += 0.05
        elif len(unique_hives) == 2:
            feedback_parts.append("✅ Hive_ID values properly standardized (2 hives)")
            score += 0.12
        else:
            feedback_parts.append(f"✅ Hive_ID values present ({len(unique_hives)} unique)")
            score += 0.08

        # Check Frames_Of_Honey contains numeric values
        honey_values = [row['frames_of_honey'] for row in data_rows if row.get('frames_of_honey') is not None]
        numeric_honey = [val for val in honey_values if isinstance(val, (int, float))]
        
        if len(honey_values) == 0:
            feedback_parts.append("❌ No honey frame data found")
            score += 0.02
        elif len(numeric_honey) >= len(honey_values) * 0.7:
            feedback_parts.append(f"✅ Frames_Of_Honey properly numeric ({len(numeric_honey)}/{len(honey_values)})")
            score += 0.12
        else:
            feedback_parts.append(f"⚠️ Frames_Of_Honey not fully numeric ({len(numeric_honey)}/{len(honey_values)})")
            score += 0.06

        # Check Queen_Seen has consistent categorical values
        queen_values = [str(row['queen_seen']).lower().strip() 
                       for row in data_rows 
                       if row.get('queen_seen') is not None and str(row.get('queen_seen')).strip()]
        
        expected_queen_values = ['yes', 'no', 'eggs present', 'eggs', 'not seen', 'seen']
        valid_queen = sum(1 for val in queen_values 
                         if any(exp in val for exp in expected_queen_values))
        
        if len(queen_values) == 0:
            feedback_parts.append("⚠️ No queen status data found")
            score += 0.02
        elif valid_queen >= len(queen_values) * 0.7:
            feedback_parts.append(f"✅ Queen_Seen properly categorized ({valid_queen}/{len(queen_values)})")
            score += 0.12
        else:
            feedback_parts.append(f"⚠️ Queen_Seen inconsistently categorized ({valid_queen}/{len(queen_values)})")
            score += 0.06

        # Check for pest alerts being flagged
        pest_values = [str(row['pest_alert']).lower().strip() 
                      for row in data_rows 
                      if row.get('pest_alert') is not None and str(row.get('pest_alert')).strip()]
        
        # At least one pest alert should be "yes" (mites mentioned in original data)
        has_pest_alerts = any(val in ['yes', 'true', '1', 'alert', 'mites'] for val in pest_values)
        
        if len(pest_values) >= len(data_rows) * 0.6:
            if has_pest_alerts:
                feedback_parts.append("✅ Pest alerts properly flagged")
                score += 0.10
            else:
                feedback_parts.append("✅ Pest_Alert column populated")
                score += 0.08
        else:
            feedback_parts.append("⚠️ Pest_Alert column incomplete")
            score += 0.04

        # Check for summary statistics/formulas
        # Look for cells containing keywords or formulas below the data
        summary_found = False
        formula_found = False
        
        search_start_row = data_start_row + len(data_rows) + 1
        
        for row_idx in range(search_start_row, min(search_start_row + 15, sheet.max_row + 1)):
            for col_idx in range(1, min(10, sheet.max_column + 1)):
                cell = sheet.cell(row=row_idx, column=col_idx)
                cell_value = cell.value
                
                # Check for summary keywords
                if cell_value and isinstance(cell_value, str):
                    lower_val = cell_value.lower()
                    if any(keyword in lower_val for keyword in 
                          ["latest", "last", "days since", "average", "avg", "total", "summary", "max", "min"]):
                        summary_found = True
                    
                    # Check for formulas
                    if cell_value.startswith('='):
                        formula_found = True
                
                # Check for formula in cell (openpyxl stores formulas separately)
                if hasattr(cell, 'data_type') and cell.data_type == 'f':
                    formula_found = True

        if summary_found and formula_found:
            feedback_parts.append("✅ Summary statistics with formulas present")
            score += 0.15
        elif summary_found or formula_found:
            feedback_parts.append("⚠️ Summary section incomplete (missing formulas or labels)")
            score += 0.08
        else:
            feedback_parts.append("❌ Missing summary statistics/calculations")
            score += 0.03

        # Check data appears cleaned (not just raw copied)
        # Original data had varied formats like "H1", "Hive2", "1", "2", "H2", "Hive 2"
        # Cleaned data should be more consistent
        if len(unique_hives) <= 2 and len(numeric_honey) >= len(honey_values) * 0.7:
            feedback_parts.append("✅ Data appears properly cleaned and structured")
            score += 0.08
        else:
            feedback_parts.append("⚠️ Data may not be fully cleaned")
            score += 0.03

        # Determine pass/fail (need 70% score to pass)
        score = min(score, 1.0)
        passed = score >= 0.70

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": round(score * 100, 1),
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
