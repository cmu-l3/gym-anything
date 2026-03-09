#!/usr/bin/env python3
"""
Verifier for Theater Conflict Detector task.

Validates that agent correctly identified scheduling conflicts by:
1. Parsing the Rehearsal_Schedule sheet to find conflict detection column
2. Comparing agent's flags against ground truth conflicts
3. Calculating precision, recall, and accuracy metrics
4. Checking for formula usage (not hardcoded values)
"""

import sys
import os
import logging
import re
from typing import Dict, Set, List, Tuple, Any, Optional

# Add utils to path (relative path for host machine execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_cell_formula,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def generate_ground_truth_conflicts(workbook: Dict[str, Any]) -> Set[str]:
    """
    Generate ground truth by independently calculating which rehearsals have conflicts.
    
    Args:
        workbook: Parsed spreadsheet data
    
    Returns:
        Set of rehearsal IDs that have conflicts
    """
    try:
        sheets = workbook.get('sheets', {})
        
        # Parse Rehearsal_Schedule
        rehearsal_sheet = sheets.get('Rehearsal_Schedule')
        if not rehearsal_sheet:
            logger.warning("Rehearsal_Schedule sheet not found")
            return set()
        
        # Parse Actor_Availability
        availability_sheet = sheets.get('Actor_Availability')
        if not availability_sheet:
            logger.warning("Actor_Availability sheet not found")
            return set()
        
        # Build unavailability map: {(actor, date): True}
        unavailable = {}
        for i, row in enumerate(availability_sheet):
            if i == 0:  # Skip header
                continue
            
            if len(row) < 2:
                continue
            
            actor_cell = row[0]
            date_cell = row[1]
            
            actor = actor_cell.get('value') if isinstance(actor_cell, dict) else actor_cell
            date = date_cell.get('value') if isinstance(date_cell, dict) else date_cell
            
            if actor and date:
                # Normalize actor name and date
                actor = str(actor).strip()
                date = str(date).strip()
                unavailable[(actor, date)] = True
        
        logger.info(f"Loaded {len(unavailable)} unavailability records")
        
        # Check each rehearsal for conflicts
        conflicts = set()
        for i, row in enumerate(rehearsal_sheet):
            if i == 0:  # Skip header
                continue
            
            if len(row) < 5:
                continue
            
            rehearsal_id_cell = row[0]
            date_cell = row[1]
            actor_cell = row[4]  # Assigned_Actor column
            
            rehearsal_id = rehearsal_id_cell.get('value') if isinstance(rehearsal_id_cell, dict) else rehearsal_id_cell
            date = date_cell.get('value') if isinstance(date_cell, dict) else date_cell
            actors = actor_cell.get('value') if isinstance(actor_cell, dict) else actor_cell
            
            if not rehearsal_id or not date or not actors:
                continue
            
            # Normalize
            rehearsal_id = str(rehearsal_id).strip()
            date = str(date).strip()
            actors_str = str(actors).strip()
            
            # Parse actors (handle comma-separated or single)
            actor_list = [a.strip() for a in actors_str.split(',')]
            
            # Check if any actor is unavailable on this date
            for actor in actor_list:
                if (actor, date) in unavailable:
                    conflicts.add(rehearsal_id)
                    logger.info(f"Conflict detected: {rehearsal_id} - {actor} unavailable on {date}")
                    break
        
        logger.info(f"Ground truth: {len(conflicts)} conflicts - {sorted(conflicts)}")
        return conflicts
    
    except Exception as e:
        logger.error(f"Error generating ground truth: {e}", exc_info=True)
        return set()


def find_conflict_column(rehearsal_sheet: List[List[Any]]) -> Optional[int]:
    """
    Find the column index where agent added conflict detection.
    
    Looks for column headers containing "conflict", "has_conflict", "issue", etc.
    
    Args:
        rehearsal_sheet: Sheet data rows
    
    Returns:
        Column index or None
    """
    if not rehearsal_sheet or len(rehearsal_sheet) == 0:
        return None
    
    header_row = rehearsal_sheet[0]
    
    # Look for conflict-related headers
    keywords = ['conflict', 'has_conflict', 'issue', 'problem', 'flag', 'status', 'check']
    
    for col_idx, cell in enumerate(header_row):
        value = cell.get('value') if isinstance(cell, dict) else cell
        if value:
            value_lower = str(value).lower().strip()
            for keyword in keywords:
                if keyword in value_lower:
                    logger.info(f"Found conflict column at index {col_idx}: '{value}'")
                    return col_idx
    
    # If no obvious header, check last non-empty column (agent may have added at end)
    last_col = len(header_row) - 1
    while last_col >= 5 and not header_row[last_col].get('value'):
        last_col -= 1
    
    if last_col >= 5:  # More columns than original (0-4 are original)
        logger.info(f"Using last column as conflict column: index {last_col}")
        return last_col
    
    return None


def normalize_flag_value(value: Any) -> bool:
    """
    Normalize various conflict flag formats to boolean.
    
    Accepts: CONFLICT, YES, TRUE, Y, 1, True, "conflict", etc.
    
    Args:
        value: Cell value
    
    Returns:
        True if indicates conflict, False otherwise
    """
    if value is None or value == '':
        return False
    
    if isinstance(value, bool):
        return value
    
    if isinstance(value, (int, float)):
        return value != 0
    
    value_str = str(value).strip().upper()
    
    # Positive indicators
    positive = ['CONFLICT', 'YES', 'TRUE', 'Y', '1', 'FAIL', 'ERROR', 'ISSUE', 'PROBLEM', 'X']
    
    return value_str in positive


def extract_agent_conflicts(workbook: Dict[str, Any]) -> Tuple[Set[str], bool]:
    """
    Extract which rehearsals the agent flagged as conflicts.
    
    Args:
        workbook: Parsed spreadsheet data
    
    Returns:
        Tuple of (set of flagged rehearsal IDs, whether formulas were used)
    """
    try:
        sheets = workbook.get('sheets', {})
        rehearsal_sheet = sheets.get('Rehearsal_Schedule')
        
        if not rehearsal_sheet:
            logger.error("Rehearsal_Schedule sheet not found")
            return set(), False
        
        # Find conflict column
        conflict_col_idx = find_conflict_column(rehearsal_sheet)
        
        if conflict_col_idx is None:
            logger.warning("Could not find conflict detection column")
            return set(), False
        
        agent_flagged = set()
        has_formulas = False
        
        # Check each data row
        for i, row in enumerate(rehearsal_sheet):
            if i == 0:  # Skip header
                continue
            
            if len(row) <= conflict_col_idx:
                continue
            
            # Get rehearsal ID
            id_cell = row[0]
            rehearsal_id = id_cell.get('value') if isinstance(id_cell, dict) else id_cell
            
            if not rehearsal_id:
                continue
            
            rehearsal_id = str(rehearsal_id).strip()
            
            # Get conflict flag
            flag_cell = row[conflict_col_idx]
            flag_value = flag_cell.get('value') if isinstance(flag_cell, dict) else flag_cell
            flag_formula = flag_cell.get('formula') if isinstance(flag_cell, dict) else None
            
            # Check if formula was used
            if flag_formula:
                has_formulas = True
                logger.debug(f"Row {i}: Formula detected: {flag_formula}")
            
            # Check if flagged as conflict
            if normalize_flag_value(flag_value):
                agent_flagged.add(rehearsal_id)
                logger.info(f"Agent flagged conflict: {rehearsal_id} (value: {flag_value})")
        
        logger.info(f"Agent flagged {len(agent_flagged)} conflicts: {sorted(agent_flagged)}")
        logger.info(f"Formulas used: {has_formulas}")
        
        return agent_flagged, has_formulas
    
    except Exception as e:
        logger.error(f"Error extracting agent conflicts: {e}", exc_info=True)
        return set(), False


def calculate_metrics(ground_truth: Set[str], agent_flagged: Set[str]) -> Dict[str, float]:
    """
    Calculate precision, recall, F1 score.
    
    Args:
        ground_truth: Set of true conflict IDs
        agent_flagged: Set of agent-flagged conflict IDs
    
    Returns:
        Dict with metrics
    """
    true_positives = len(ground_truth & agent_flagged)
    false_positives = len(agent_flagged - ground_truth)
    false_negatives = len(ground_truth - agent_flagged)
    true_negatives = 0  # Not easily calculable without knowing total rehearsals
    
    precision = true_positives / (true_positives + false_positives) if (true_positives + false_positives) > 0 else 0
    recall = true_positives / (true_positives + false_negatives) if (true_positives + false_negatives) > 0 else 0
    f1_score = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0
    
    return {
        'precision': precision,
        'recall': recall,
        'f1_score': f1_score,
        'true_positives': true_positives,
        'false_positives': false_positives,
        'false_negatives': false_negatives,
        'missed_conflicts': ground_truth - agent_flagged,
        'false_alarms': agent_flagged - ground_truth
    }


def verify_theater_conflicts(traj, env_info, task_info):
    """
    Main verification function for theater conflict detector task.
    
    Checks:
    1. Conflict column added to Rehearsal_Schedule
    2. Formulas used (not hardcoded)
    3. High recall (≥90% of conflicts detected)
    4. Good precision (≥85%, few false positives)
    5. Overall accuracy
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    container_path = "/home/ga/Documents/theater_schedule.ods"
    success, file_info, error = setup_calc_verification(
        copy_from_env,
        container_path,
        ['ods']
    )
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}
    
    try:
        workbook = file_info.get('sheet_data', {})
        
        # Generate ground truth
        ground_truth = generate_ground_truth_conflicts(workbook)
        
        if not ground_truth:
            logger.warning("No ground truth conflicts found - this may indicate a problem")
            # Use hardcoded ground truth as fallback
            ground_truth = {'R003', 'R005', 'R008', 'R009'}
            logger.info(f"Using fallback ground truth: {ground_truth}")
        
        # Extract agent's solution
        agent_flagged, has_formulas = extract_agent_conflicts(workbook)
        
        # Calculate metrics
        metrics = calculate_metrics(ground_truth, agent_flagged)
        
        # Build feedback
        feedback_parts = []
        criteria_passed = 0
        total_criteria = 5
        
        # Criterion 1: Conflict column present
        if agent_flagged or has_formulas:
            criteria_passed += 1
            feedback_parts.append("✅ Conflict detection column added")
        else:
            feedback_parts.append("❌ No conflict detection column found")
        
        # Criterion 2: Formulas used
        if has_formulas:
            criteria_passed += 1
            feedback_parts.append("✅ Formulas used (not hardcoded)")
        else:
            feedback_parts.append("❌ No formulas detected (values may be hardcoded)")
        
        # Criterion 3: High recall (≥90%)
        recall = metrics['recall']
        if recall >= 0.90:
            criteria_passed += 1
            feedback_parts.append(f"✅ Excellent recall: {recall*100:.0f}% (detected {metrics['true_positives']}/{len(ground_truth)} conflicts)")
        elif recall >= 0.75:
            criteria_passed += 0.7
            feedback_parts.append(f"⚠️ Good recall: {recall*100:.0f}% (detected {metrics['true_positives']}/{len(ground_truth)} conflicts)")
        else:
            feedback_parts.append(f"❌ Low recall: {recall*100:.0f}% (missed {metrics['false_negatives']} conflicts)")
            if metrics['missed_conflicts']:
                feedback_parts.append(f"   Missed: {', '.join(sorted(metrics['missed_conflicts']))}")
        
        # Criterion 4: Good precision (≥85%)
        precision = metrics['precision']
        if precision >= 0.85:
            criteria_passed += 1
            feedback_parts.append(f"✅ High precision: {precision*100:.0f}% (few false alarms)")
        elif precision >= 0.70:
            criteria_passed += 0.7
            feedback_parts.append(f"⚠️ Acceptable precision: {precision*100:.0f}%")
        else:
            feedback_parts.append(f"❌ Low precision: {precision*100:.0f}% ({metrics['false_positives']} false alarms)")
            if metrics['false_alarms']:
                feedback_parts.append(f"   False alarms: {', '.join(sorted(metrics['false_alarms']))}")
        
        # Criterion 5: Overall quality (F1 score)
        f1 = metrics['f1_score']
        if f1 >= 0.85:
            criteria_passed += 1
            feedback_parts.append(f"✅ Excellent overall accuracy (F1: {f1:.2f})")
        elif f1 >= 0.70:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Good overall accuracy (F1: {f1:.2f})")
        else:
            feedback_parts.append(f"❌ Needs improvement (F1: {f1:.2f})")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70
        
        if passed and score >= 90:
            feedback_parts.append("🎭 Perfect conflict detection! The director can now reschedule with confidence.")
        elif passed:
            feedback_parts.append("✅ Task completed successfully")
        else:
            feedback_parts.append("❌ Task requirements not met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "column_added": agent_flagged or has_formulas,
                "formulas_used": has_formulas,
                "recall": recall,
                "precision": precision,
                "f1_score": f1,
                "true_positives": metrics['true_positives'],
                "false_positives": metrics['false_positives'],
                "false_negatives": metrics['false_negatives']
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
        cleanup_verification_temp(file_info.get('temp_dir'))
