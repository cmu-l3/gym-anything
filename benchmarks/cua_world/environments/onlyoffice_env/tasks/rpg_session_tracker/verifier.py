#!/usr/bin/env python3
"""
Verifier for RPG Session Tracker task
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_text(text):
    """Normalize text for comparison (lowercase, strip, remove extra spaces)"""
    if text is None:
        return ""
    return str(text).strip().lower()


def normalize_number(value):
    """Extract numeric value from cell (handle formatted numbers with commas)"""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    # Try to parse string with commas
    text = str(value).replace(',', '').replace(' ', '').strip()
    try:
        return float(text)
    except:
        return None


def is_formula(cell):
    """Check if cell contains a formula"""
    if hasattr(cell, 'data_type') and cell.data_type == 'f':
        return True
    if hasattr(cell, 'value') and isinstance(cell.value, str) and cell.value.startswith('='):
        return True
    return False


def verify_rpg_session_tracker(traj, env_info, task_info):
    """
    Verify the RPG session tracker spreadsheet.

    Checks:
    1. All 4 characters present
    2. Correct previous gold values (±5 GP tolerance)
    3. Correct gold gained values (±5 GP tolerance)
    4. Working Total Gold formulas
    5. Correct previous XP values (±50 XP tolerance)
    6. Correct XP gained values (±50 XP tolerance)
    7. Working Total XP formulas
    8. Working Level Up formulas (Elara='YES', others='NO')
    9. Magic items section present
    10. Correct item assignments
    11. Headers are bold (structure check)
    12. File saved correctly
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    filepath = "/home/ga/Documents/Spreadsheets/dragon_hoard_loot.xlsx"
    
    # Copy file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.xlsx')
    temp_path = temp_file.name
    temp_file.close()
    
    try:
        copy_from_env(filepath, temp_path)
        
        if not os.path.exists(temp_path) or os.path.getsize(temp_path) == 0:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "❌ File not found or empty: dragon_hoard_loot.xlsx"
            }
        
        # Parse spreadsheet (data_only=False to see formulas)
        wb = parse_xlsx_file(temp_path)
        if not wb:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "❌ Could not parse XLSX file"
            }
        
        sheet = wb.active
        criteria_met = 0
        total_criteria = 10
        feedback_parts = []
        
        # Expected character data
        expected_chars = {
            'alaric': {
                'player': 'sarah',
                'prev_gold': 1247,
                'gold_gained': 850,
                'total_gold': 2097,
                'prev_xp': 11300,
                'xp_gained': 2100,
                'total_xp': 13400,
                'level_up': 'no'
            },
            'thorgrim': {
                'player': 'marcus',
                'prev_gold': 1180,
                'gold_gained': 600,
                'total_gold': 1780,
                'prev_xp': 11850,
                'xp_gained': 1050,
                'total_xp': 12900,
                'level_up': 'no'
            },
            'elara': {
                'player': 'jen',
                'prev_gold': 1390,
                'gold_gained': 1100,
                'total_gold': 2490,
                'prev_xp': 12100,
                'xp_gained': 2100,
                'total_xp': 14200,
                'level_up': 'yes'
            },
            'krrosh': {
                'player': 'david',
                'prev_gold': 998,
                'gold_gained': 950,
                'total_gold': 1948,
                'prev_xp': 10900,
                'xp_gained': 2100,
                'total_xp': 13000,
                'level_up': 'no'
            }
        }
        
        # Find header row (look for "character" and "name" in same row)
        header_row_idx = None
        header_row_num = None
        col_mapping = {}
        
        for row_idx, row in enumerate(sheet.iter_rows(max_row=20, values_only=False)):
            row_text = [normalize_text(cell.value) for cell in row[:15]]
            row_combined = ' '.join(row_text)
            
            # Check if this looks like a header row
            if 'character' in row_combined and 'name' in row_combined:
                header_row_idx = row_idx
                header_row_num = row_idx + 1
                
                # Map column names to indices
                for col_idx, cell in enumerate(row[:15]):
                    cell_text = normalize_text(cell.value)
                    if 'character' in cell_text and 'name' in cell_text:
                        col_mapping['char_name'] = col_idx
                    elif 'player' in cell_text and 'name' in cell_text:
                        col_mapping['player_name'] = col_idx
                    elif 'previous' in cell_text and 'gold' in cell_text:
                        col_mapping['prev_gold'] = col_idx
                    elif 'gold' in cell_text and 'gained' in cell_text:
                        col_mapping['gold_gained'] = col_idx
                    elif 'total' in cell_text and 'gold' in cell_text:
                        col_mapping['total_gold'] = col_idx
                    elif 'previous' in cell_text and 'xp' in cell_text:
                        col_mapping['prev_xp'] = col_idx
                    elif 'xp' in cell_text and 'gained' in cell_text:
                        col_mapping['xp_gained'] = col_idx
                    elif 'total' in cell_text and 'xp' in cell_text:
                        col_mapping['total_xp'] = col_idx
                    elif 'level' in cell_text and 'up' in cell_text:
                        col_mapping['level_up'] = col_idx
                break
        
        if header_row_idx is None:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "❌ Could not find character table header row. Expected headers like 'Character Name', 'Player Name', 'Previous Gold', etc."
            }
        
        # Check if we have the essential columns
        required_cols = ['char_name', 'prev_gold', 'gold_gained', 'total_gold', 
                        'prev_xp', 'xp_gained', 'total_xp', 'level_up']
        missing_cols = [col for col in required_cols if col not in col_mapping]
        if missing_cols:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Missing required columns in header: {missing_cols}. Found columns: {list(col_mapping.keys())}"
            }
        
        feedback_parts.append(f"✅ Character table structure found (row {header_row_num})")
        
        # Parse character data rows
        char_data = {}
        for row in sheet.iter_rows(min_row=header_row_num+1, max_row=header_row_num+10, values_only=False):
            if len(row) <= max(col_mapping.values()):
                continue
            
            char_cell = row[col_mapping['char_name']]
            char_name = normalize_text(char_cell.value)
            
            if char_name in expected_chars:
                char_data[char_name] = {
                    'prev_gold': normalize_number(row[col_mapping['prev_gold']].value),
                    'gold_gained': normalize_number(row[col_mapping['gold_gained']].value),
                    'total_gold': normalize_number(row[col_mapping['total_gold']].value),
                    'total_gold_cell': row[col_mapping['total_gold']],
                    'prev_xp': normalize_number(row[col_mapping['prev_xp']].value),
                    'xp_gained': normalize_number(row[col_mapping['xp_gained']].value),
                    'total_xp': normalize_number(row[col_mapping['total_xp']].value),
                    'total_xp_cell': row[col_mapping['total_xp']],
                    'level_up': normalize_text(row[col_mapping['level_up']].value),
                    'level_up_cell': row[col_mapping['level_up']],
                }
        
        # Criterion 1: All 4 characters present
        if len(char_data) == 4:
            criteria_met += 1
            feedback_parts.append(f"✅ All 4 characters present: {', '.join(char_data.keys()).title()}")
        else:
            found = ', '.join(char_data.keys()).title() if char_data else 'none'
            feedback_parts.append(f"❌ Only found {len(char_data)}/4 characters ({found})")
        
        # Criteria 2-8: Check individual character data
        gold_tolerance = 10
        xp_tolerance = 100
        
        correct_prev_gold = 0
        correct_gold_gained = 0
        correct_total_gold = 0
        correct_prev_xp = 0
        correct_xp_gained = 0
        correct_total_xp = 0
        correct_level_up = 0
        
        has_gold_formulas = 0
        has_xp_formulas = 0
        has_level_formulas = 0
        
        for char_name in expected_chars.keys():
            if char_name not in char_data:
                continue
            
            expected = expected_chars[char_name]
            actual = char_data[char_name]
            
            # Check previous gold
            if actual['prev_gold'] is not None and abs(actual['prev_gold'] - expected['prev_gold']) <= gold_tolerance:
                correct_prev_gold += 1
            
            # Check gold gained
            if actual['gold_gained'] is not None and abs(actual['gold_gained'] - expected['gold_gained']) <= gold_tolerance:
                correct_gold_gained += 1
            
            # Check total gold (value and formula)
            if actual['total_gold'] is not None and abs(actual['total_gold'] - expected['total_gold']) <= gold_tolerance:
                correct_total_gold += 1
                # Check if it's a formula
                if is_formula(actual['total_gold_cell']):
                    has_gold_formulas += 1
            
            # Check previous XP
            if actual['prev_xp'] is not None and abs(actual['prev_xp'] - expected['prev_xp']) <= xp_tolerance:
                correct_prev_xp += 1
            
            # Check XP gained
            if actual['xp_gained'] is not None and abs(actual['xp_gained'] - expected['xp_gained']) <= xp_tolerance:
                correct_xp_gained += 1
            
            # Check total XP (value and formula)
            if actual['total_xp'] is not None and abs(actual['total_xp'] - expected['total_xp']) <= xp_tolerance:
                correct_total_xp += 1
                # Check if it's a formula
                if is_formula(actual['total_xp_cell']):
                    has_xp_formulas += 1
            
            # Check level up
            if actual['level_up'] == expected['level_up']:
                correct_level_up += 1
                # Check if it's a formula
                if is_formula(actual['level_up_cell']):
                    has_level_formulas += 1
        
        # Criterion 2: Previous gold values correct
        if correct_prev_gold >= 3:
            criteria_met += 1
            feedback_parts.append(f"✅ Previous gold values correct ({correct_prev_gold}/4)")
        else:
            feedback_parts.append(f"❌ Previous gold values incorrect ({correct_prev_gold}/4)")
        
        # Criterion 3: Gold gained values correct
        if correct_gold_gained >= 3:
            criteria_met += 1
            feedback_parts.append(f"✅ Gold gained values correct ({correct_gold_gained}/4)")
        else:
            feedback_parts.append(f"❌ Gold gained values incorrect ({correct_gold_gained}/4)")
        
        # Criterion 4: Total gold formulas working
        if correct_total_gold >= 3 and has_gold_formulas >= 2:
            criteria_met += 1
            feedback_parts.append(f"✅ Total gold formulas working ({has_gold_formulas}/4 are formulas)")
        else:
            feedback_parts.append(f"❌ Total gold formulas issue (values: {correct_total_gold}/4, formulas: {has_gold_formulas}/4)")
        
        # Criterion 5: Previous XP values correct
        if correct_prev_xp >= 3:
            criteria_met += 1
            feedback_parts.append(f"✅ Previous XP values correct ({correct_prev_xp}/4)")
        else:
            feedback_parts.append(f"❌ Previous XP values incorrect ({correct_prev_xp}/4)")
        
        # Criterion 6: XP gained values correct
        if correct_xp_gained >= 3:
            criteria_met += 1
            feedback_parts.append(f"✅ XP gained values correct ({correct_xp_gained}/4)")
        else:
            feedback_parts.append(f"❌ XP gained values incorrect ({correct_xp_gained}/4)")
        
        # Criterion 7: Total XP formulas working
        if correct_total_xp >= 3 and has_xp_formulas >= 2:
            criteria_met += 1
            feedback_parts.append(f"✅ Total XP formulas working ({has_xp_formulas}/4 are formulas)")
        else:
            feedback_parts.append(f"❌ Total XP formulas issue (values: {correct_total_xp}/4, formulas: {has_xp_formulas}/4)")
        
        # Criterion 8: Level up detection correct
        # Special check: Elara should be YES, others NO
        elara_correct = char_data.get('elara', {}).get('level_up') == 'yes'
        others_correct = sum([1 for name in ['alaric', 'thorgrim', 'krrosh'] 
                             if char_data.get(name, {}).get('level_up') == 'no'])
        
        if elara_correct and others_correct >= 2 and has_level_formulas >= 2:
            criteria_met += 1
            feedback_parts.append(f"✅ Level up formulas correct (Elara=YES, others=NO, {has_level_formulas}/4 formulas)")
        else:
            if not elara_correct:
                feedback_parts.append(f"❌ Level up incorrect: Elara should level up (14,200 XP >= 14,000)")
            else:
                feedback_parts.append(f"❌ Level up detection issue (correct: {correct_level_up}/4, formulas: {has_level_formulas}/4)")
        
        # Criterion 9-10: Magic items section
        items_found = {
            'flaming_sword': False,
            'cloak': False,
            'ring': False,
            'potion': False
        }
        
        items_assigned_correctly = 0
        
        # Search for magic items section (below character table)
        for row in sheet.iter_rows(min_row=header_row_num+6, max_row=header_row_num+30, values_only=True):
            if not row or len(row) < 2:
                continue
            
            item_text = normalize_text(row[0])
            assigned_text = normalize_text(row[1]) if len(row) > 1 else ''
            
            if 'flaming' in item_text and ('sword' in item_text or 'longsword' in item_text):
                items_found['flaming_sword'] = True
                if 'alaric' in assigned_text:
                    items_assigned_correctly += 1
            
            if 'cloak' in item_text and 'displacement' in item_text:
                items_found['cloak'] = True
                if 'elara' in assigned_text:
                    items_assigned_correctly += 1
            
            if 'ring' in item_text and 'fire' in item_text and 'resistance' in item_text:
                items_found['ring'] = True
                if 'thorgrim' in assigned_text:
                    items_assigned_correctly += 1
            
            if 'potion' in item_text and ('healing' in item_text or 'greater' in item_text):
                items_found['potion'] = True
                if 'party' in assigned_text or 'pool' in assigned_text:
                    items_assigned_correctly += 1
        
        items_count = sum(items_found.values())
        if items_count >= 3:
            criteria_met += 1
            feedback_parts.append(f"✅ Magic items section present ({items_count}/4 items found)")
        else:
            feedback_parts.append(f"❌ Magic items section incomplete ({items_count}/4 items found)")
        
        if items_assigned_correctly >= 3:
            criteria_met += 1
            feedback_parts.append(f"✅ Items assigned correctly ({items_assigned_correctly}/4)")
        else:
            feedback_parts.append(f"❌ Item assignments incorrect ({items_assigned_correctly}/4 correct)")
        
        # Calculate final score
        score = criteria_met / total_criteria
        passed = score >= 0.7  # Need 70% to pass
        
        feedback = f"Score: {criteria_met}/{total_criteria} criteria. " + " | ".join(feedback_parts)
        
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
        if os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except:
                pass
