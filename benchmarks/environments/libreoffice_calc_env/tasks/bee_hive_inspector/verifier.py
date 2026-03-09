#!/usr/bin/env python3
"""
Verifier for Bee Hive Inspector task.

Checks:
1. Health scores calculated for all 5 Week 4 hives
2. Formulas used (not hardcoded values)
3. Scores in valid range (0-23)
4. Domain logic correct (spot checks)
5. Conditional formatting applied
6. At least one at-risk hive identified (<12 score)
"""

import sys
import os
import logging
import re

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    check_conditional_formatting,
    cleanup_verification_temp,
    setup_calc_verification
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def calculate_expected_score(population, brood_frames, honey_stores, disease, queen_seen):
    """
    Calculate expected health score based on task criteria.
    
    Scoring:
    - Population: Strong/>50k=5, Moderate/30-50k=3, Weak/<30k=1
    - Brood: 8+=5, 5-7=3, <5=1
    - Honey: Full/>8=5, Adequate/4-8=3, Low/<4=1
    - Disease: None=5, Possible=2, Confirmed=0
    - Queen: Yes=3, No=0
    """
    score = 0
    
    # Population score
    if isinstance(population, str):
        pop_str = population.lower()
        if 'strong' in pop_str:
            score += 5
        elif 'moderate' in pop_str:
            score += 3
        elif 'weak' in pop_str:
            score += 1
    elif isinstance(population, (int, float)):
        if population > 50000:
            score += 5
        elif population >= 30000:
            score += 3
        else:
            score += 1
    
    # Brood frames score
    if isinstance(brood_frames, (int, float)):
        if brood_frames >= 8:
            score += 5
        elif brood_frames >= 5:
            score += 3
        else:
            score += 1
    
    # Honey stores score
    if isinstance(honey_stores, str):
        honey_str = honey_stores.lower()
        if 'full' in honey_str:
            score += 5
        elif 'adequate' in honey_str:
            score += 3
        elif 'low' in honey_str:
            score += 1
    elif isinstance(honey_stores, (int, float)):
        if honey_stores > 8:
            score += 5
        elif honey_stores >= 4:
            score += 3
        else:
            score += 1
    
    # Disease score
    if isinstance(disease, str):
        disease_str = disease.lower()
        if 'none' in disease_str:
            score += 5
        elif 'possible' in disease_str or 'suspected' in disease_str:
            score += 2
        elif 'confirmed' in disease_str:
            score += 0
    
    # Queen bonus
    if isinstance(queen_seen, str):
        if queen_seen.lower() in ['yes', 'y', 'true']:
            score += 3
    
    return score


def find_week4_data_rows(workbook, sheet_name):
    """
    Find rows containing Week 4 data.
    Returns list of row indices (0-based).
    """
    week4_rows = []
    sheet_rows = workbook['sheets'][sheet_name]
    
    for row_idx, row in enumerate(sheet_rows):
        if len(row) > 0:
            first_cell = row[0]
            cell_value = first_cell.get('value') if isinstance(first_cell, dict) else first_cell
            
            # Check if this row is Week 4
            if cell_value == 4 or cell_value == '4' or str(cell_value) == '4':
                week4_rows.append(row_idx)
    
    return week4_rows


def extract_hive_data(workbook, sheet_name, row_idx):
    """
    Extract hive inspection data from a specific row.
    Returns dict with hive data.
    """
    sheet_rows = workbook['sheets'][sheet_name]
    
    if row_idx >= len(sheet_rows):
        return None
    
    row = sheet_rows[row_idx]
    
    # Expected columns: Week, Hive ID, Date, Population, Brood Frames, Honey Stores, Disease, Queen Seen, [Health Score]
    hive_data = {
        'week': get_cell_value(workbook, sheet_name, f'A{row_idx+1}'),
        'hive_id': get_cell_value(workbook, sheet_name, f'B{row_idx+1}'),
        'date': get_cell_value(workbook, sheet_name, f'C{row_idx+1}'),
        'population': get_cell_value(workbook, sheet_name, f'D{row_idx+1}'),
        'brood_frames': get_cell_value(workbook, sheet_name, f'E{row_idx+1}'),
        'honey_stores': get_cell_value(workbook, sheet_name, f'F{row_idx+1}'),
        'disease': get_cell_value(workbook, sheet_name, f'G{row_idx+1}'),
        'queen_seen': get_cell_value(workbook, sheet_name, f'H{row_idx+1}'),
        'health_score': get_cell_value(workbook, sheet_name, f'I{row_idx+1}'),
        'health_score_formula': get_cell_formula(workbook, sheet_name, f'I{row_idx+1}'),
        'row_idx': row_idx
    }
    
    return hive_data


def verify_bee_hive_inspector(traj, env_info, task_info):
    """
    Verify bee hive inspector task completion.
    
    Checks:
    1. All 5 Week 4 hives have health scores
    2. Scores use formulas (not hardcoded)
    3. Scores in valid range (0-23)
    4. Domain logic correct (spot checks)
    5. Conditional formatting applied
    6. At least one at-risk hive (<12)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try to find the saved file in multiple locations
    temp_dir = None
    success = False
    workbook = None
    
    # Try primary output location
    for file_format, container_path in [
        ('ods', '/home/ga/Documents/bee_colony_health_analysis.ods'),
        ('ods', '/home/ga/Documents/hive_inspections.ods'),
        ('csv', '/home/ga/Documents/hive_inspections.csv'),
        ('ods', '/home/ga/Documents/hive_inspections.ods')
    ]:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded file from: {container_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load spreadsheet file: {error}"
        }
    
    try:
        sheet_name = list(workbook['sheets'].keys())[0]
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # Find Week 4 data rows
        week4_rows = find_week4_data_rows(workbook, sheet_name)
        
        if len(week4_rows) < 5:
            feedback_parts.append(f"❌ Expected 5 Week 4 hives, found {len(week4_rows)}")
            subscores['week4_data_found'] = False
        else:
            feedback_parts.append(f"✅ Found {len(week4_rows)} Week 4 hive records")
            subscores['week4_data_found'] = True
        
        # Extract hive data for Week 4
        week4_hives = []
        for row_idx in week4_rows[:5]:  # Take first 5 Week 4 entries
            hive_data = extract_hive_data(workbook, sheet_name, row_idx)
            if hive_data:
                week4_hives.append(hive_data)
        
        # Criterion 1: All hives have health scores calculated
        hives_with_scores = sum(1 for h in week4_hives if h['health_score'] is not None)
        if hives_with_scores >= 4:  # At least 4 out of 5
            criteria_passed += 1
            feedback_parts.append(f"✅ Health scores calculated ({hives_with_scores}/5 hives)")
            subscores['scores_calculated'] = True
        else:
            feedback_parts.append(f"❌ Only {hives_with_scores}/5 hives have health scores")
            subscores['scores_calculated'] = False
        
        # Criterion 2: Scores use formulas (not hardcoded)
        formula_count = sum(1 for h in week4_hives if h['health_score_formula'] is not None)
        if formula_count >= 3:  # At least 3/5 should use formulas
            criteria_passed += 1
            feedback_parts.append(f"✅ Formulas used ({formula_count}/5 hives use formulas)")
            subscores['formulas_used'] = True
        else:
            feedback_parts.append(f"❌ Only {formula_count}/5 hives use formulas (may be hardcoded values)")
            subscores['formulas_used'] = False
        
        # Criterion 3: Scores in valid range (0-23)
        invalid_scores = []
        for hive in week4_hives:
            if hive['health_score'] is not None:
                try:
                    score = float(hive['health_score'])
                    if score < 0 or score > 23:
                        invalid_scores.append((hive['hive_id'], score))
                except (ValueError, TypeError):
                    invalid_scores.append((hive['hive_id'], hive['health_score']))
        
        if len(invalid_scores) == 0:
            criteria_passed += 1
            feedback_parts.append("✅ All scores in valid range (0-23)")
            subscores['valid_range'] = True
        else:
            feedback_parts.append(f"❌ Invalid scores found: {invalid_scores}")
            subscores['valid_range'] = False
        
        # Criterion 4: Domain logic correct (spot checks)
        logic_checks_passed = 0
        logic_checks_total = 0
        
        for hive in week4_hives:
            if hive['health_score'] is None:
                continue
            
            try:
                actual_score = float(hive['health_score'])
                expected_score = calculate_expected_score(
                    hive['population'],
                    hive['brood_frames'],
                    hive['honey_stores'],
                    hive['disease'],
                    hive['queen_seen']
                )
                
                # Allow ±2 points tolerance for different interpretation strategies
                if abs(actual_score - expected_score) <= 2:
                    logic_checks_passed += 1
                else:
                    logger.debug(f"Logic check failed for {hive['hive_id']}: expected ~{expected_score}, got {actual_score}")
                
                logic_checks_total += 1
            except (ValueError, TypeError) as e:
                logger.debug(f"Could not validate logic for {hive['hive_id']}: {e}")
        
        if logic_checks_total > 0 and logic_checks_passed / logic_checks_total >= 0.6:
            criteria_passed += 1
            feedback_parts.append(f"✅ Domain logic correct ({logic_checks_passed}/{logic_checks_total} spot checks passed)")
            subscores['logic_correct'] = True
        elif logic_checks_total > 0:
            feedback_parts.append(f"⚠️  Domain logic partially correct ({logic_checks_passed}/{logic_checks_total} checks)")
            subscores['logic_correct'] = False
        else:
            feedback_parts.append("⚠️  Could not validate domain logic")
            subscores['logic_correct'] = False
        
        # Criterion 5: Conditional formatting applied
        has_conditional_formatting = False
        try:
            # Check column I (Health Score) for conditional formatting
            has_conditional_formatting = check_conditional_formatting(workbook, sheet_name, 'I17:I21')
            
            if has_conditional_formatting:
                criteria_passed += 1
                feedback_parts.append("✅ Conditional formatting applied to Health Score column")
                subscores['conditional_formatting'] = True
            else:
                feedback_parts.append("❌ No conditional formatting detected on Health Score column")
                subscores['conditional_formatting'] = False
        except Exception as e:
            logger.debug(f"Could not check conditional formatting: {e}")
            feedback_parts.append("⚠️  Could not verify conditional formatting")
            subscores['conditional_formatting'] = False
        
        # Criterion 6: At least one at-risk hive (<12 score)
        at_risk_hives = []
        for hive in week4_hives:
            if hive['health_score'] is not None:
                try:
                    score = float(hive['health_score'])
                    if score < 12:
                        at_risk_hives.append((hive['hive_id'], score))
                except (ValueError, TypeError):
                    pass
        
        if len(at_risk_hives) > 0:
            criteria_passed += 1
            feedback_parts.append(f"✅ At-risk hives identified: {len(at_risk_hives)} hive(s) with score <12")
            subscores['at_risk_identified'] = True
        else:
            feedback_parts.append("❌ No at-risk hives identified (expected at least 1 with score <12)")
            subscores['at_risk_identified'] = False
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
        # Add summary feedback
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent! Colony health analysis completed successfully")
        elif passed:
            feedback_parts.insert(0, "✅ Task completed - health scores calculated and formatted")
        else:
            feedback_parts.insert(0, "❌ Task requirements not fully met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores
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
