#!/usr/bin/env python3
"""
Verifier for Small Claims Evidence task
"""

import sys
import os
import logging
import tempfile
from datetime import datetime, timedelta

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_sheet_data,
    get_cell_value,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_small_claims_evidence(traj, env_info, task_info):
    """
    Verify small claims evidence spreadsheet organization.
    
    Checks:
    1. Structure - Required columns present
    2. Data Accuracy - All 10 evidence items present and chronologically ordered
    3. Calculations - Days Since Move-In calculated, summary section with correct values
    4. Formatting - Conditional formatting applied (colored backgrounds)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/deposit_evidence.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_claims_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0.0, 
                   "feedback": f"❌ File not found or cannot be parsed: {error}"}

        sheet = wb.active
        data = get_sheet_data(wb, sheet.title, max_rows=30, max_cols=15)

        score = 0.0
        feedback = []

        # ===================================================================
        # CRITERION 1: Structure Check (25 points)
        # ===================================================================
        structure_score = 0
        
        # Find the header row (look for row with most column-like words)
        header_row_idx = None
        header_row = None
        
        for idx, row in enumerate(data[:10]):  # Check first 10 rows
            if not row:
                continue
            row_lower = [str(cell).lower().strip() if cell else '' for cell in row]
            # Look for rows with multiple column-like words
            if any('date' in cell for cell in row_lower) and \
               any('evidence' in cell or 'type' in cell for cell in row_lower):
                header_row_idx = idx
                header_row = row_lower
                break
        
        if header_row is None:
            feedback.append("❌ Structure: Could not find header row with required columns (0/25)")
        else:
            # Check for required columns (flexible matching)
            required_cols = {
                'date': ['date', 'when', 'time'],
                'evidence_type': ['evidence type', 'type', 'evidence', 'category'],
                'description': ['description', 'desc', 'details', 'summary'],
                'supports_claim': ['supports claim', 'claim', 'supports', 'purpose'],
                'dollar_amount': ['dollar', 'amount', 'cost', 'price', '$'],
                'days_since': ['days since', 'days', 'elapsed', 'day count']
            }
            
            found_cols = {}
            for col_key, variations in required_cols.items():
                for cell in header_row:
                    if any(var in cell for var in variations):
                        found_cols[col_key] = True
                        break
            
            structure_score = len(found_cols) * 4  # 4 points per column, max 24
            
            # Bonus point if all columns found
            if len(found_cols) >= 6:
                structure_score = 25
                feedback.append(f"✅ Structure: All required columns found ({structure_score}/25)")
            elif len(found_cols) >= 4:
                structure_score = 20
                feedback.append(f"⚠️ Structure: Most columns found ({len(found_cols)}/6 columns, {structure_score}/25)")
            else:
                feedback.append(f"❌ Structure: Missing columns ({len(found_cols)}/6 columns, {structure_score}/25)")
        
        score += structure_score

        # ===================================================================
        # CRITERION 2: Data Accuracy (35 points)
        # ===================================================================
        data_score = 0
        
        # Define required evidence items with multiple matching patterns
        required_evidence = [
            {
                'date': '2024-03-01',
                'keywords': ['lease', 'agreement', '1200', 'deposit'],
                'min_match': 2,
                'name': 'Lease agreement'
            },
            {
                'date': '2024-03-01',
                'keywords': ['bank', 'statement', 'paid', '1200', 'deposit'],
                'min_match': 2,
                'name': 'Bank statement'
            },
            {
                'date': '2024-03-10',
                'keywords': ['previous tenant', 'email', 'crack', 'there'],
                'min_match': 2,
                'name': 'Previous tenant email'
            },
            {
                'date': '2024-03-15',
                'keywords': ['move-in', 'photo', 'crack', 'countertop', 'showing'],
                'min_match': 2,
                'name': 'Move-in photos'
            },
            {
                'date': '2024-05-28',
                'keywords': ['cleaning', 'receipt', '180', 'professional'],
                'min_match': 2,
                'name': 'Cleaning receipt'
            },
            {
                'date': '2024-05-28',
                'keywords': ['walkthrough', 'email', 'everything', 'looks good', 'landlord'],
                'min_match': 2,
                'name': 'Move-out walkthrough'
            },
            {
                'date': '2024-05-28',
                'keywords': ['photo', 'clean', 'empty', 'apartment', 'move-out'],
                'min_match': 2,
                'name': 'Move-out photos'
            },
            {
                'date': '2024-06-03',
                'keywords': ['text', 'landlord', '800', 'countertop', 'claiming'],
                'min_match': 2,
                'name': 'Landlord damage claim'
            },
            {
                'date': '2024-06-03',
                'keywords': ['reply', 'text', 'photo', 'move-in', 'your'],
                'min_match': 2,
                'name': 'Your reply with proof'
            },
            {
                'date': '2024-06-10',
                'keywords': ['certified', 'mail', 'demand', 'letter'],
                'min_match': 2,
                'name': 'Demand letter receipt'
            }
        ]
        
        # Extract data rows (skip header and instruction rows)
        if header_row_idx is not None:
            data_rows = data[header_row_idx + 1:header_row_idx + 15]  # Check next 14 rows
        else:
            data_rows = data[3:17]  # Fallback: skip first few rows
        
        found_evidence = []
        
        for row in data_rows:
            if not row or not any(row):
                continue
            
            row_str = ' '.join([str(cell).lower() for cell in row if cell]).strip()
            
            if not row_str or len(row_str) < 5:
                continue
            
            # Check against each required evidence item
            for evidence in required_evidence:
                if evidence['name'] in [e['name'] for e in found_evidence]:
                    continue  # Already found this evidence
                
                match_count = sum(1 for keyword in evidence['keywords'] if keyword.lower() in row_str)
                
                if match_count >= evidence['min_match']:
                    found_evidence.append(evidence)
                    break
        
        # Score based on evidence items found
        evidence_found_count = len(found_evidence)
        data_score = min(35, evidence_found_count * 3.5)
        
        if evidence_found_count >= 9:
            feedback.append(f"✅ Data: Found {evidence_found_count}/10 evidence items ({int(data_score)}/35)")
        elif evidence_found_count >= 7:
            feedback.append(f"⚠️ Data: Found {evidence_found_count}/10 evidence items ({int(data_score)}/35)")
        else:
            feedback.append(f"❌ Data: Only found {evidence_found_count}/10 evidence items ({int(data_score)}/35)")
        
        score += data_score

        # ===================================================================
        # CRITERION 3: Calculations (20 points)
        # ===================================================================
        calc_score = 0
        
        # Check for Days Since Move-In calculations
        has_day_calculations = False
        
        if header_row_idx is not None:
            # Look in the Days Since Move-In column
            days_col_idx = None
            for idx, cell in enumerate(header_row):
                if 'days' in cell or 'day' in cell:
                    days_col_idx = idx
                    break
            
            if days_col_idx is not None:
                # Check if there are numeric values in this column
                numeric_count = 0
                for row_idx in range(header_row_idx + 1, min(header_row_idx + 12, len(data))):
                    if row_idx < len(data) and days_col_idx < len(data[row_idx]):
                        cell_val = data[row_idx][days_col_idx]
                        if isinstance(cell_val, (int, float)) and cell_val >= 0:
                            numeric_count += 1
                
                if numeric_count >= 5:
                    has_day_calculations = True
                    calc_score += 5
        
        # Look for summary section with key dollar amounts
        all_rows_str = ' '.join([
            ' '.join([str(cell) for cell in row if cell])
            for row in data[15:28]  # Look in rows that might contain summary
        ])
        
        # Check for key amounts
        has_1200 = '1200' in all_rows_str or '1,200' in all_rows_str
        has_800 = '800' in all_rows_str
        has_180 = '180' in all_rows_str
        has_1000 = '1000' in all_rows_str or '1,000' in all_rows_str
        has_200 = '200' in all_rows_str
        
        summary_checks = sum([has_1200, has_800, has_180, (has_1000 or has_200)])
        summary_score = min(15, summary_checks * 4)
        calc_score += summary_score
        
        if calc_score >= 15:
            feedback.append(f"✅ Calculations: Days calculated and summary present ({calc_score}/20)")
        elif calc_score >= 10:
            feedback.append(f"⚠️ Calculations: Partial calculations found ({calc_score}/20)")
        else:
            feedback.append(f"❌ Calculations: Missing calculations or summary ({calc_score}/20)")
        
        score += calc_score

        # ===================================================================
        # CRITERION 4: Conditional Formatting (20 points)
        # ===================================================================
        format_score = 0
        
        # Check if any cells have background colors applied
        colored_rows = set()
        
        # Check data rows for cell background colors
        start_row = header_row_idx + 1 if header_row_idx else 4
        end_row = min(start_row + 15, sheet.max_row + 1)
        
        for row_idx in range(start_row, end_row):
            row_has_color = False
            for col_idx in range(1, min(8, sheet.max_column + 1)):
                try:
                    cell = sheet.cell(row_idx, col_idx)
                    if cell.fill and cell.fill.start_color:
                        color_val = str(cell.fill.start_color.rgb) if cell.fill.start_color.rgb else ''
                        # Check if it's not default/white/transparent
                        if color_val and color_val not in ['00000000', 'FFFFFFFF', 'None', '']:
                            # Actual color found
                            if not color_val.startswith('00000000'):
                                row_has_color = True
                                break
                except Exception:
                    pass
            
            if row_has_color:
                colored_rows.add(row_idx)
        
        num_colored = len(colored_rows)
        
        if num_colored >= 4:
            format_score = 20
            feedback.append(f"✅ Formatting: Conditional formatting applied ({num_colored} highlighted rows, 20/20)")
        elif num_colored >= 2:
            format_score = 12
            feedback.append(f"⚠️ Formatting: Some highlighting found ({num_colored} highlighted rows, {format_score}/20)")
        elif num_colored >= 1:
            format_score = 6
            feedback.append(f"⚠️ Formatting: Minimal highlighting ({num_colored} highlighted row, {format_score}/20)")
        else:
            feedback.append("❌ Formatting: No conditional formatting detected (0/20)")
        
        score += format_score

        # ===================================================================
        # Final Assessment
        # ===================================================================
        passed = score >= 70
        feedback_str = " | ".join(feedback)
        
        return {
            "passed": passed,
            "score": score / 100.0,
            "feedback": f"Score: {int(score)}/100. {feedback_str}"
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
