#!/usr/bin/env python3
"""
Verifier for Student Loan Strategy Comparison task

This verifier checks that the user created a comprehensive loan comparison
spreadsheet with proper data organization, formulas, and formatting.
"""

import sys
import os
import logging
import tempfile
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_student_loan_strategy_comparison(traj, env_info, task_info):
    """
    Verify student loan payoff strategy comparison spreadsheet.
    
    Scoring breakdown (100 points total):
    - Loan Data Organization: 30 points
    - Strategy Comparison: 40 points
    - Formulas Used: 15 points
    - Professional Formatting: 15 points
    
    Passing threshold: 70/100 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "❌ Copy function not available in environment"
        }

    expected_path = "/home/ga/Documents/Spreadsheets/loan_comparison.xlsx"
    temp_file = None
    
    try:
        # Copy file from container
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.xlsx')
        temp_file.close()
        
        try:
            copy_from_env(expected_path, temp_file.name)
        except Exception as e:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Could not copy file from container: {str(e)}"
            }
        
        if not Path(temp_file.name).exists() or Path(temp_file.name).stat().st_size == 0:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ File not found or empty: {expected_path}"
            }
        
        # Parse spreadsheet
        wb = parse_xlsx_file(temp_file.name)
        if wb is None:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "❌ Could not parse XLSX file - file may be corrupted"
            }
        
        # Get the active sheet
        sheet = wb.active
        sheet_name = sheet.title
        
        # Extract all data from the sheet
        data = get_sheet_data(wb, sheet_name, max_rows=100, max_cols=20)
        
        # Convert to searchable flat text (lowercase for case-insensitive matching)
        flat_text = ' '.join([
            str(cell).lower() if cell is not None else '' 
            for row in data 
            for cell in row
        ])
        
        # Also create a list of all numeric values for checking amounts
        all_numbers = [
            cell for row in data for cell in row 
            if isinstance(cell, (int, float)) and cell != 0
        ]
        
        # Initialize scoring
        points = 0
        max_points = 100
        feedback_parts = []
        
        # ====================================================================
        # CRITERION 1: Loan Data Organization (30 points)
        # ====================================================================
        loan_data_score = 0
        
        # Check for loan-related keywords (basic presence check)
        loan_keywords = ['loan', 'balance', 'interest', 'payment', 'rate']
        loan_keyword_count = sum(1 for kw in loan_keywords if kw in flat_text)
        
        if loan_keyword_count >= 3:
            loan_data_score += 5
        
        # Check for specific loan amounts (with tolerance for rounding)
        expected_amounts = {
            6000: "SoFi/Private Loan 2",
            12500: "Great Lakes/Federal Loan 1", 
            18200: "Navient/Federal Loan 2",
            8300: "Discover/Private Loan 1",
            45000: "Total"
        }
        
        amounts_found = 0
        for amount, description in expected_amounts.items():
            # Check if any number in the spreadsheet is close to this amount
            if any(isinstance(cell, (int, float)) and abs(cell - amount) < 100 
                   for cell in all_numbers):
                amounts_found += 1
        
        if amounts_found >= 4:
            loan_data_score += 15
            feedback_parts.append(f"✅ Loan balances present ({amounts_found}/5 amounts found)")
        elif amounts_found >= 2:
            loan_data_score += 8
            feedback_parts.append(f"⚠️  Some loan balances present ({amounts_found}/5)")
        else:
            feedback_parts.append(f"❌ Loan balances missing or incorrect ({amounts_found}/5)")
        
        # Check for interest rates (as decimals or percentages)
        expected_rates = [3.9, 4.5, 5.8, 7.2, 0.039, 0.045, 0.058, 0.072]
        rates_found = 0
        
        for rate in expected_rates:
            if any(isinstance(cell, (int, float)) and abs(cell - rate) < 0.1 
                   for cell in all_numbers):
                rates_found += 1
        
        # Count unique rates (avoid double-counting decimal and percentage forms)
        unique_rates = min(rates_found, 4)
        
        if unique_rates >= 3:
            loan_data_score += 10
            feedback_parts.append(f"✅ Interest rates included ({unique_rates}/4)")
        elif unique_rates >= 2:
            loan_data_score += 5
            feedback_parts.append(f"⚠️  Some interest rates present ({unique_rates}/4)")
        else:
            feedback_parts.append(f"❌ Interest rates missing or incorrect")
        
        points += loan_data_score
        
        # ====================================================================
        # CRITERION 2: Strategy Comparison (40 points)
        # ====================================================================
        strategy_score = 0
        
        # Check for strategy names
        strategies = {
            'snowball': False,
            'avalanche': False,
            'current': False,
            'even': False
        }
        
        for strategy_name in strategies.keys():
            if strategy_name in flat_text:
                strategies[strategy_name] = True
        
        # At least 2 distinct strategies should be mentioned
        strategies_found = sum(strategies.values())
        
        if strategies_found >= 3:
            strategy_score += 15
            feedback_parts.append(f"✅ Multiple strategies identified ({strategies_found} strategies)")
        elif strategies_found >= 2:
            strategy_score += 10
            feedback_parts.append(f"⚠️  Some strategies present ({strategies_found}/3)")
        else:
            feedback_parts.append(f"❌ Strategy comparison missing (only {strategies_found} strategy found)")
        
        # Check for comparison metrics
        metrics = ['interest', 'total', 'month', 'payoff', 'paid', 'time']
        metrics_found = sum(1 for m in metrics if m in flat_text)
        
        if metrics_found >= 3:
            strategy_score += 15
            feedback_parts.append("✅ Comparison metrics present (interest, payoff time, etc.)")
        elif metrics_found >= 2:
            strategy_score += 8
            feedback_parts.append(f"⚠️  Some comparison metrics present ({metrics_found}/3+)")
        else:
            feedback_parts.append("❌ Comparison metrics incomplete")
        
        # Check for realistic interest calculations
        # Expected total interest paid: roughly $5,000-$12,000 depending on strategy
        # Snowball: ~$8,500, Avalanche: ~$7,800, Even: ~$8,200 (rough estimates)
        interest_values = [
            cell for cell in all_numbers 
            if 3000 < cell < 15000
        ]
        
        if len(interest_values) >= 2:
            strategy_score += 10
            feedback_parts.append(f"✅ Interest calculations present ({len(interest_values)} values in reasonable range)")
        elif len(interest_values) >= 1:
            strategy_score += 5
            feedback_parts.append("⚠️  Some interest calculations may be present")
        else:
            feedback_parts.append("❌ Interest calculations appear to be missing")
        
        points += strategy_score
        
        # ====================================================================
        # CRITERION 3: Formulas Used (15 points)
        # ====================================================================
        formula_score = 0
        formula_count = 0
        
        # Check for formulas in the spreadsheet
        for row in sheet.iter_rows(max_row=100, max_col=20):
            for cell in row:
                if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                    formula_count += 1
        
        if formula_count >= 5:
            formula_score = 15
            feedback_parts.append(f"✅ Formulas used extensively ({formula_count} formulas found)")
        elif formula_count >= 3:
            formula_score = 12
            feedback_parts.append(f"✅ Formulas used ({formula_count} formulas found)")
        elif formula_count >= 1:
            formula_score = 7
            feedback_parts.append(f"⚠️  Some formulas present ({formula_count}), but more recommended")
        else:
            feedback_parts.append("❌ No formulas detected - calculations should use formulas")
        
        points += formula_score
        
        # ====================================================================
        # CRITERION 4: Professional Formatting (15 points)
        # ====================================================================
        formatting_score = 0
        
        # Check for currency formatting
        currency_count = 0
        percent_count = 0
        bold_count = 0
        
        for row in sheet.iter_rows(max_row=50, max_col=15):
            for cell in row:
                # Check currency formatting
                if cell.number_format and ('$' in str(cell.number_format) or 
                                          'currency' in str(cell.number_format).lower()):
                    currency_count += 1
                
                # Check percentage formatting
                if cell.number_format and ('%' in str(cell.number_format) or 
                                          'percent' in str(cell.number_format).lower()):
                    percent_count += 1
                
                # Check bold formatting
                if cell.font and cell.font.bold:
                    bold_count += 1
        
        # Currency formatting (8 points)
        if currency_count >= 8:
            formatting_score += 8
            feedback_parts.append(f"✅ Currency formatting applied ({currency_count} cells)")
        elif currency_count >= 4:
            formatting_score += 5
            feedback_parts.append(f"⚠️  Some currency formatting ({currency_count} cells)")
        elif currency_count >= 1:
            formatting_score += 2
            feedback_parts.append(f"⚠️  Minimal currency formatting ({currency_count} cells)")
        
        # Bold headers (7 points)
        if bold_count >= 5:
            formatting_score += 7
            feedback_parts.append(f"✅ Bold headers used ({bold_count} bold cells)")
        elif bold_count >= 3:
            formatting_score += 4
            feedback_parts.append(f"⚠️  Some bold formatting ({bold_count} cells)")
        elif bold_count >= 1:
            formatting_score += 2
            feedback_parts.append(f"⚠️  Minimal bold formatting ({bold_count} cells)")
        
        points += formatting_score
        
        # ====================================================================
        # Calculate Final Score
        # ====================================================================
        score = points / max_points
        passed = score >= 0.70
        
        # Build final feedback with summary
        summary = f"📊 Score: {points}/{max_points} ({int(score * 100)}%)"
        if passed:
            summary += " - PASSED ✅"
        else:
            summary += " - NEEDS IMPROVEMENT ❌"
        
        feedback = summary + " | " + " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
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
        # Cleanup temporary file
        if temp_file and Path(temp_file.name).exists():
            try:
                Path(temp_file.name).unlink()
                logger.debug(f"Cleaned up temp file: {temp_file.name}")
            except Exception as e:
                logger.warning(f"Failed to cleanup temp file: {e}")