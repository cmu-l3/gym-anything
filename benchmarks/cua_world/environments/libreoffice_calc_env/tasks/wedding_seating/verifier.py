#!/usr/bin/env python3
"""
Verifier for Wedding Seating Arrangement task.
Checks constraint satisfaction, formula usage, and summary table creation.
"""

import sys
import os
import logging
from typing import Dict, List, Any, Tuple, Optional

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_guest_data(rows: List[List[Dict]], start_row: int = 2, end_row: int = 66) -> List[Dict]:
    """
    Extract guest data from spreadsheet rows.
    
    Args:
        rows: Sheet rows from parsed ODS/CSV
        start_row: Starting row index (0-based, row 3 = index 2)
        end_row: Ending row index (0-based, row 66 = index 65)
        
    Returns:
        List of guest dicts with name, family, meal, table
    """
    guests = []
    
    for i in range(start_row, min(end_row, len(rows))):
        if i >= len(rows):
            break
            
        row = rows[i]
        if len(row) < 4:
            continue
        
        # Extract cell values (handle both dict and direct value formats)
        def get_val(cell):
            if isinstance(cell, dict):
                return cell.get('value', '')
            return cell
        
        name = get_val(row[0]) if len(row) > 0 else ''
        family = get_val(row[1]) if len(row) > 1 else ''
        meal = get_val(row[2]) if len(row) > 2 else ''
        table = get_val(row[3]) if len(row) > 3 else ''
        
        # Only include rows with guest names
        if name and str(name).strip():
            guests.append({
                'row': i + 1,  # 1-based row number for reporting
                'name': str(name).strip(),
                'family': str(family).strip() if family else '',
                'meal': str(meal).strip() if meal else '',
                'table': table
            })
    
    return guests


def check_all_assigned(guests: List[Dict]) -> Tuple[bool, int, str]:
    """Check if all guests have table assignments."""
    empty_count = 0
    empty_names = []
    
    for guest in guests:
        table = guest['table']
        # Check if table is empty, None, or blank string
        if table is None or table == '' or str(table).strip() == '':
            empty_count += 1
            if len(empty_names) < 5:  # Limit examples
                empty_names.append(guest['name'])
    
    success = empty_count == 0
    message = f"✅ All {len(guests)} guests assigned" if success else f"❌ {empty_count} guests unassigned (e.g., {', '.join(empty_names)})"
    
    return success, empty_count, message


def check_capacity_constraints(guests: List[Dict]) -> Tuple[bool, Dict[Any, int], str]:
    """Check that no table exceeds 8 guests."""
    table_counts = {}
    
    for guest in guests:
        table = guest['table']
        if table is not None and table != '' and str(table).strip() != '':
            # Normalize table number (handle both int and string)
            try:
                table_num = int(float(str(table)))
            except (ValueError, TypeError):
                table_num = str(table)
            
            table_counts[table_num] = table_counts.get(table_num, 0) + 1
    
    violations = []
    for table, count in sorted(table_counts.items()):
        if count > 8:
            violations.append(f"Table {table}: {count} guests")
    
    success = len(violations) == 0
    message = "✅ All tables ≤8 guests" if success else f"❌ Capacity violations: {', '.join(violations)}"
    
    return success, table_counts, message


def check_wedding_party_constraint(guests: List[Dict]) -> Tuple[bool, str]:
    """Check that Wedding Party (8 people) are all at Table 1, exclusively."""
    wedding_party = [g for g in guests if 'wedding party' in g['family'].lower()]
    
    if len(wedding_party) != 8:
        return False, f"❌ Expected 8 Wedding Party members, found {len(wedding_party)}"
    
    # Check all at Table 1
    at_table_1 = []
    not_at_table_1 = []
    
    for guest in wedding_party:
        try:
            table_num = int(float(str(guest['table'])))
        except (ValueError, TypeError):
            table_num = None
        
        if table_num == 1:
            at_table_1.append(guest['name'])
        else:
            not_at_table_1.append((guest['name'], guest['table']))
    
    if len(at_table_1) != 8:
        return False, f"❌ Only {len(at_table_1)}/8 Wedding Party at Table 1"
    
    # Check that ONLY Wedding Party at Table 1
    table_1_guests = [g for g in guests if _normalize_table(g['table']) == 1]
    
    if len(table_1_guests) != 8:
        return False, f"❌ Table 1 has {len(table_1_guests)} guests (should be exactly 8)"
    
    non_wedding_at_1 = [g['name'] for g in table_1_guests if 'wedding party' not in g['family'].lower()]
    if non_wedding_at_1:
        return False, f"❌ Non-Wedding Party guests at Table 1: {', '.join(non_wedding_at_1[:3])}"
    
    return True, "✅ Wedding Party (8 members) correctly at Table 1"


def _normalize_table(table_val) -> Optional[int]:
    """Normalize table value to integer."""
    if table_val is None or table_val == '' or str(table_val).strip() == '':
        return None
    try:
        return int(float(str(table_val)))
    except (ValueError, TypeError):
        return None


def check_family_cohesion(guests: List[Dict]) -> Tuple[bool, float, str]:
    """Check that families are seated together (80%+ threshold)."""
    # Group guests by family
    family_groups = {}
    
    for guest in guests:
        family = guest['family']
        # Only consider actual family groups (contains "Family" or has multiple members)
        if family and family.lower() not in ['friends', 'colleagues', '']:
            family_groups.setdefault(family, []).append(guest)
    
    # Filter to families with 2+ members
    family_groups = {k: v for k, v in family_groups.items() if len(v) >= 2}
    
    if not family_groups:
        return True, 1.0, "✅ No multi-member families to check"
    
    families_together = 0
    families_split = []
    
    for family_name, members in family_groups.items():
        # Get all table assignments for this family
        tables = [_normalize_table(m['table']) for m in members]
        tables = [t for t in tables if t is not None]  # Remove None values
        
        if not tables:
            continue
        
        # Check if all at same table
        unique_tables = set(tables)
        if len(unique_tables) == 1:
            families_together += 1
        else:
            families_split.append(f"{family_name} ({len(members)} people across tables {unique_tables})")
    
    total_families = len(family_groups)
    cohesion_rate = families_together / total_families if total_families > 0 else 1.0
    success = cohesion_rate >= 0.8
    
    if success:
        message = f"✅ Family cohesion: {families_together}/{total_families} families together ({cohesion_rate*100:.0f}%)"
    else:
        split_examples = ', '.join(families_split[:2])
        message = f"❌ Family cohesion: {families_together}/{total_families} together ({cohesion_rate*100:.0f}%). Split: {split_examples}"
    
    return success, cohesion_rate, message


def check_summary_table(rows: List[List[Dict]]) -> Tuple[bool, str]:
    """Check if summary table exists with proper headers in F2:G2."""
    if len(rows) < 2:
        return False, "❌ Insufficient rows for summary table"
    
    # Check row 2 (index 1) for headers in columns F and G (indices 5 and 6)
    header_row = rows[1] if len(rows) > 1 else []
    
    if len(header_row) < 7:
        return False, "❌ Summary table headers not found (columns F-G empty)"
    
    def get_val(cell):
        if isinstance(cell, dict):
            return cell.get('value', '')
        return cell
    
    f2_val = str(get_val(header_row[5])).lower() if len(header_row) > 5 else ''
    g2_val = str(get_val(header_row[6])).lower() if len(header_row) > 6 else ''
    
    # Check for reasonable header text
    has_table_header = 'table' in f2_val or 'number' in f2_val or f2_val.strip() in ['table number', 'table #', '#']
    has_count_header = 'count' in g2_val or 'guest' in g2_val or 'total' in g2_val
    
    if not has_table_header and not has_count_header:
        return False, f"❌ Summary headers unclear (F2: '{f2_val}', G2: '{g2_val}')"
    
    return True, "✅ Summary table headers present"


def check_summary_formulas(rows: List[List[Dict]], workbook: Dict, sheet_name: str) -> Tuple[bool, int, str]:
    """Check if summary table has COUNTIF formulas in column G."""
    from calc_verification_utils import get_cell_formula
    
    formula_count = 0
    formulas_found = []
    
    # Check rows 3-15 (indices 2-14) in column G for COUNTIF formulas
    for i in range(2, min(15, len(rows))):
        cell_ref = f"G{i+1}"  # Convert 0-based index to 1-based row number
        formula = get_cell_formula(workbook, sheet_name, cell_ref)
        
        if formula and 'COUNTIF' in str(formula).upper():
            formula_count += 1
            if len(formulas_found) < 3:
                formulas_found.append(f"{cell_ref}: {formula}")
    
    success = formula_count >= 3  # At least 3 tables should have formulas
    
    if success:
        message = f"✅ COUNTIF formulas found ({formula_count} formulas)"
    else:
        message = f"❌ Insufficient COUNTIF formulas (found {formula_count}, expected ≥3)"
    
    return success, formula_count, message


def check_summary_accuracy(rows: List[List[Dict]], table_counts: Dict[Any, int]) -> Tuple[bool, int, str]:
    """Check if summary table counts match actual table assignments."""
    if not table_counts:
        return False, 0, "❌ No table assignments to verify"
    
    def get_val(cell):
        if isinstance(cell, dict):
            return cell.get('value', '')
        return cell
    
    matches = 0
    mismatches = []
    
    # Check rows 3-15 (indices 2-14) for table numbers in F and counts in G
    for i in range(2, min(15, len(rows))):
        if i >= len(rows):
            break
        
        row = rows[i]
        if len(row) < 7:
            continue
        
        # Column F (index 5): table number
        # Column G (index 6): count
        table_val = get_val(row[5]) if len(row) > 5 else None
        count_val = get_val(row[6]) if len(row) > 6 else None
        
        if table_val is None or count_val is None:
            continue
        
        try:
            table_num = int(float(str(table_val)))
            summary_count = int(float(str(count_val)))
            actual_count = table_counts.get(table_num, 0)
            
            if summary_count == actual_count:
                matches += 1
            else:
                if len(mismatches) < 3:
                    mismatches.append(f"Table {table_num}: summary={summary_count}, actual={actual_count}")
        except (ValueError, TypeError):
            continue
    
    success = matches >= 3  # At least 3 tables should match
    
    if success:
        message = f"✅ Summary accurate ({matches} tables verified)"
    else:
        mismatch_str = ', '.join(mismatches) if mismatches else 'no matches found'
        message = f"❌ Summary inaccurate ({matches} matches). Issues: {mismatch_str}"
    
    return success, matches, message


def verify_wedding_seating(traj, env_info, task_info):
    """
    Verify wedding seating arrangement task completion.
    
    Checks:
    1. All guests assigned to tables
    2. No table exceeds 8 guests
    3. Wedding Party (8 people) at Table 1 exclusively
    4. Families seated together (80%+ threshold)
    5. Summary table exists with headers
    6. Summary table has COUNTIF formulas and accurate counts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations and formats
    file_paths = [
        ('ods', '/home/ga/Documents/wedding_seating.ods'),
        ('ods', '/home/ga/Documents/wedding_guest_list.ods'),
        ('csv', '/home/ga/Documents/wedding_guest_list.csv'),
        ('csv', '/home/ga/Documents/wedding_seating.csv'),
    ]
    
    success = False
    workbook = None
    temp_dir = None
    
    for fmt, path in file_paths:
        try:
            success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
                path, copy_from_env, file_format=fmt
            )
            if success:
                logger.info(f"Successfully loaded file: {path}")
                break
        except Exception as e:
            logger.debug(f"Failed to load {path}: {e}")
            continue
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Failed to load spreadsheet file. Tried: wedding_seating.ods, wedding_guest_list.ods/csv"
        }
    
    try:
        # Get first sheet
        sheet_name = list(workbook['sheets'].keys())[0]
        rows = workbook['sheets'][sheet_name]
        
        # Extract guest data (rows 3-66, indices 2-65)
        guests = extract_guest_data(rows, start_row=2, end_row=66)
        
        if len(guests) < 60:
            logger.warning(f"Only {len(guests)} guests found, expected ~64")
        
        # Initialize results
        results = {
            'all_assigned': False,
            'capacity_ok': False,
            'wedding_party_ok': False,
            'families_together': False,
            'summary_exists': False,
            'summary_accurate': False
        }
        feedback_parts = []
        
        # 1. Check all assigned
        all_assigned, empty_count, msg = check_all_assigned(guests)
        results['all_assigned'] = all_assigned
        feedback_parts.append(msg)
        
        # 2. Check capacity constraints
        capacity_ok, table_counts, msg = check_capacity_constraints(guests)
        results['capacity_ok'] = capacity_ok
        feedback_parts.append(msg)
        
        # 3. Check Wedding Party constraint
        wedding_ok, msg = check_wedding_party_constraint(guests)
        results['wedding_party_ok'] = wedding_ok
        feedback_parts.append(msg)
        
        # 4. Check family cohesion
        family_ok, cohesion_rate, msg = check_family_cohesion(guests)
        results['families_together'] = family_ok
        feedback_parts.append(msg)
        
        # 5. Check summary table exists
        summary_exists, msg = check_summary_table(rows)
        results['summary_exists'] = summary_exists
        feedback_parts.append(msg)
        
        # 6. Check summary formulas and accuracy
        if summary_exists:
            formulas_ok, formula_count, formula_msg = check_summary_formulas(rows, workbook, sheet_name)
            accuracy_ok, match_count, accuracy_msg = check_summary_accuracy(rows, table_counts)
            
            # Summary is accurate if both formulas exist AND counts match
            results['summary_accurate'] = formulas_ok and accuracy_ok
            feedback_parts.append(formula_msg)
            feedback_parts.append(accuracy_msg)
        else:
            feedback_parts.append("❌ Summary formulas not checked (table missing)")
        
        # Calculate score
        criteria_met = sum(results.values())
        score = int((criteria_met / 6.0) * 100)
        passed = score >= 70  # 4 out of 6 criteria
        
        # Generate detailed feedback
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "all_assigned": results['all_assigned'],
                "capacity_ok": results['capacity_ok'],
                "wedding_party_ok": results['wedding_party_ok'],
                "families_together": results['families_together'],
                "summary_exists": results['summary_exists'],
                "summary_accurate": results['summary_accurate']
            },
            "details": {
                "total_guests": len(guests),
                "unassigned_count": empty_count if not all_assigned else 0,
                "table_counts": {str(k): v for k, v in sorted(table_counts.items())},
                "family_cohesion_rate": f"{cohesion_rate*100:.0f}%" if family_ok is not None else "N/A"
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
