#!/usr/bin/env python3
"""
Verifier for Circular Reference Debugger task.
Checks that circular references are eliminated and calculations are correct.
"""

import sys
import os
import logging
import re
from collections import defaultdict, deque
from typing import Dict, List, Set, Tuple, Any

# Add utils to path - use relative path for host execution
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_cell_ref(cell_ref: str) -> Tuple[int, int]:
    """Parse cell reference like 'A1' into (col_index, row_index) 0-based"""
    col_str = ''
    row_str = ''
    
    for char in cell_ref:
        if char.isalpha():
            col_str += char.upper()
        elif char.isdigit():
            row_str += char
    
    # Convert column letters to index
    col_idx = 0
    for char in col_str:
        col_idx = col_idx * 26 + (ord(char) - ord('A') + 1)
    col_idx -= 1  # 0-based
    
    # Convert row number to index
    row_idx = int(row_str) - 1  # 0-based
    
    return col_idx, row_idx


def format_cell_ref(col_idx: int, row_idx: int) -> str:
    """Format cell reference from indices"""
    col_str = ''
    col = col_idx + 1
    
    while col > 0:
        col -= 1
        col_str = chr(ord('A') + (col % 26)) + col_str
        col //= 26
    
    return f"{col_str}{row_idx + 1}"


def extract_cell_references(formula: str) -> List[str]:
    """
    Extract cell references from a formula string.
    Handles OpenDocument format (of:=[.B14]) and standard format (=B14).
    """
    if not formula:
        return []
    
    refs = []
    
    # Pattern for standard cell references: A1, B23, AA100, etc.
    # Match word boundaries to avoid matching within longer strings
    standard_refs = re.findall(r'\b([A-Z]+[0-9]+)\b', formula.upper())
    refs.extend(standard_refs)
    
    # Pattern for OpenDocument format: [.B14] or [$Sheet1.B14]
    od_refs = re.findall(r'\[\.([A-Z]+[0-9]+)\]', formula.upper())
    refs.extend(od_refs)
    
    # Pattern for sheet references: [Sheet1.B14]
    sheet_refs = re.findall(r'\[[^\]]*\.([A-Z]+[0-9]+)\]', formula.upper())
    refs.extend(sheet_refs)
    
    # Remove duplicates while preserving order
    seen = set()
    unique_refs = []
    for ref in refs:
        if ref not in seen:
            seen.add(ref)
            unique_refs.append(ref)
    
    return unique_refs


def build_dependency_graph(workbook: Dict[str, Any], sheet_name: str) -> Dict[str, Set[str]]:
    """
    Build a dependency graph of cell references.
    Returns a dict mapping cell_ref -> set of cells it depends on.
    """
    graph = defaultdict(set)
    
    sheets = workbook.get('sheets', {})
    if sheet_name not in sheets:
        return graph
    
    rows = sheets[sheet_name]
    
    for row_idx, row in enumerate(rows):
        for col_idx, cell_data in enumerate(row):
            cell_ref = format_cell_ref(col_idx, row_idx)
            
            # Get formula if it exists
            if isinstance(cell_data, dict):
                formula = cell_data.get('formula', '')
            else:
                formula = ''
            
            if formula:
                # Extract all cell references from formula
                refs = extract_cell_references(formula)
                for ref in refs:
                    if ref != cell_ref:  # Don't include self-references
                        graph[cell_ref].add(ref)
    
    return graph


def detect_circular_references(graph: Dict[str, Set[str]]) -> List[List[str]]:
    """
    Detect circular references (cycles) in the dependency graph using DFS.
    Returns list of cycles found (each cycle is a list of cell references).
    """
    cycles = []
    visited = set()
    rec_stack = set()
    path = []
    
    def dfs(node: str) -> bool:
        """DFS to detect cycles. Returns True if cycle found."""
        if node in rec_stack:
            # Found a cycle - extract the cycle from path
            cycle_start = path.index(node)
            cycle = path[cycle_start:] + [node]
            cycles.append(cycle)
            return True
        
        if node in visited:
            return False
        
        visited.add(node)
        rec_stack.add(node)
        path.append(node)
        
        # Visit all dependencies
        for neighbor in graph.get(node, set()):
            dfs(neighbor)
        
        path.pop()
        rec_stack.remove(node)
        return False
    
    # Check all nodes
    for node in graph.keys():
        if node not in visited:
            dfs(node)
    
    return cycles


def check_for_formula_errors(workbook: Dict[str, Any], sheet_name: str) -> Dict[str, List[str]]:
    """
    Check for common formula errors in cells.
    Returns dict mapping error types to lists of cell references.
    """
    error_types = {
        '#REF!': [],
        '#VALUE!': [],
        '#DIV/0!': [],
        '#NAME?': [],
        '#N/A': [],
        '#NUM!': [],
        'Err:': [],  # Generic error
    }
    
    sheets = workbook.get('sheets', {})
    if sheet_name not in sheets:
        return error_types
    
    rows = sheets[sheet_name]
    
    for row_idx, row in enumerate(rows):
        for col_idx, cell_data in enumerate(row):
            cell_ref = format_cell_ref(col_idx, row_idx)
            
            if isinstance(cell_data, dict):
                value = cell_data.get('value', '')
            else:
                value = cell_data
            
            # Check if value is an error string
            if isinstance(value, str):
                for error_type in error_types:
                    if error_type in value:
                        error_types[error_type].append(cell_ref)
    
    return error_types


def verify_circular_ref_fix(traj, env_info, task_info):
    """
    Verify circular reference fix task completion.
    
    Checks:
    1. No circular references in dependency graph
    2. No formula errors (#REF!, #VALUE!, etc.)
    3. Key formulas still exist (not hard-coded)
    4. Grand Total (B15) equals expected value (~$40,500)
    5. Calculations are internally consistent
    6. Recalculation logic is sound
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/budget_circular.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        # Get first sheet
        sheet_name = list(workbook['sheets'].keys())[0]

        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []

        # Criterion 1: No circular references
        logger.info("Checking for circular references...")
        graph = build_dependency_graph(workbook, sheet_name)
        cycles = detect_circular_references(graph)
        
        no_circular_refs = len(cycles) == 0
        if no_circular_refs:
            criteria_passed += 1
            feedback_parts.append("✅ No circular references detected")
        else:
            cycle_strs = [' → '.join(cycle) for cycle in cycles[:3]]  # Show first 3 cycles
            feedback_parts.append(f"❌ Circular references found: {'; '.join(cycle_strs)}")

        # Criterion 2: No formula errors
        logger.info("Checking for formula errors...")
        errors = check_for_formula_errors(workbook, sheet_name)
        total_errors = sum(len(cells) for cells in errors.values())
        
        no_errors = total_errors == 0
        if no_errors:
            criteria_passed += 1
            feedback_parts.append("✅ No formula errors (#REF!, #VALUE!, etc.)")
        else:
            error_summary = []
            for error_type, cells in errors.items():
                if cells:
                    error_summary.append(f"{error_type} in {', '.join(cells[:3])}")
            feedback_parts.append(f"❌ Formula errors found: {'; '.join(error_summary[:2])}")

        # Criterion 3: Key formulas still exist
        logger.info("Checking that formulas are preserved...")
        # Check that important cells still have formulas (not just hard-coded values)
        key_formula_cells = ['B10', 'B12', 'B14', 'B15']  # Cells that should have formulas
        formulas_present = 0
        formulas_expected = len(key_formula_cells)
        
        for cell_ref in key_formula_cells:
            formula = get_cell_formula(workbook, sheet_name, cell_ref)
            if formula:
                formulas_present += 1
                logger.info(f"  {cell_ref}: {formula}")
        
        # Also check B8 (overhead) - it should either have a formula or be removed
        b8_formula = get_cell_formula(workbook, sheet_name, 'B8')
        b8_value = get_cell_value(workbook, sheet_name, 'B8')
        
        if b8_formula:
            # B8 has a formula - good! Check it doesn't reference B14
            if 'B14' not in b8_formula.upper() and '.B14' not in b8_formula.upper():
                formulas_present += 0.5  # Bonus for fixing B8 formula
                logger.info(f"  B8 formula fixed: {b8_formula}")
        
        formulas_used = formulas_present >= (formulas_expected * 0.6)  # At least 60% of formulas present
        if formulas_used:
            criteria_passed += 1
            feedback_parts.append(f"✅ Formulas preserved ({formulas_present}/{formulas_expected} key cells)")
        else:
            feedback_parts.append(f"❌ Too many hard-coded values ({formulas_present}/{formulas_expected} formulas found)")

        # Criterion 4: Grand Total is correct
        logger.info("Checking Grand Total calculation...")
        grand_total = get_cell_value(workbook, sheet_name, 'B15')
        
        # Expected value: $40,500 (Revenue $75,000 - Total Expenses $34,500)
        # Expenses: Salaries $25,000 + Supplies $5,000 + Overhead $4,500 (15% of $30,000)
        expected_total = 40500.0
        tolerance = 1.0  # $1 tolerance
        
        try:
            if grand_total is not None:
                grand_total_float = float(grand_total)
                total_correct = abs(grand_total_float - expected_total) <= tolerance
                
                if total_correct:
                    criteria_passed += 1
                    feedback_parts.append(f"✅ Grand Total correct: ${grand_total_float:,.2f}")
                else:
                    # Check if it's close to the expected value
                    diff = abs(grand_total_float - expected_total)
                    feedback_parts.append(f"❌ Grand Total incorrect: ${grand_total_float:,.2f} (expected ${expected_total:,.2f}, diff: ${diff:,.2f})")
            else:
                feedback_parts.append("❌ Grand Total (B15) is empty or error")
        except (ValueError, TypeError) as e:
            feedback_parts.append(f"❌ Grand Total not numeric: {grand_total}")

        # Criterion 5: Internal consistency
        logger.info("Checking calculation consistency...")
        # Verify that intermediate calculations make sense
        revenue = get_cell_value(workbook, sheet_name, 'B3')
        total_expenses = get_cell_value(workbook, sheet_name, 'B12')
        net_income = get_cell_value(workbook, sheet_name, 'B14')
        
        try:
            if revenue and total_expenses and net_income:
                revenue_float = float(revenue)
                expenses_float = float(total_expenses)
                income_float = float(net_income)
                
                # Net Income should equal Revenue - Total Expenses
                expected_income = revenue_float - expenses_float
                income_correct = abs(income_float - expected_income) <= tolerance
                
                if income_correct:
                    criteria_passed += 1
                    feedback_parts.append(f"✅ Calculations consistent (Net Income = Revenue - Expenses)")
                else:
                    feedback_parts.append(f"⚠️ Calculation inconsistency: Net Income ${income_float:,.2f} != Revenue ${revenue_float:,.2f} - Expenses ${expenses_float:,.2f}")
            else:
                feedback_parts.append("⚠️ Cannot verify consistency (missing values)")
        except (ValueError, TypeError):
            feedback_parts.append("⚠️ Cannot verify consistency (non-numeric values)")

        # Criterion 6: Solution quality (checks that the fix is logical)
        logger.info("Checking solution quality...")
        # Check that B8 (Overhead) is calculated reasonably
        b8_value = get_cell_value(workbook, sheet_name, 'B8')
        b8_formula = get_cell_formula(workbook, sheet_name, 'B8')
        
        overhead_reasonable = False
        if b8_value:
            try:
                overhead_float = float(b8_value)
                # Overhead should be around $4,500 (15% of $30,000 base expenses)
                # Accept range: $3,000 - $6,000
                if 3000 <= overhead_float <= 6000:
                    overhead_reasonable = True
                    if b8_formula:
                        # Bonus: formula exists and doesn't reference B14
                        if 'B14' not in b8_formula.upper() and '.B14' not in b8_formula.upper():
                            criteria_passed += 1
                            feedback_parts.append(f"✅ Overhead calculated correctly (${overhead_float:,.2f})")
                        else:
                            # Formula still references B14!
                            feedback_parts.append(f"⚠️ Overhead formula still references Net Income")
                    else:
                        # Hard-coded value - partial credit
                        criteria_passed += 0.5
                        feedback_parts.append(f"⚠️ Overhead hard-coded (${overhead_float:,.2f}) - formula preferred")
                else:
                    feedback_parts.append(f"⚠️ Overhead value unusual: ${overhead_float:,.2f}")
            except (ValueError, TypeError):
                pass
        
        if not overhead_reasonable and not b8_formula:
            feedback_parts.append("⚠️ Overhead calculation unclear")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 80  # Need 5/6 criteria (80%)
        
        # Add summary message
        if passed and score >= 95:
            feedback_parts.insert(0, "🎉 Excellent work! Circular reference eliminated perfectly!")
        elif passed:
            feedback_parts.insert(0, "✅ Circular reference fixed successfully")
        else:
            feedback_parts.insert(0, "❌ Circular reference not properly resolved")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "no_circular_refs": no_circular_refs,
                "no_formula_errors": no_errors,
                "formulas_preserved": formulas_used,
                "grand_total_correct": total_correct if 'total_correct' in locals() else False,
                "internally_consistent": income_correct if 'income_correct' in locals() else False,
                "overhead_reasonable": overhead_reasonable
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
