#!/usr/bin/env python3
"""
Verifier for Credit Card Rewards Optimization task
"""

import sys
import os
import logging
import re

# Add utils to path - use relative path for host execution
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_cc_rewards_optimizer(traj, env_info, task_info):
    """
    Verify credit card rewards optimization task completion.
    
    Checks:
    1. All transactions have categories (no blank category cells)
    2. Optimal_Card column exists with valid card names
    3. Calculations are correct (spot-check)
    4. Analysis sheet has summary totals
    5. Category recommendation table exists
    6. Formulas are used (not just values)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/cc_rewards_analysis.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        sheets = workbook.get('sheets', {})
        if not sheets:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_names = list(sheets.keys())
        
        # Find sheet names (case-insensitive)
        transactions_sheet = None
        card_details_sheet = None
        analysis_sheet = None
        
        for name in sheet_names:
            name_lower = name.lower()
            if 'transaction' in name_lower:
                transactions_sheet = name
            elif 'card' in name_lower or 'detail' in name_lower:
                card_details_sheet = name
            elif 'analysis' in name_lower:
                analysis_sheet = name
        
        if not transactions_sheet:
            return {"passed": False, "score": 0, "feedback": "Transactions sheet not found"}
        
        if not card_details_sheet:
            return {"passed": False, "score": 0, "feedback": "Card_Details sheet not found"}
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}

        # Get transactions data
        transactions_data = sheets[transactions_sheet]
        
        # Criterion 1: All transactions have categories
        category_col_idx = None
        optimal_card_col_idx = None
        actual_rewards_col_idx = None
        optimal_rewards_col_idx = None
        opportunity_cost_col_idx = None
        
        # Find column indices from header row
        if len(transactions_data) > 0:
            header_row = transactions_data[0]
            for idx, cell in enumerate(header_row):
                cell_value = cell.get('value', '') if isinstance(cell, dict) else str(cell)
                cell_value_lower = str(cell_value).lower().strip()
                
                if 'category' in cell_value_lower:
                    category_col_idx = idx
                elif 'optimal' in cell_value_lower and 'card' in cell_value_lower:
                    optimal_card_col_idx = idx
                elif 'actual' in cell_value_lower and 'reward' in cell_value_lower:
                    actual_rewards_col_idx = idx
                elif 'optimal' in cell_value_lower and 'reward' in cell_value_lower:
                    optimal_rewards_col_idx = idx
                elif 'opportunity' in cell_value_lower or 'cost' in cell_value_lower:
                    opportunity_cost_col_idx = idx
        
        # Check all categories are filled
        all_categorized = True
        blank_count = 0
        if category_col_idx is not None:
            for row_idx in range(1, min(len(transactions_data), 36)):  # Skip header, check up to 35 transactions
                if row_idx < len(transactions_data):
                    row = transactions_data[row_idx]
                    if category_col_idx < len(row):
                        cell = row[category_col_idx]
                        value = cell.get('value', '') if isinstance(cell, dict) else str(cell)
                        if not value or str(value).strip() == '':
                            all_categorized = False
                            blank_count += 1
        
        if all_categorized and category_col_idx is not None:
            criteria_passed += 1
            subscores['all_categorized'] = True
            feedback_parts.append("✅ All transactions categorized")
        else:
            subscores['all_categorized'] = False
            feedback_parts.append(f"❌ {blank_count} transactions missing categories")
        
        # Criterion 2: Optimal_Card column exists with valid card names
        optimal_card_exists = optimal_card_col_idx is not None
        valid_cards = {'chase freedom', 'discover', 'amex blue preferred', 'citi double cash'}
        
        if optimal_card_exists:
            # Check that cells contain valid card names
            valid_card_count = 0
            total_checked = 0
            for row_idx in range(1, min(len(transactions_data), 11)):  # Check first 10 transactions
                if row_idx < len(transactions_data):
                    row = transactions_data[row_idx]
                    if optimal_card_col_idx < len(row):
                        cell = row[optimal_card_col_idx]
                        value = cell.get('value', '') if isinstance(cell, dict) else str(cell)
                        if value and str(value).strip():
                            total_checked += 1
                            if any(card in str(value).lower() for card in valid_cards):
                                valid_card_count += 1
            
            if total_checked > 0 and valid_card_count >= total_checked * 0.8:  # At least 80% valid
                criteria_passed += 1
                subscores['optimal_card_identified'] = True
                feedback_parts.append(f"✅ Optimal_Card column present ({valid_card_count}/{total_checked} valid)")
            else:
                subscores['optimal_card_identified'] = False
                feedback_parts.append(f"⚠️ Optimal_Card column found but values may be incorrect ({valid_card_count}/{total_checked})")
        else:
            subscores['optimal_card_identified'] = False
            feedback_parts.append("❌ Optimal_Card column not found")
        
        # Criterion 3: Calculations correct (spot-check)
        # Check if reward calculation columns exist
        has_calculations = (actual_rewards_col_idx is not None and 
                          optimal_rewards_col_idx is not None and 
                          opportunity_cost_col_idx is not None)
        
        calculations_correct = False
        if has_calculations:
            # Spot-check a few rows for correct calculation
            correct_count = 0
            checked_count = 0
            
            for row_idx in range(1, min(len(transactions_data), 6)):  # Check first 5 transactions
                if row_idx < len(transactions_data):
                    row = transactions_data[row_idx]
                    
                    # Get values
                    actual_val = None
                    optimal_val = None
                    opportunity_val = None
                    
                    if actual_rewards_col_idx < len(row):
                        cell = row[actual_rewards_col_idx]
                        actual_val = cell.get('value', None) if isinstance(cell, dict) else cell
                    
                    if optimal_rewards_col_idx < len(row):
                        cell = row[optimal_rewards_col_idx]
                        optimal_val = cell.get('value', None) if isinstance(cell, dict) else cell
                    
                    if opportunity_cost_col_idx < len(row):
                        cell = row[opportunity_cost_col_idx]
                        opportunity_val = cell.get('value', None) if isinstance(cell, dict) else cell
                    
                    # Check if opportunity = optimal - actual (with tolerance)
                    if actual_val is not None and optimal_val is not None and opportunity_val is not None:
                        try:
                            actual_float = float(actual_val)
                            optimal_float = float(optimal_val)
                            opportunity_float = float(opportunity_val)
                            expected_opportunity = optimal_float - actual_float
                            
                            if abs(opportunity_float - expected_opportunity) < 0.02:  # 2 cent tolerance
                                correct_count += 1
                            checked_count += 1
                        except (ValueError, TypeError):
                            pass
            
            if checked_count > 0 and correct_count >= checked_count * 0.8:
                criteria_passed += 1
                calculations_correct = True
                subscores['calculations_correct'] = True
                feedback_parts.append(f"✅ Calculations verified correct ({correct_count}/{checked_count} spot-checks)")
            else:
                subscores['calculations_correct'] = False
                feedback_parts.append(f"⚠️ Calculation issues detected ({correct_count}/{checked_count} correct)")
        else:
            subscores['calculations_correct'] = False
            feedback_parts.append("❌ Reward calculation columns not found")
        
        # Criterion 4: Analysis sheet has summary totals
        summary_exists = False
        if analysis_sheet:
            analysis_data = sheets[analysis_sheet]
            
            # Look for summary values (numeric values that might be totals)
            numeric_values_found = 0
            formulas_found = 0
            
            for row in analysis_data[:20]:  # Check first 20 rows
                for cell in row:
                    if isinstance(cell, dict):
                        value = cell.get('value')
                        formula = cell.get('formula')
                        
                        if formula and 'SUM' in str(formula).upper():
                            formulas_found += 1
                        
                        if value is not None:
                            try:
                                float_val = float(value)
                                if float_val > 0:  # Positive numeric value
                                    numeric_values_found += 1
                            except (ValueError, TypeError):
                                pass
            
            if formulas_found >= 2 or numeric_values_found >= 3:  # At least 2 SUM formulas or 3 numeric summaries
                criteria_passed += 1
                summary_exists = True
                subscores['summary_present'] = True
                feedback_parts.append(f"✅ Analysis sheet has summary ({formulas_found} SUM formulas, {numeric_values_found} values)")
            else:
                subscores['summary_present'] = False
                feedback_parts.append(f"⚠️ Analysis sheet incomplete ({formulas_found} formulas, {numeric_values_found} values)")
        else:
            subscores['summary_present'] = False
            feedback_parts.append("❌ Analysis sheet not found")
        
        # Criterion 5: Category recommendation table exists
        recommendation_exists = False
        if analysis_sheet:
            analysis_data = sheets[analysis_sheet]
            
            # Look for category names in Analysis sheet
            category_keywords = ['groceries', 'gas', 'dining', 'travel', 'general']
            categories_found = 0
            card_names_found = 0
            
            for row in analysis_data[:30]:  # Check first 30 rows
                for cell in row:
                    value = cell.get('value', '') if isinstance(cell, dict) else str(cell)
                    value_lower = str(value).lower().strip()
                    
                    if any(cat in value_lower for cat in category_keywords):
                        categories_found += 1
                    
                    if any(card in value_lower for card in valid_cards):
                        card_names_found += 1
            
            if categories_found >= 4 and card_names_found >= 4:  # At least 4 categories and 4 card recommendations
                criteria_passed += 1
                recommendation_exists = True
                subscores['recommendation_table'] = True
                feedback_parts.append(f"✅ Category recommendation table found ({categories_found} categories)")
            else:
                subscores['recommendation_table'] = False
                feedback_parts.append(f"⚠️ Recommendation table incomplete ({categories_found} categories, {card_names_found} cards)")
        else:
            subscores['recommendation_table'] = False
            feedback_parts.append("❌ No recommendation table in Analysis sheet")
        
        # Criterion 6: Formulas are used (not just hard-coded values)
        formulas_used = False
        formula_count = 0
        
        # Check transactions sheet for formulas
        for row_idx in range(1, min(len(transactions_data), 11)):  # Check first 10 data rows
            if row_idx < len(transactions_data):
                row = transactions_data[row_idx]
                for col_idx in [optimal_card_col_idx, actual_rewards_col_idx, 
                               optimal_rewards_col_idx, opportunity_cost_col_idx]:
                    if col_idx is not None and col_idx < len(row):
                        cell = row[col_idx]
                        if isinstance(cell, dict):
                            formula = cell.get('formula')
                            if formula:
                                formula_count += 1
        
        # Also check Analysis sheet
        if analysis_sheet:
            for row in analysis_data[:20]:
                for cell in row:
                    if isinstance(cell, dict):
                        formula = cell.get('formula')
                        if formula:
                            formula_count += 1
        
        if formula_count >= 10:  # At least 10 formulas used
            criteria_passed += 1
            formulas_used = True
            subscores['formulas_used'] = True
            feedback_parts.append(f"✅ Formulas used throughout ({formula_count} formulas detected)")
        else:
            subscores['formulas_used'] = False
            feedback_parts.append(f"⚠️ Limited formula usage ({formula_count} formulas found)")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 85  # Need 5/6 criteria (85%)
        
        if passed and score >= 95:
            feedback_parts.append("🎉 Excellent credit card optimization analysis!")
        elif passed:
            feedback_parts.append("✅ Credit card rewards analysis completed")
        else:
            feedback_parts.append("❌ Analysis incomplete - needs more work")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
