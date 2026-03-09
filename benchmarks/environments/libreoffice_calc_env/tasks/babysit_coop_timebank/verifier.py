#!/usr/bin/env python3
"""
Verifier for Babysitting Co-op Time Bank Reconciliation task
"""

import sys
import os
import logging
import re
from typing import Dict, List, Tuple, Optional

# Add utils to path (relative path for host machine execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    check_conditional_formatting
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_family_name(name: str) -> str:
    """
    Normalize family names to handle variations.
    E.g., "Johnson", "Johnsons", "Johnson Family" all map to "Johnson"
    """
    if not name:
        return ""
    
    name = str(name).strip()
    # Remove "Family" suffix
    name = re.sub(r'\s+Family$', '', name, flags=re.IGNORECASE)
    # Remove trailing 's' for plural forms
    name = re.sub(r's$', '', name)
    return name


def calculate_expected_balances(transactions: List[Dict]) -> Dict[str, Dict[str, float]]:
    """
    Calculate expected balances from transaction log.
    
    Returns:
        Dict mapping normalized family name to {earned, spent, balance}
    """
    balances = {}
    
    for trans in transactions:
        provider = normalize_family_name(trans.get('provider', ''))
        client = normalize_family_name(trans.get('client', ''))
        hours = trans.get('hours', 0.0)
        
        if not provider or not client:
            continue
            
        # Provider earns hours
        if provider not in balances:
            balances[provider] = {'earned': 0.0, 'spent': 0.0, 'balance': 0.0}
        balances[provider]['earned'] += hours
        
        # Client spends hours
        if client not in balances:
            balances[client] = {'earned': 0.0, 'spent': 0.0, 'balance': 0.0}
        balances[client]['spent'] += hours
    
    # Calculate balances
    for family in balances:
        balances[family]['balance'] = balances[family]['earned'] - balances[family]['spent']
    
    return balances


def parse_transaction_log(workbook: Dict, sheet_name: str) -> List[Dict]:
    """
    Parse transaction log from spreadsheet.
    
    Returns:
        List of transaction dicts with keys: provider, client, hours
    """
    transactions = []
    sheet_rows = workbook['sheets'][sheet_name]
    
    # Skip header row (row 0)
    for row_idx in range(1, len(sheet_rows)):
        row = sheet_rows[row_idx]
        if len(row) < 4:
            continue
        
        # Columns: Date, Provider Family, Client Family, Hours
        provider_cell = row[1] if len(row) > 1 else {}
        client_cell = row[2] if len(row) > 2 else {}
        hours_cell = row[3] if len(row) > 3 else {}
        
        provider = provider_cell.get('value') if isinstance(provider_cell, dict) else provider_cell
        client = client_cell.get('value') if isinstance(client_cell, dict) else client_cell
        hours = hours_cell.get('value') if isinstance(hours_cell, dict) else hours_cell
        
        # Skip empty rows
        if not provider or not client or not hours:
            continue
        
        try:
            hours = float(hours)
        except (ValueError, TypeError):
            continue
        
        transactions.append({
            'provider': provider,
            'client': client,
            'hours': hours
        })
    
    return transactions


def find_summary_table(workbook: Dict, sheet_name: str) -> Optional[Dict]:
    """
    Find the summary table in the spreadsheet.
    Looks for columns with headers containing keywords: Family, Earned, Spent, Balance
    
    Returns:
        Dict with keys: family_col, earned_col, spent_col, balance_col, start_row
        or None if not found
    """
    sheet_rows = workbook['sheets'][sheet_name]
    
    # Search first 10 rows for headers
    for row_idx in range(min(10, len(sheet_rows))):
        row = sheet_rows[row_idx]
        
        # Look for header keywords in this row
        family_col = None
        earned_col = None
        spent_col = None
        balance_col = None
        
        for col_idx, cell in enumerate(row):
            value = cell.get('value') if isinstance(cell, dict) else cell
            if not value:
                continue
            
            value_str = str(value).lower()
            
            if 'family' in value_str and 'name' in value_str:
                family_col = col_idx
            elif 'earned' in value_str or 'provider' in value_str:
                earned_col = col_idx
            elif 'spent' in value_str or 'client' in value_str or 'received' in value_str:
                spent_col = col_idx
            elif 'balance' in value_str or 'net' in value_str:
                balance_col = col_idx
        
        # If we found at least 3 of the 4 columns, consider this the header row
        found_cols = sum([
            family_col is not None,
            earned_col is not None,
            spent_col is not None,
            balance_col is not None
        ])
        
        if found_cols >= 3:
            return {
                'family_col': family_col,
                'earned_col': earned_col,
                'spent_col': spent_col,
                'balance_col': balance_col,
                'start_row': row_idx + 1  # Data starts next row
            }
    
    return None


def extract_summary_data(workbook: Dict, sheet_name: str, table_info: Dict) -> List[Dict]:
    """
    Extract summary data from the summary table.
    
    Returns:
        List of dicts with keys: family, earned, spent, balance, earned_formula, spent_formula, balance_formula
    """
    sheet_rows = workbook['sheets'][sheet_name]
    summary_data = []
    
    start_row = table_info['start_row']
    family_col = table_info.get('family_col')
    earned_col = table_info.get('earned_col')
    spent_col = table_info.get('spent_col')
    balance_col = table_info.get('balance_col')
    
    # Extract up to 15 rows of data (reasonable max for families)
    for row_idx in range(start_row, min(start_row + 15, len(sheet_rows))):
        row = sheet_rows[row_idx]
        
        # Get family name
        if family_col is not None and family_col < len(row):
            family_cell = row[family_col]
            family = family_cell.get('value') if isinstance(family_cell, dict) else family_cell
        else:
            family = None
        
        # Skip empty rows
        if not family or str(family).strip() == '':
            continue
        
        # Get earned hours
        earned = None
        earned_formula = None
        if earned_col is not None and earned_col < len(row):
            earned_cell = row[earned_col]
            earned = earned_cell.get('value') if isinstance(earned_cell, dict) else earned_cell
            earned_formula = earned_cell.get('formula') if isinstance(earned_cell, dict) else None
        
        # Get spent hours
        spent = None
        spent_formula = None
        if spent_col is not None and spent_col < len(row):
            spent_cell = row[spent_col]
            spent = spent_cell.get('value') if isinstance(spent_cell, dict) else spent_cell
            spent_formula = spent_cell.get('formula') if isinstance(spent_cell, dict) else None
        
        # Get balance
        balance = None
        balance_formula = None
        if balance_col is not None and balance_col < len(row):
            balance_cell = row[balance_col]
            balance = balance_cell.get('value') if isinstance(balance_cell, dict) else balance_cell
            balance_formula = balance_cell.get('formula') if isinstance(balance_cell, dict) else None
        
        summary_data.append({
            'family': family,
            'earned': earned,
            'spent': spent,
            'balance': balance,
            'earned_formula': earned_formula,
            'spent_formula': spent_formula,
            'balance_formula': balance_formula
        })
    
    return summary_data


def check_sumif_formula(formula: str) -> bool:
    """Check if formula contains SUMIF or SUMIFS"""
    if not formula:
        return False
    formula_upper = formula.upper()
    return 'SUMIF' in formula_upper


def check_arithmetic_formula(formula: str) -> bool:
    """Check if formula contains arithmetic operations (-, +)"""
    if not formula:
        return False
    # Look for subtraction or reference to other cells
    return '-' in formula or ('+' in formula and any(c.isalpha() for c in formula))


def verify_babysit_coop_timebank(traj, env_info, task_info):
    """
    Verify babysitting co-op time bank reconciliation task completion.
    
    Checks:
    1. Summary table exists with appropriate columns
    2. SUMIF formulas used for Hours Earned
    3. SUMIF formulas used for Hours Spent
    4. Balance calculated with formula (earned - spent)
    5. Calculations are accurate (within tolerance)
    6. Conditional formatting applied for balance < -5
    7. At least one family flagged with balance < -5
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try to load the reconciled file
    container_path = "/home/ga/Documents/babysit_coop_reconciled.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )
    
    # Fallback to CSV if ODS not found
    if not success:
        container_path = "/home/ga/Documents/babysit_coop_transactions.csv"
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format='csv'
        )
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        # Get first sheet
        sheet_name = list(workbook['sheets'].keys())[0]
        
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []
        
        # Parse transaction log to calculate expected balances
        transactions = parse_transaction_log(workbook, sheet_name)
        expected_balances = calculate_expected_balances(transactions)
        
        logger.info(f"Parsed {len(transactions)} transactions")
        logger.info(f"Expected balances for {len(expected_balances)} families")
        
        # Criterion 1: Summary table exists
        table_info = find_summary_table(workbook, sheet_name)
        
        if table_info and all([
            table_info.get('family_col') is not None,
            table_info.get('earned_col') is not None,
            table_info.get('spent_col') is not None,
            table_info.get('balance_col') is not None
        ]):
            criteria_passed += 1
            feedback_parts.append("✅ Summary table structure found")
            logger.info(f"Summary table found: {table_info}")
        else:
            feedback_parts.append("❌ Summary table not found or incomplete")
            # Can't proceed without table
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts) + " | Cannot verify task without summary table"
            }
        
        # Extract summary data
        summary_data = extract_summary_data(workbook, sheet_name, table_info)
        
        if len(summary_data) < 3:
            feedback_parts.append(f"❌ Insufficient families in summary (found {len(summary_data)}, need at least 3)")
        else:
            logger.info(f"Found {len(summary_data)} families in summary")
        
        # Criterion 2: SUMIF formulas in Hours Earned
        earned_formulas = [row['earned_formula'] for row in summary_data if row['earned_formula']]
        sumif_earned = sum(1 for f in earned_formulas if check_sumif_formula(f))
        
        if sumif_earned >= len(summary_data) * 0.5:  # At least half use SUMIF
            criteria_passed += 1
            feedback_parts.append(f"✅ SUMIF formulas found in Hours Earned ({sumif_earned}/{len(summary_data)})")
        else:
            feedback_parts.append(f"❌ SUMIF formulas missing in Hours Earned ({sumif_earned}/{len(summary_data)})")
        
        # Criterion 3: SUMIF formulas in Hours Spent
        spent_formulas = [row['spent_formula'] for row in summary_data if row['spent_formula']]
        sumif_spent = sum(1 for f in spent_formulas if check_sumif_formula(f))
        
        if sumif_spent >= len(summary_data) * 0.5:
            criteria_passed += 1
            feedback_parts.append(f"✅ SUMIF formulas found in Hours Spent ({sumif_spent}/{len(summary_data)})")
        else:
            feedback_parts.append(f"❌ SUMIF formulas missing in Hours Spent ({sumif_spent}/{len(summary_data)})")
        
        # Criterion 4: Balance calculated with formula
        balance_formulas = [row['balance_formula'] for row in summary_data if row['balance_formula']]
        arithmetic_balance = sum(1 for f in balance_formulas if check_arithmetic_formula(f))
        
        if arithmetic_balance >= len(summary_data) * 0.5:
            criteria_passed += 1
            feedback_parts.append(f"✅ Balance formulas found ({arithmetic_balance}/{len(summary_data)})")
        else:
            feedback_parts.append(f"❌ Balance formulas missing ({arithmetic_balance}/{len(summary_data)})")
        
        # Criterion 5: Calculations accurate
        calculation_errors = 0
        tolerance = 0.5  # Allow 0.5 hour tolerance for rounding/name matching
        
        for row in summary_data:
            family_name = normalize_family_name(row['family'])
            actual_balance = row['balance']
            
            if family_name in expected_balances:
                expected = expected_balances[family_name]
                
                try:
                    actual_bal = float(actual_balance) if actual_balance is not None else 0.0
                    expected_bal = expected['balance']
                    
                    if abs(actual_bal - expected_bal) > tolerance:
                        calculation_errors += 1
                        logger.warning(f"Balance mismatch for {family_name}: expected {expected_bal}, got {actual_bal}")
                except (ValueError, TypeError):
                    calculation_errors += 1
        
        accuracy_rate = 1.0 - (calculation_errors / max(len(summary_data), 1))
        
        if accuracy_rate >= 0.7:  # At least 70% accurate
            criteria_passed += 1
            feedback_parts.append(f"✅ Calculations accurate ({int(accuracy_rate*100)}% correct)")
        else:
            feedback_parts.append(f"❌ Calculation errors detected ({int(accuracy_rate*100)}% correct)")
        
        # Criterion 6: Conditional formatting applied
        # This is tricky - need to check ODS file for formatting rules
        has_cond_format = check_conditional_formatting(workbook, sheet_name, "I:I")  # Assume balance in column I
        
        if has_cond_format:
            criteria_passed += 1
            feedback_parts.append("✅ Conditional formatting detected")
        else:
            # Try alternative check - look for any conditional formatting in the sheet
            feedback_parts.append("⚠️ Conditional formatting not detected (may still exist)")
            # Give partial credit
            criteria_passed += 0.5
        
        # Criterion 7: At least one family with balance < -5
        negative_balances = []
        for row in summary_data:
            try:
                balance = float(row['balance']) if row['balance'] is not None else 0.0
                if balance < -5:
                    negative_balances.append((row['family'], balance))
            except (ValueError, TypeError):
                continue
        
        if len(negative_balances) >= 1:
            criteria_passed += 1
            feedback_parts.append(f"✅ Problem accounts identified ({len(negative_balances)} families with balance < -5)")
        else:
            feedback_parts.append("❌ No families with balance < -5 (check calculations)")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "summary_table_exists": table_info is not None,
                "sumif_earned": sumif_earned >= len(summary_data) * 0.5,
                "sumif_spent": sumif_spent >= len(summary_data) * 0.5,
                "balance_formula": arithmetic_balance >= len(summary_data) * 0.5,
                "calculations_accurate": accuracy_rate >= 0.7,
                "conditional_formatting": has_cond_format,
                "problem_accounts_flagged": len(negative_balances) >= 1
            },
            "details": {
                "families_in_summary": len(summary_data),
                "calculation_accuracy": f"{int(accuracy_rate*100)}%",
                "families_flagged": len(negative_balances)
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
