#!/usr/bin/env python3
"""
Verifier for Secret Santa Fixer task.
Checks constraint satisfaction, cycle validity, and data quality.
"""

import sys
import os
import logging
from typing import Dict, List, Tuple, Set, Any, Optional

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_participants_data(workbook: Dict, sheet_name: str) -> List[Dict[str, Any]]:
    """
    Parse participant data from spreadsheet.
    
    Returns:
        List of dicts with keys: name, spouse, gives_to, budget
    """
    participants = []
    sheet_rows = workbook['sheets'][sheet_name]
    
    # Skip header row (row 0)
    for row_idx, row in enumerate(sheet_rows[1:], start=2):
        if len(row) < 3:
            continue
        
        name_cell = row[0] if len(row) > 0 else {}
        spouse_cell = row[1] if len(row) > 1 else {}
        gives_to_cell = row[2] if len(row) > 2 else {}
        budget_cell = row[3] if len(row) > 3 else {}
        
        name = name_cell.get('value') if isinstance(name_cell, dict) else name_cell
        spouse = spouse_cell.get('value') if isinstance(spouse_cell, dict) else spouse_cell
        gives_to = gives_to_cell.get('value') if isinstance(gives_to_cell, dict) else gives_to_cell
        budget = budget_cell.get('value') if isinstance(budget_cell, dict) else budget_cell
        
        # Skip empty rows
        if not name or str(name).strip() == '':
            continue
        
        participants.append({
            'row': row_idx,
            'name': str(name).strip(),
            'spouse': str(spouse).strip() if spouse else '',
            'gives_to': str(gives_to).strip() if gives_to else '',
            'budget': budget
        })
    
    return participants


def check_self_assignments(participants: List[Dict]) -> Tuple[bool, List[str]]:
    """Check for self-assignments (person gives to themselves)."""
    violations = []
    
    for p in participants:
        name_lower = p['name'].lower()
        gives_to_lower = p['gives_to'].lower() if p['gives_to'] else ''
        
        if gives_to_lower and name_lower == gives_to_lower:
            violations.append(f"{p['name']} → {p['gives_to']} (self-assignment)")
    
    return len(violations) == 0, violations


def check_spouse_violations(participants: List[Dict]) -> Tuple[bool, List[str]]:
    """Check for spouse pairing violations (married couples assigned to each other)."""
    violations = []
    
    # Build spouse map
    spouse_map = {}
    for p in participants:
        if p['spouse']:
            spouse_map[p['name'].lower()] = p['spouse'].lower()
    
    # Check for violations
    for p in participants:
        if not p['gives_to']:
            continue
        
        name_lower = p['name'].lower()
        gives_to_lower = p['gives_to'].lower()
        
        # Check if giving to their spouse
        if name_lower in spouse_map and spouse_map[name_lower] == gives_to_lower:
            violations.append(f"{p['name']} → {p['gives_to']} (spouse pairing)")
    
    return len(violations) == 0, violations


def check_completeness(participants: List[Dict]) -> Tuple[bool, List[str]]:
    """Check that all participants have assignments."""
    missing = []
    
    for p in participants:
        if not p['gives_to'] or p['gives_to'] == '':
            missing.append(f"{p['name']} has no assignment")
    
    return len(missing) == 0, missing


def validate_gift_cycle(participants: List[Dict]) -> Tuple[bool, str]:
    """
    Validate that assignments form a single complete cycle.
    Everyone should give to exactly one person and receive from exactly one person.
    """
    if not participants:
        return False, "No participants found"
    
    # Build assignment graph
    assignments = {}
    all_names = set()
    
    for p in participants:
        name = p['name']
        gives_to = p['gives_to']
        
        all_names.add(name)
        
        if gives_to and gives_to.strip():
            # Normalize names for matching
            assignments[name.lower().strip()] = gives_to.lower().strip()
    
    # Check if everyone has an assignment
    if len(assignments) != len(participants):
        return False, f"Missing assignments: {len(participants)} people but only {len(assignments)} assignments"
    
    # Check that everyone who gives also receives
    givers = set(assignments.keys())
    receivers = set(assignments.values())
    
    # Check if all givers have corresponding names in participants
    participant_names_lower = set(p['name'].lower().strip() for p in participants)
    
    # Check for people who give but aren't in participant list (shouldn't happen)
    unknown_givers = givers - participant_names_lower
    if unknown_givers:
        return False, f"Unknown givers: {unknown_givers}"
    
    # Check for people who receive but aren't in participant list
    unknown_receivers = receivers - participant_names_lower
    if unknown_receivers:
        return False, f"Assigned to non-existent people: {unknown_receivers}"
    
    # Check if everyone appears exactly once as receiver
    if len(receivers) != len(givers):
        return False, f"Imbalanced: {len(givers)} givers but {len(receivers)} receivers"
    
    if givers != receivers:
        missing_receivers = givers - receivers
        extra_receivers = receivers - givers
        msg = ""
        if missing_receivers:
            msg += f"Not receiving gifts: {missing_receivers}. "
        if extra_receivers:
            msg += f"Receiving but not giving: {extra_receivers}."
        return False, msg.strip()
    
    # Check for a valid cycle by following the chain
    if not assignments:
        return False, "No assignments found"
    
    start = next(iter(assignments.keys()))
    visited = set()
    current = start
    
    # Follow the chain
    for _ in range(len(assignments) + 1):
        if current in visited:
            # We've hit a cycle
            if current == start and len(visited) == len(assignments):
                # Perfect! We returned to start after visiting everyone
                return True, "Valid single cycle covering all participants"
            else:
                # We hit a cycle but didn't visit everyone
                unvisited = givers - visited
                return False, f"Incomplete cycle: visited {len(visited)}/{len(assignments)} people. Unvisited: {unvisited}"
        
        visited.add(current)
        next_person = assignments.get(current)
        
        if next_person is None:
            return False, f"Broken chain at {current} (no assignment)"
        
        current = next_person
    
    # If we get here, the chain is too long (shouldn't happen)
    return False, "Cycle detection failed: chain too long"


def check_budget_standardization(participants: List[Dict]) -> Tuple[bool, List[str], float]:
    """
    Check that budgets are standardized to numeric values in reasonable range.
    
    Returns:
        (is_standardized, issues, std_dev)
    """
    issues = []
    numeric_budgets = []
    
    for p in participants:
        budget = p['budget']
        
        if budget is None or budget == '':
            issues.append(f"{p['name']}: missing budget")
            continue
        
        # Try to extract numeric value
        numeric_value = None
        
        if isinstance(budget, (int, float)):
            numeric_value = float(budget)
        else:
            budget_str = str(budget).strip()
            # Remove common currency symbols and text
            budget_str = budget_str.replace('$', '').replace('dollars', '').strip()
            
            try:
                numeric_value = float(budget_str)
            except ValueError:
                issues.append(f"{p['name']}: non-numeric budget '{budget}'")
                continue
        
        # Check range
        if numeric_value < 15 or numeric_value > 50:
            issues.append(f"{p['name']}: budget ${numeric_value:.0f} outside range $15-50")
        
        numeric_budgets.append(numeric_value)
    
    # Calculate standard deviation
    if len(numeric_budgets) > 1:
        mean = sum(numeric_budgets) / len(numeric_budgets)
        variance = sum((x - mean) ** 2 for x in numeric_budgets) / len(numeric_budgets)
        std_dev = variance ** 0.5
    else:
        std_dev = 0
    
    # Consider standardized if all are numeric and in range
    is_standardized = len(issues) == 0 and len(numeric_budgets) == len(participants)
    
    return is_standardized, issues, std_dev


def verify_secret_santa_fixer(traj, env_info, task_info):
    """
    Verify Secret Santa Fixer task completion.
    
    Checks:
    1. No self-assignments
    2. No spouse pairings
    3. Complete assignments
    4. Valid cycle
    5. Budget standardized
    6. Balanced coverage
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    temp_dir = None
    success = False
    workbook = None
    
    file_attempts = [
        ('ods', '/home/ga/Documents/secret_santa_fixed.ods'),
        ('ods', '/home/ga/Documents/secret_santa.ods'),
        ('csv', '/home/ga/Documents/secret_santa.csv'),
    ]
    
    for file_format, container_path in file_attempts:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format=file_format
        )
        
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load Secret Santa file: {error}"
        }
    
    try:
        # Get first sheet
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        # Parse participant data
        participants = parse_participants_data(workbook, sheet_name)
        
        if len(participants) < 10:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Insufficient participants: found {len(participants)}, expected at least 10"
            }
        
        logger.info(f"Found {len(participants)} participants")
        
        # Initialize scoring
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: No self-assignments
        no_self, self_violations = check_self_assignments(participants)
        if no_self:
            criteria_passed += 1
            feedback_parts.append("✅ No self-assignments")
            subscores['no_self_assignments'] = True
        else:
            feedback_parts.append(f"❌ Self-assignment violations: {', '.join(self_violations)}")
            subscores['no_self_assignments'] = False
        
        # Criterion 2: No spouse pairings
        no_spouse, spouse_violations = check_spouse_violations(participants)
        if no_spouse:
            criteria_passed += 1
            feedback_parts.append("✅ No spouse pairings")
            subscores['no_spouse_pairings'] = True
        else:
            feedback_parts.append(f"❌ Spouse pairing violations: {', '.join(spouse_violations)}")
            subscores['no_spouse_pairings'] = False
        
        # Criterion 3: Complete assignments
        is_complete, missing = check_completeness(participants)
        if is_complete:
            criteria_passed += 1
            feedback_parts.append("✅ All assignments complete")
            subscores['assignments_complete'] = True
        else:
            feedback_parts.append(f"❌ Missing assignments: {', '.join(missing)}")
            subscores['assignments_complete'] = False
        
        # Criterion 4: Valid cycle
        valid_cycle, cycle_msg = validate_gift_cycle(participants)
        if valid_cycle:
            criteria_passed += 1
            feedback_parts.append(f"✅ Valid gift cycle: {cycle_msg}")
            subscores['valid_cycle'] = True
        else:
            feedback_parts.append(f"❌ Cycle invalid: {cycle_msg}")
            subscores['valid_cycle'] = False
        
        # Criterion 5: Budget standardization
        budgets_ok, budget_issues, std_dev = check_budget_standardization(participants)
        if budgets_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ Budgets standardized (std dev: ${std_dev:.1f})")
            subscores['budgets_standardized'] = True
        else:
            if len(budget_issues) <= 3:
                feedback_parts.append(f"❌ Budget issues: {', '.join(budget_issues)}")
            else:
                feedback_parts.append(f"❌ Budget issues: {len(budget_issues)} problems found")
            subscores['budgets_standardized'] = False
        
        # Criterion 6: Balanced coverage (implied by valid cycle, but check explicitly)
        # This is mostly redundant with valid_cycle, but we check it for clarity
        if valid_cycle and is_complete:
            criteria_passed += 1
            feedback_parts.append("✅ Balanced coverage (everyone gives to 1, receives from 1)")
            subscores['balanced_coverage'] = True
        else:
            feedback_parts.append("❌ Coverage imbalanced")
            subscores['balanced_coverage'] = False
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 80  # Need 5/6 criteria (80%)
        
        # Add summary
        if passed and score >= 95:
            feedback_parts.insert(0, "🎉 Perfect Secret Santa fix!")
        elif passed:
            feedback_parts.insert(0, "✅ Secret Santa fixed successfully")
        else:
            feedback_parts.insert(0, f"❌ Insufficient fixes ({criteria_passed}/{total_criteria} criteria met)")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "metrics": {
                "criteria_passed": criteria_passed,
                "total_criteria": total_criteria,
                "participant_count": len(participants),
                "self_violations": len(self_violations) if not no_self else 0,
                "spouse_violations": len(spouse_violations) if not no_spouse else 0,
                "missing_assignments": len(missing) if not is_complete else 0,
                "budget_std_dev": round(std_dev, 2) if budgets_ok else None
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
        cleanup_verification_temp(temp_dir)
