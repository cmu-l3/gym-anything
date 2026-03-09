#!/usr/bin/env python3
"""
Verifier for Class Action Settlement Claim task

Verifies that the agent:
1. Completed missing data in existing rows
2. Added a new row for the second QuickGro purchase
3. Calculated correct recovery amounts
4. Created a TOTAL row with SUM formula
5. Saved the file properly
"""

import sys
import os
import logging
import tempfile
import re
from typing import Any, Dict, Callable, Optional, Tuple

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    get_cell_value,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_currency(value: Any) -> Optional[float]:
    """
    Normalize currency values to float.
    Handles: $65, 65.00, 65, "$65.00", etc.
    """
    if value is None:
        return None
    
    if isinstance(value, (int, float)):
        return float(value)
    
    if isinstance(value, str):
        # Remove currency symbols, spaces, commas
        cleaned = re.sub(r'[\$\s,]', '', value.strip())
        try:
            return float(cleaned)
        except ValueError:
            return None
    
    return None


def normalize_text(value: Any) -> str:
    """Normalize text for comparison (lowercase, stripped)"""
    if value is None:
        return ""
    return str(value).lower().strip()


def check_status_field(value: Any) -> bool:
    """Check if status field indicates readiness to file"""
    text = normalize_text(value)
    keywords = ['ready', 'file', 'submit', 'complete', 'done']
    return any(keyword in text for keyword in keywords)


def verify_class_action_settlement_claim(traj, env_info, task_info):
    """
    Verify class action settlement claim tracking spreadsheet.
    
    Checks:
    1. File exists and parses
    2. Row 2 (TechPhone): Est. Recovery = $65, Status filled
    3. Row 3 (StreamFlix): Est. Recovery = $10, Status filled
    4. Row 4 (QuickGro #1): Purchase Date, Amount, Proof, Est. Recovery = $30, Status
    5. Row 5 (QuickGro #2): New row with all details, Est. Recovery = $30
    6. Row 6 (DataBank): Est. Recovery = $125, Status filled
    7. Row 7 (TOTAL): Label present and SUM formula result = 260
    8. Data quality: QuickGro entries have proof, all status fields filled
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "❌ Copy function not available"}

    filepath = "/home/ga/Documents/Spreadsheets/class_action_claims.xlsx"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.xlsx')
    
    try:
        # Copy file from container
        copy_from_env(filepath, temp_file.name)
        
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ File not found or empty: {filepath}"
            }
        
        # Parse workbook
        wb = parse_xlsx_file(temp_file.name)
        if wb is None:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "❌ Failed to parse XLSX file"
            }
        
        # Get the active sheet
        if 'SettlementClaims' in wb.sheetnames:
            sheet = wb['SettlementClaims']
        else:
            sheet = wb.active
        
        feedback_parts = []
        score = 0
        total_checks = 10
        
        # Get all data for inspection
        data_rows = []
        for row_idx in range(1, 11):  # Check up to row 10
            row_data = []
            for col_idx in range(1, 9):  # Columns A-H
                cell = sheet.cell(row=row_idx, column=col_idx)
                row_data.append(cell.value)
            data_rows.append(row_data)
        
        # Check 1: Verify at least 7 rows exist (header + 6 data rows)
        non_empty_rows = sum(1 for row in data_rows if any(cell for cell in row))
        if non_empty_rows >= 7:
            score += 1
            feedback_parts.append(f"✅ Sufficient rows ({non_empty_rows})")
        else:
            feedback_parts.append(f"❌ Only {non_empty_rows} rows, need 7+")
        
        # Check 2: Row 2 (TechPhone) - Est. Recovery = $65
        techphone_recovery = normalize_currency(sheet['F2'].value)
        if techphone_recovery and abs(techphone_recovery - 65.0) <= 1.0:
            score += 1
            feedback_parts.append("✅ TechPhone recovery: $65")
        else:
            feedback_parts.append(f"❌ TechPhone recovery: {techphone_recovery} (expected $65)")
        
        # Check 3: Row 3 (StreamFlix) - Est. Recovery = $10
        streamflix_recovery = normalize_currency(sheet['F3'].value)
        if streamflix_recovery and abs(streamflix_recovery - 10.0) <= 1.0:
            score += 1
            feedback_parts.append("✅ StreamFlix recovery: $10")
        else:
            feedback_parts.append(f"❌ StreamFlix recovery: {streamflix_recovery} (expected $10)")
        
        # Check 4: Row 4 (QuickGro #1) - Complete data with Est. Recovery = $30
        quickgro1_date = sheet['C4'].value
        quickgro1_amount = normalize_currency(sheet['D4'].value)
        quickgro1_proof = normalize_text(sheet['E4'].value)
        quickgro1_recovery = normalize_currency(sheet['F4'].value)
        
        quickgro1_valid = (
            quickgro1_date is not None and
            quickgro1_amount and abs(quickgro1_amount - 42.0) <= 1.0 and
            ('yes' in quickgro1_proof or quickgro1_proof == 'y') and
            quickgro1_recovery and abs(quickgro1_recovery - 30.0) <= 1.0
        )
        
        if quickgro1_valid:
            score += 1
            feedback_parts.append("✅ QuickGro #1 complete")
        else:
            feedback_parts.append(f"❌ QuickGro #1 incomplete (Date:{quickgro1_date}, Amt:{quickgro1_amount}, Proof:{quickgro1_proof}, Recovery:{quickgro1_recovery})")
        
        # Check 5: Row 5 (QuickGro #2) - New entry exists
        row5_lawsuit = normalize_text(sheet['A5'].value)
        row5_recovery = normalize_currency(sheet['F5'].value)
        
        # Check if it's QuickGro or if DataBank moved down (then QuickGro should be in row 6)
        quickgro2_found = False
        quickgro2_row = None
        
        if 'quickgro' in row5_lawsuit:
            # QuickGro #2 is in row 5 (DataBank moved to row 6)
            if row5_recovery and abs(row5_recovery - 30.0) <= 1.0:
                quickgro2_found = True
                quickgro2_row = 5
        else:
            # Check if row 5 is DataBank, then QuickGro #2 might be missing
            # or they inserted it differently
            pass
        
        if quickgro2_found:
            score += 1
            feedback_parts.append(f"✅ QuickGro #2 added (row {quickgro2_row})")
        else:
            feedback_parts.append(f"❌ QuickGro #2 not found or incorrect recovery")
        
        # Check 6: DataBank - Est. Recovery = $125 (should be in row 5 originally, but may move to row 6)
        databank_found = False
        databank_recovery = None
        
        for row_idx in [5, 6]:
            lawsuit_name = normalize_text(sheet[f'A{row_idx}'].value)
            if 'databank' in lawsuit_name:
                databank_recovery = normalize_currency(sheet[f'F{row_idx}'].value)
                if databank_recovery and abs(databank_recovery - 125.0) <= 1.0:
                    databank_found = True
                    score += 1
                    feedback_parts.append(f"✅ DataBank recovery: $125 (row {row_idx})")
                break
        
        if not databank_found:
            feedback_parts.append(f"❌ DataBank recovery incorrect: {databank_recovery}")
        
        # Check 7: TOTAL row exists with label
        total_found = False
        total_row = None
        
        for row_idx in [6, 7, 8]:
            label = normalize_text(sheet[f'A{row_idx}'].value)
            if 'total' in label:
                total_found = True
                total_row = row_idx
                score += 1
                feedback_parts.append(f"✅ TOTAL label found (row {row_idx})")
                break
        
        if not total_found:
            feedback_parts.append("❌ TOTAL label not found")
        
        # Check 8: TOTAL formula calculates to $260
        if total_row:
            total_value = normalize_currency(sheet[f'F{total_row}'].value)
            if total_value and abs(total_value - 260.0) <= 2.0:
                score += 1
                feedback_parts.append(f"✅ TOTAL formula: $260")
            else:
                feedback_parts.append(f"❌ TOTAL incorrect: {total_value} (expected $260)")
        else:
            score += 0
            feedback_parts.append("❌ Cannot verify TOTAL (row not found)")
        
        # Check 9: Status fields are filled (spot check rows 2, 3, and DataBank)
        status_count = 0
        for row_idx in [2, 3]:
            status_val = sheet[f'H{row_idx}'].value
            if status_val and len(str(status_val).strip()) > 0:
                status_count += 1
        
        if status_count >= 2:
            score += 1
            feedback_parts.append("✅ Status fields filled")
        else:
            feedback_parts.append(f"❌ Status fields incomplete ({status_count}/2 checked)")
        
        # Check 10: QuickGro entries have "Have Proof?" = Yes
        quickgro_proof_count = 0
        for row_idx in [4, 5]:
            lawsuit = normalize_text(sheet[f'A{row_idx}'].value)
            if 'quickgro' in lawsuit:
                proof = normalize_text(sheet[f'E{row_idx}'].value)
                if 'yes' in proof or proof == 'y':
                    quickgro_proof_count += 1
        
        if quickgro_proof_count >= 2:
            score += 1
            feedback_parts.append("✅ QuickGro proof documented")
        elif quickgro_proof_count == 1:
            score += 0.5
            feedback_parts.append("⚠️ Only 1 QuickGro has proof")
        else:
            feedback_parts.append("❌ QuickGro proof fields missing")
        
        # Calculate final results
        final_score = score / total_checks
        passed = final_score >= 0.7  # Pass if 7/10 checks pass
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": final_score,
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
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)