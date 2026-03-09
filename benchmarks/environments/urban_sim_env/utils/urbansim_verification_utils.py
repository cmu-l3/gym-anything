#!/usr/bin/env python3
"""Shared verification utilities for UrbanSim tasks."""

import json
import os
import tempfile
import re


def copy_result_json(env_info, remote_path="/tmp/task_result.json"):
    """Copy task result JSON from the VM and parse it."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return None, "Copy function not available"

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(remote_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        return result, None
    except Exception as e:
        return None, f"Failed to read result: {e}"
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)


def copy_file_from_env(env_info, remote_path, local_suffix='.tmp'):
    """Copy a file from the VM and return local path."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return None, "Copy function not available"

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=local_suffix)
    try:
        copy_from_env(remote_path, temp_file.name)
        return temp_file.name, None
    except Exception as e:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
        return None, f"Failed to copy file: {e}"


def validate_notebook_has_code(notebook_path, required_patterns):
    """Check if a notebook contains code matching required patterns.

    Strips string literals before matching to prevent gaming via keywords
    in strings. Also checks for execution errors.

    Args:
        notebook_path: Path to .ipynb file
        required_patterns: List of (name, regex_pattern) tuples

    Returns:
        dict with {name: bool} for each pattern, plus:
        - 'num_executed_cells': int
        - 'has_errors': bool
    """
    try:
        with open(notebook_path, 'r') as f:
            nb = json.load(f)
    except Exception:
        results = {name: False for name, _ in required_patterns}
        results['num_executed_cells'] = 0
        results['has_errors'] = False
        return results

    # Concatenate all code cell sources
    code_cells = [c for c in nb.get('cells', []) if c.get('cell_type') == 'code']
    code = ""
    for cell in code_cells:
        source = cell.get('source', '')
        if isinstance(source, list):
            source = ''.join(source)
        lines = [l for l in source.split('\n') if not l.strip().startswith('#')]
        code += '\n'.join(lines) + '\n'

    # Strip string literals to prevent gaming via keywords in strings
    clean_code = re.sub(r'"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'', '', code)
    clean_code = re.sub(r'"[^"\n]*"|\'[^\'\n]*\'', '', clean_code)

    # Check for error outputs in executed cells
    has_errors = False
    for cell in code_cells:
        if cell.get('execution_count') is not None:
            for out in cell.get('outputs', []):
                if out.get('output_type') == 'error':
                    has_errors = True
                    break

    num_executed = sum(1 for c in code_cells if c.get('execution_count') is not None)

    results = {}
    for name, pattern in required_patterns:
        results[name] = bool(re.search(pattern, clean_code, re.IGNORECASE))
    results['num_executed_cells'] = num_executed
    results['has_errors'] = has_errors
    return results


def validate_csv_output(csv_path, expected_columns=None, min_rows=1):
    """Validate a CSV output file.

    Returns:
        dict with validation results
    """
    import csv

    result = {
        'exists': False,
        'valid': False,
        'rows': 0,
        'columns': [],
        'has_expected_columns': False,
        'data': []
    }

    if not os.path.exists(csv_path):
        return result

    result['exists'] = True

    try:
        with open(csv_path, 'r') as f:
            reader = csv.DictReader(f)
            result['columns'] = reader.fieldnames or []
            rows = list(reader)
            result['rows'] = len(rows)
            result['data'] = rows
            result['valid'] = True

            if expected_columns:
                col_lower = [c.lower() for c in result['columns']]
                result['has_expected_columns'] = all(
                    c.lower() in col_lower for c in expected_columns
                )

            if result['rows'] < min_rows:
                result['valid'] = False

    except Exception:
        result['valid'] = False

    return result


def validate_png_file(png_path, min_size_kb=5):
    """Validate a PNG image file."""
    result = {
        'exists': False,
        'valid': False,
        'size_kb': 0
    }

    if not os.path.exists(png_path):
        return result

    result['exists'] = True
    result['size_kb'] = os.path.getsize(png_path) / 1024

    # Check PNG magic bytes
    try:
        with open(png_path, 'rb') as f:
            header = f.read(8)
            result['valid'] = header[:4] == b'\x89PNG'
    except Exception:
        result['valid'] = False

    if result['size_kb'] < min_size_kb:
        result['valid'] = False

    return result


def build_verifier_result(score, max_score, feedback_parts, pass_threshold=60,
                          execution_verified=True):
    """Build standardized verifier result dict."""
    final_score = min(score, max_score)
    passed = final_score >= pass_threshold and execution_verified
    feedback = "; ".join([f for f in feedback_parts if f])
    return {
        "passed": passed,
        "score": final_score,
        "feedback": feedback
    }
