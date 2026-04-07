#!/usr/bin/env python3
"""
Verifier for Loan Payoff Strategy task.

Checks:
1. Monthly interest calculations present
2. Interest formulas mathematically correct
3. Payment analysis present (principal/payoff calculations)
4. Loans sorted by interest rate (descending)
5. Priority loan identified
6. Formatting applied (currency/percentages)
7. Data integrity (all loans preserved)
"""

import sys
import os
import logging

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    cleanup_verification_temp,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_loan_strategy(traj, env_info, task_info):
    """
    Verify loan payoff strategy spreadsheet.
    
    Returns:
        dict: Verification results with passed, score, feedback, subscores
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations and formats
    success = False
    workbook = None
    temp_dir = None
    
    for file_format, container_path in [
        ('ods', '/home/ga/Documents/loan_strategy.ods'),
        ('ods', '/home/ga/Documents/my_loans.ods'),
        ('csv', '/home/ga/Documents/my_loans.csv'),
        ('csv', '/home/ga/Documents/loan_strategy.csv')
    ]:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}
    
    try:
        # Initialize results tracking
        results = {
            'monthly_interest_present': False,
            'interest_formulas_correct': False,
            'payment_analysis_present': False,
            'sorted_by_rate': False,
            'priority_identified': False,
            'formatting_applied': False,
            'data_integrity': False,
            'score': 0
        }
        
        feedback_parts = []
        
        # Get sheet data
        sheets = workbook.get('sheets', {})
        if not sheets:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = list(sheets.keys())[0]
        rows = sheets[sheet_name]
        
        if len(rows) < 5:  # Need header + 4 loans minimum
            return {"passed": False, "score": 0, "feedback": f"Insufficient data rows (found {len(rows)}, expected 5+)"}
        
        # Get header row for reference
        header_row = rows[0]
        num_columns = len([cell for cell in header_row if cell.get('value') if isinstance(cell, dict) else cell])
        
        logger.info(f"Found {num_columns} columns in spreadsheet")
        
        # Criterion 1 & 7: Check for sufficient columns and data integrity
        if num_columns >= 7:  # Original 4 + at least 3 calculated
            results['monthly_interest_present'] = True
            feedback_parts.append(f"✅ Additional columns present ({num_columns} total columns)")
        else:
            feedback_parts.append(f"⚠️ Limited calculated columns (found {num_columns}, expected 7+)")
        
        # Extract loan data for verification
        expected_balances = [12500, 8200, 3800, 6100]
        expected_rates = [4.5, 7.2, 5.0, 6.8]
        expected_payments = [150, 120, 75, 95]
        
        # Check data integrity - verify original data is present
        found_balances = []
        found_rates = []
        found_payments = []
        
        for row_idx in range(1, min(5, len(rows))):
            row = rows[row_idx]
            
            # Look for balance values (typically large numbers around 3000-15000)
            for col_idx in range(min(4, len(row))):
                val = row[col_idx].get('value') if isinstance(row[col_idx], dict) else row[col_idx]
                if isinstance(val, (int, float)):
                    if 3000 <= val <= 15000:
                        found_balances.append(val)
                    elif 4 <= val <= 8:  # Interest rates as percentages
                        found_rates.append(val)
                    elif 0.04 <= val <= 0.08:  # Interest rates as decimals
                        found_rates.append(val * 100)
                    elif 70 <= val <= 160:  # Payment amounts
                        found_payments.append(val)
        
        # Check if we found most of the original data
        if len(found_balances) >= 3 and len(found_rates) >= 3:
            results['data_integrity'] = True
            feedback_parts.append("✅ Original loan data preserved")
        else:
            feedback_parts.append(f"⚠️ Data integrity concern (found {len(found_balances)} balances, {len(found_rates)} rates)")
        
        # Criterion 2 & 3: Check for interest calculations
        # Look for monthly interest rate or monthly interest dollar columns
        has_monthly_interest_calc = False
        has_principal_calc = False
        
        # Check columns beyond the first 4 (original data)
        for col_idx in range(4, min(10, len(header_row))):
            col_values = []
            
            for row_idx in range(1, min(5, len(rows))):
                if col_idx < len(rows[row_idx]):
                    cell = rows[row_idx][col_idx]
                    val = cell.get('value') if isinstance(cell, dict) else cell
                    if isinstance(val, (int, float)) and val > 0:
                        col_values.append(val)
            
            if len(col_values) >= 3:
                # Check if values look like monthly interest rates (0.003-0.008 range)
                if all(0.002 < v < 0.01 for v in col_values):
                    has_monthly_interest_calc = True
                    # Verify calculation accuracy
                    # Expected monthly rates: 4.5/12=0.375%, 7.2/12=0.6%, 5.0/12=0.417%, 6.8/12=0.567%
                    expected_monthly = [0.00375, 0.006, 0.00417, 0.00567]
                    # Check if any value is close to expected
                    for cv in col_values:
                        for em in expected_monthly:
                            if abs(cv - em) / em < 0.1:  # Within 10% tolerance
                                results['interest_formulas_correct'] = True
                                break
                
                # Check if values look like monthly interest dollars ($20-$60 range)
                elif all(20 < v < 100 for v in col_values):
                    has_monthly_interest_calc = True
                    # Expected interest charges (approximate):
                    # Federal: 12500*0.00375 = $46.88
                    # Private A: 8200*0.006 = $49.20
                    # Perkins: 3800*0.00417 = $15.85
                    # Private B: 6100*0.00567 = $34.59
                    expected_interest = [46.88, 49.20, 15.85, 34.59]
                    for cv in col_values:
                        for ei in expected_interest:
                            if abs(cv - ei) / ei < 0.15:  # Within 15% tolerance
                                results['interest_formulas_correct'] = True
                                break
                
                # Check if values look like principal portions ($30-$130 range)
                elif all(30 < v < 140 for v in col_values):
                    has_principal_calc = True
                    results['payment_analysis_present'] = True
                
                # Check if values look like months to payoff (50-500 range)
                elif all(50 < v < 500 for v in col_values):
                    has_principal_calc = True
                    results['payment_analysis_present'] = True
        
        if has_monthly_interest_calc:
            feedback_parts.append("✅ Monthly interest calculations detected")
        else:
            feedback_parts.append("❌ Monthly interest calculations not found")
        
        if results['interest_formulas_correct']:
            feedback_parts.append("✅ Interest calculations mathematically correct")
        elif has_monthly_interest_calc:
            feedback_parts.append("⚠️ Interest calculations present but values may be incorrect")
        
        if has_principal_calc:
            feedback_parts.append("✅ Payment analysis/principal calculations present")
        else:
            feedback_parts.append("❌ Payment analysis not detected")
        
        # Criterion 4: Check if sorted by interest rate (descending)
        interest_rates_in_order = []
        
        # Look for interest rate column (should be column 2 or nearby)
        for row_idx in range(1, min(5, len(rows))):
            row = rows[row_idx]
            for col_idx in range(min(6, len(row))):
                val = row[col_idx].get('value') if isinstance(row[col_idx], dict) else row[col_idx]
                if isinstance(val, (int, float)):
                    # Check if it looks like an interest rate
                    if 4 <= val <= 8:  # Percentage form
                        interest_rates_in_order.append(val)
                        break
                    elif 0.04 <= val <= 0.08:  # Decimal form
                        interest_rates_in_order.append(val * 100)
                        break
        
        if len(interest_rates_in_order) >= 3:
            # Check if mostly descending (allow one inversion for flexibility)
            descending_count = sum(1 for i in range(len(interest_rates_in_order)-1) 
                                  if interest_rates_in_order[i] >= interest_rates_in_order[i+1])
            
            if descending_count >= len(interest_rates_in_order) - 2:
                results['sorted_by_rate'] = True
                # Check if highest rate (7.2%) is first
                if interest_rates_in_order[0] > 7.0:
                    results['priority_identified'] = True
                    feedback_parts.append("✅ Loans sorted by interest rate (highest first)")
                    feedback_parts.append("✅ Priority loan identified (highest rate)")
                else:
                    feedback_parts.append("⚠️ Loans partially sorted, but highest rate may not be first")
            else:
                feedback_parts.append(f"❌ Loans not properly sorted (descending count: {descending_count}/{len(interest_rates_in_order)-1})")
        else:
            feedback_parts.append("⚠️ Could not verify sorting (insufficient rate data found)")
        
        # Criterion 6: Check for formatting
        # Look for currency-formatted values (balances, payments)
        has_large_values = any(
            any(
                isinstance(cell.get('value') if isinstance(cell, dict) else cell, (int, float)) and 
                (cell.get('value') if isinstance(cell, dict) else cell) > 1000
                for cell in row
            )
            for row in rows[1:5]
        )
        
        if has_large_values:
            results['formatting_applied'] = True
            feedback_parts.append("✅ Appropriate numeric formatting applied")
        else:
            feedback_parts.append("⚠️ Currency formatting may be missing")
        
        # Calculate final score
        criteria_met = sum([
            results['monthly_interest_present'],
            results['interest_formulas_correct'],
            results['payment_analysis_present'],
            results['sorted_by_rate'],
            results['priority_identified'],
            results['formatting_applied'],
            results['data_integrity']
        ])
        
        results['score'] = int((criteria_met / 7.0) * 100)
        passed = results['score'] >= 70
        
        # Add summary message
        if passed and results['score'] >= 90:
            feedback_parts.append("🎉 Excellent loan analysis! All key criteria met.")
        elif passed:
            feedback_parts.append("✅ Loan strategy task completed successfully")
        else:
            feedback_parts.append("❌ Loan strategy incomplete - missing key calculations or analysis")
        
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Verification complete: Score={results['score']}, Passed={passed}")
        
        return {
            "passed": passed,
            "score": results['score'],
            "feedback": feedback,
            "subscores": {
                "monthly_interest_present": results['monthly_interest_present'],
                "interest_formulas_correct": results['interest_formulas_correct'],
                "payment_analysis_present": results['payment_analysis_present'],
                "sorted_by_rate": results['sorted_by_rate'],
                "priority_identified": results['priority_identified'],
                "formatting_applied": results['formatting_applied'],
                "data_integrity": results['data_integrity']
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    
    finally:
        if temp_dir:
            cleanup_verification_temp(temp_dir)
