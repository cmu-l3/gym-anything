#!/usr/bin/env python3
"""
Verifier for Financial Aid Dispute Tracker task
"""

import sys
import os
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_cell_color(sheet, cell_ref, check_type='fill'):
    """
    Check if a cell has color formatting.
    
    Args:
        sheet: openpyxl worksheet
        cell_ref: Cell reference (e.g., 'B7')
        check_type: 'fill' for background, 'font' for text color
    
    Returns:
        Color hex code or None
    """
    try:
        cell = sheet[cell_ref]
        if check_type == 'fill':
            if cell.fill and cell.fill.start_color:
                return cell.fill.start_color.rgb
        elif check_type == 'font':
            if cell.font and cell.font.color:
                return cell.font.color.rgb
        return None
    except:
        return None


def check_cell_bold(sheet, cell_ref):
    """Check if a cell has bold formatting"""
    try:
        cell = sheet[cell_ref]
        return cell.font and cell.font.bold
    except:
        return False


def verify_financial_aid_dispute_tracker(traj, env_info, task_info):
    """
    Verify financial aid dispute tracker spreadsheet.
    
    Checks:
    1. All 5 sheets present
    2. EFC sheet: Row 7 highlighted, E9 formatted
    3. Communication Log: Column H color coded
    4. Document Tracker: Column F color coded
    5. Financial Impact: Formulas created with correct results
    6. Deadline Tracker: Column C color coded
    7. Overall formatting quality
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/financial_aid_dispute.xlsx"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.xlsx')
    
    feedback_parts = []
    score = 0
    max_score = 100
    
    try:
        copy_from_env(container_path, temp_file.name)
        
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ File not found or empty: {container_path}"
            }
        
        # Parse workbook
        wb = parse_xlsx_file(temp_file.name)
        if not wb:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Failed to parse Excel file. Is it corrupted?"
            }
        
        # ====================================================================
        # Check 1: All 5 sheets present (15 points)
        # ====================================================================
        required_sheets = [
            "EFC Calculation Comparison",
            "Communication Log",
            "Document Tracker",
            "Financial Impact Scenarios",
            "Deadline Tracker"
        ]
        
        sheet_names = wb.sheetnames
        sheets_found = sum(1 for sheet in required_sheets if sheet in sheet_names)
        
        if sheets_found == 5:
            score += 15
            feedback_parts.append(f"✅ All 5 required sheets present")
        else:
            missing = [s for s in required_sheets if s not in sheet_names]
            score += int((sheets_found / 5) * 15)
            feedback_parts.append(f"⚠️ Missing sheets: {', '.join(missing)} ({sheets_found}/5)")
        
        # ====================================================================
        # Check 2: EFC Calculation Comparison formatting (20 points)
        # ====================================================================
        if "EFC Calculation Comparison" in sheet_names:
            efc_sheet = wb["EFC Calculation Comparison"]
            efc_points = 0
            
            # Check row 7 (B7 or E7) has yellow highlight
            b7_fill = check_cell_color(efc_sheet, 'B7', 'fill')
            e7_fill = check_cell_color(efc_sheet, 'E7', 'fill')
            
            # Yellow is typically FFFF00 or similar
            if (b7_fill and 'FFFF' in str(b7_fill)) or (e7_fill and 'FFFF' in str(e7_fill)):
                efc_points += 10
                feedback_parts.append("✅ Row 7 (error row) highlighted in yellow")
            else:
                feedback_parts.append(f"❌ Row 7 not highlighted in yellow (B7:{b7_fill}, E7:{e7_fill})")
            
            # Check E9 (discrepancy) is bold and red
            e9_bold = check_cell_bold(efc_sheet, 'E9')
            e9_color = check_cell_color(efc_sheet, 'E9', 'font')
            
            if e9_bold and e9_color and ('FF0000' in str(e9_color) or 'FF00' in str(e9_color)):
                efc_points += 10
                feedback_parts.append("✅ Discrepancy (E9) formatted in bold red")
            else:
                feedback_parts.append(f"⚠️ Discrepancy (E9) not fully formatted (bold:{e9_bold}, color:{e9_color})")
                if e9_bold:
                    efc_points += 5
            
            score += efc_points
        else:
            feedback_parts.append("❌ EFC Calculation Comparison sheet missing")
        
        # ====================================================================
        # Check 3: Communication Log color coding (15 points)
        # ====================================================================
        if "Communication Log" in sheet_names:
            comm_sheet = wb["Communication Log"]
            comm_points = 0
            
            # Check if column H has color coding
            # Rows 2-5 should have different colors based on status
            colored_cells = 0
            for row in range(2, 6):
                cell_ref = f'H{row}'
                fill_color = check_cell_color(comm_sheet, cell_ref, 'fill')
                if fill_color and fill_color != '00000000':
                    colored_cells += 1
            
            if colored_cells >= 3:
                comm_points = 15
                feedback_parts.append(f"✅ Communication log 'Follow-up Needed' column color coded ({colored_cells}/4 cells)")
            elif colored_cells >= 2:
                comm_points = 10
                feedback_parts.append(f"⚠️ Partial color coding in Communication Log ({colored_cells}/4 cells)")
            else:
                feedback_parts.append(f"❌ Communication Log column H not color coded")
            
            score += comm_points
        else:
            feedback_parts.append("❌ Communication Log sheet missing")
        
        # ====================================================================
        # Check 4: Document Tracker color coding (15 points)
        # ====================================================================
        if "Document Tracker" in sheet_names:
            doc_sheet = wb["Document Tracker"]
            doc_points = 0
            
            # Check if column F (Status) has text color coding
            colored_cells = 0
            for row in range(2, 6):
                cell_ref = f'F{row}'
                font_color = check_cell_color(doc_sheet, cell_ref, 'font')
                if font_color and font_color != '00000000' and font_color != 'FF000000':
                    colored_cells += 1
            
            if colored_cells >= 3:
                doc_points = 15
                feedback_parts.append(f"✅ Document Tracker 'Status' column color coded ({colored_cells}/4 cells)")
            elif colored_cells >= 2:
                doc_points = 10
                feedback_parts.append(f"⚠️ Partial color coding in Document Tracker ({colored_cells}/4 cells)")
            else:
                feedback_parts.append(f"❌ Document Tracker column F not color coded")
            
            score += doc_points
        else:
            feedback_parts.append("❌ Document Tracker sheet missing")
        
        # ====================================================================
        # Check 5: Financial Impact Scenarios formulas (25 points)
        # ====================================================================
        if "Financial Impact Scenarios" in sheet_names:
            scenario_points = 0
            
            # Check B4 = B3 + 2400 (should be 20900)
            b4_value = get_cell_value(wb, "Financial Impact Scenarios", "B4")
            if b4_value and isinstance(b4_value, (int, float)) and 20850 <= b4_value <= 20950:
                scenario_points += 6
            else:
                feedback_parts.append(f"⚠️ B4 (Corrected Aid) incorrect: {b4_value} (expected ~20900)")
            
            # Check B8 = B5 - B4 (should be 1100)
            b8_value = get_cell_value(wb, "Financial Impact Scenarios", "B8")
            if b8_value and isinstance(b8_value, (int, float)) and 1050 <= b8_value <= 1150:
                scenario_points += 6
            else:
                feedback_parts.append(f"⚠️ B8 (Scenario 1 cost) incorrect: {b8_value} (expected ~1100)")
            
            # Check B11 = (B5 - B3) + 150 (should be 3650)
            b11_value = get_cell_value(wb, "Financial Impact Scenarios", "B11")
            if b11_value and isinstance(b11_value, (int, float)) and 3600 <= b11_value <= 3700:
                scenario_points += 6
            else:
                feedback_parts.append(f"⚠️ B11 (Scenario 2 cost) incorrect: {b11_value} (expected ~3650)")
            
            # Check B13 = B11 - B8 (should be 2550)
            b13_value = get_cell_value(wb, "Financial Impact Scenarios", "B13")
            if b13_value and isinstance(b13_value, (int, float)) and 2500 <= b13_value <= 2600:
                scenario_points += 5
                feedback_parts.append(f"✅ Financial formulas calculated correctly (difference: ${int(b13_value)})")
            else:
                feedback_parts.append(f"⚠️ B13 (Difference) incorrect: {b13_value} (expected ~2550)")
            
            # Check B13 formatting (bold, red, larger font)
            scenario_sheet = wb["Financial Impact Scenarios"]
            b13_bold = check_cell_bold(scenario_sheet, 'B13')
            
            if b13_bold:
                scenario_points += 2
            
            score += scenario_points
            
            if scenario_points >= 20:
                feedback_parts.append("✅ Financial Impact scenarios formulas correct")
        else:
            feedback_parts.append("❌ Financial Impact Scenarios sheet missing")
        
        # ====================================================================
        # Check 6: Deadline Tracker conditional formatting (10 points)
        # ====================================================================
        if "Deadline Tracker" in sheet_names:
            deadline_sheet = wb["Deadline Tracker"]
            deadline_points = 0
            
            # Check if column C has background colors
            colored_cells = 0
            for row in range(2, 6):
                cell_ref = f'C{row}'
                fill_color = check_cell_color(deadline_sheet, cell_ref, 'fill')
                if fill_color and fill_color != '00000000':
                    colored_cells += 1
            
            if colored_cells >= 3:
                deadline_points = 10
                feedback_parts.append(f"✅ Deadline Tracker 'Days Remaining' color coded ({colored_cells}/4 cells)")
            elif colored_cells >= 2:
                deadline_points = 5
                feedback_parts.append(f"⚠️ Partial color coding in Deadline Tracker ({colored_cells}/4 cells)")
            else:
                feedback_parts.append(f"❌ Deadline Tracker column C not color coded")
            
            score += deadline_points
        else:
            feedback_parts.append("❌ Deadline Tracker sheet missing")
        
        # ====================================================================
        # Normalize score and determine pass/fail
        # ====================================================================
        score = min(100, score)  # Cap at 100
        passed = score >= 70
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score / 100.0,  # Normalize to 0-1
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)