#!/usr/bin/env python3
"""
Shared verification utilities for LibreOffice Calc tasks.
Provides common functions used across multiple task verifiers.
"""

import logging
import sys
import os
from pathlib import Path
from typing import Tuple, Dict, Any, Callable
import tempfile
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils directory to path
# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    parse_ods_file,
    parse_xlsx_file,
    open_spreadsheet,
    get_cell_value,
    get_cell_formula,
    verify_cell_value,
    verify_cell_formula,
    verify_formula_result,
    check_chart_exists,
    check_conditional_formatting,
    check_pivot_table_exists,
    verify_pivot_table,
    check_data_validation,
    cleanup_verification_environment,
    setup_verification_environment as _base_setup_verification_environment
)


def setup_verification_environment(copy_from_env: Callable, result_file: str,
                                   additional_files: list = None) -> Tuple[bool, Dict[str, str], str]:
    """
    Set up verification environment by copying result files from container.
    
    Args:
        copy_from_env: Function to copy files from container
        result_file: Main result file path in container
        additional_files: Additional files to copy (optional)
        
    Returns:
        Tuple of (success, file_paths_dict, error_message)
    """
    temp_dir = Path(tempfile.mkdtemp(prefix='calc_verify_'))
    file_paths = {}
    
    try:
        # Copy main result file
        result_filename = Path(result_file).name
        host_result = temp_dir / result_filename
        
        try:
            copy_from_env(result_file, str(host_result))
        except Exception as e:
            cleanup_temp(temp_dir)
            return False, {}, f"Failed to copy result file: {e}"
        
        if not host_result.exists() or host_result.stat().st_size == 0:
            cleanup_temp(temp_dir)
            return False, {}, f"Result file not found or empty: {result_file}"
        
        file_paths['result'] = str(host_result)
        
        # Copy additional files if specified
        if additional_files:
            for add_file in additional_files:
                add_filename = Path(add_file).name
                host_add = temp_dir / add_filename
                
                try:
                    copy_from_env(add_file, str(host_add))
                    if host_add.exists():
                        file_paths[add_filename] = str(host_add)
                except Exception as e:
                    logger.warning(f"Failed to copy additional file {add_file}: {e}")
        
        file_paths['temp_dir'] = str(temp_dir)
        return True, file_paths, ""
        
    except Exception as e:
        cleanup_temp(temp_dir)
        return False, {}, f"Setup failed: {e}"


def cleanup_temp(temp_dir: Path = None):
    """Clean up temporary verification directory"""
    if temp_dir and Path(temp_dir).exists():
        try:
            shutil.rmtree(temp_dir)
        except Exception as e:
            logger.warning(f"Failed to cleanup temp directory: {e}")


def verify_cell_range_formula(workbook, sheet_name: str, start_cell: str, end_cell: str,
                              formula_pattern: str) -> Tuple[bool, str]:
    """
    Verify that cells in a range contain formulas matching a pattern.
    
    Args:
        workbook: SpreadsheetWrapper object
        sheet_name: Sheet name
        start_cell: Starting cell (e.g., 'A1')
        end_cell: Ending cell (e.g., 'A10')
        formula_pattern: Pattern to match (e.g., 'SUM')
        
    Returns:
        Tuple of (success, error_message)
    """
    # Parse cell addresses
    import re
    
    def parse_cell(cell):
        match = re.match(r'^([A-Z]+)(\d+)$', cell.upper())
        if not match:
            return None, None
        col, row = match.groups()
        return col, int(row)
    
    start_col, start_row = parse_cell(start_cell)
    end_col, end_row = parse_cell(end_cell)
    
    if not all([start_col, start_row, end_col, end_row]):
        return False, f"Invalid cell range: {start_cell}:{end_cell}"
    
    # Check each cell in range
    for row in range(start_row, end_row + 1):
        cell_addr = f"{start_col}{row}"
        formula = get_cell_formula(workbook, sheet_name, cell_addr)
        
        if formula and formula_pattern.upper() in formula.upper():
            continue
        else:
            return False, f"Cell {cell_addr} missing expected formula pattern '{formula_pattern}'"
    
    return True, ""


def compare_cell_values(workbook, sheet_name: str, cell_comparisons: list,
                       tolerance: float = 0.01) -> Tuple[bool, str]:
    """
    Compare multiple cell values against expected values.
    
    Args:
        workbook: SpreadsheetWrapper object
        sheet_name: Sheet name
        cell_comparisons: List of (cell_address, expected_value) tuples
        tolerance: Tolerance for float comparison
        
    Returns:
        Tuple of (all_match, error_message)
    """
    errors = []
    
    for cell_addr, expected_val in cell_comparisons:
        actual_val = get_cell_value(workbook, sheet_name, cell_addr)
        
        # Handle None values
        if actual_val is None and expected_val is None:
            continue
        if actual_val is None or expected_val is None:
            errors.append(f"Cell {cell_addr}: expected {expected_val}, got {actual_val}")
            continue
        
        # Compare based on type
        if isinstance(expected_val, (int, float)) and isinstance(actual_val, (int, float)):
            if abs(float(actual_val) - float(expected_val)) > tolerance:
                errors.append(f"Cell {cell_addr}: expected {expected_val}, got {actual_val}")
        else:
            if str(actual_val).strip() != str(expected_val).strip():
                errors.append(f"Cell {cell_addr}: expected '{expected_val}', got '{actual_val}'")
    
    if errors:
        return False, "; ".join(errors)
    return True, ""


def check_sheet_exists(workbook, sheet_name: str) -> bool:
    """Check if a sheet exists in workbook"""
    return sheet_name in workbook.get_sheet_names()


def get_non_empty_row_count(workbook, sheet_name: str, start_row: int = 1) -> int:
    """
    Count number of non-empty rows starting from start_row.
    
    Args:
        workbook: SpreadsheetWrapper object
        sheet_name: Sheet name
        start_row: Starting row number (1-indexed)
        
    Returns:
        Count of non-empty rows
    """
    count = 0
    row = start_row
    max_empty = 10  # Stop after 10 consecutive empty rows
    empty_count = 0
    
    while empty_count < max_empty and row < 10000:  # Safety limit
        cell_val = get_cell_value(workbook, sheet_name, f"A{row}")
        if cell_val:
            count += 1
            empty_count = 0
        else:
            empty_count += 1
        row += 1
    
    return count


# Export utility functions
__all__ = [
    'setup_verification_environment',
    'cleanup_temp',
    'verify_cell_range_formula',
    'compare_cell_values',
    'check_sheet_exists',
    'get_non_empty_row_count',
    # Re-export from calc_verification_utils
    'parse_ods_file',
    'parse_xlsx_file',
    'open_spreadsheet',
    'get_cell_value',
    'get_cell_formula',
    'verify_cell_value',
    'verify_cell_formula',
    'verify_formula_result',
    'check_chart_exists',
    'check_conditional_formatting',
    'check_pivot_table_exists',
    'verify_pivot_table',
    'check_data_validation',
    'cleanup_verification_environment'
]
