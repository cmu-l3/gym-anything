#!/usr/bin/env python3
"""
Verifier for Graph Quadratic Function task.
"""

import json
import tempfile
import os
import zipfile
import xml.etree.ElementTree as ET
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_geogebra_xml_for_functions(xml_path):
    """Parse GeoGebra XML and extract function definitions."""
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()

        functions = []
        points = []

        # Find all elements in the construction
        for element in root.iter('element'):
            elem_type = element.get('type', '').lower()
            elem_label = element.get('label', '')

            if elem_type == 'function':
                # Try to get the function expression
                expr = ''
                for exp_elem in element.iter('expression'):
                    exp = exp_elem.get('exp', '')
                    if exp:
                        expr = exp
                        break

                # Also check for casMap (CAS expressions)
                for cas in element.iter('casMap'):
                    for entry in cas.iter('entry'):
                        key = entry.get('key', '')
                        val = entry.get('val', '')
                        if key and val:
                            expr = val

                functions.append({
                    'label': elem_label,
                    'expression': expr
                })

            elif elem_type == 'point':
                coords = element.find('.//coords')
                if coords is not None:
                    x = float(coords.get('x', 0))
                    y = float(coords.get('y', 0))
                    points.append({
                        'label': elem_label,
                        'x': x,
                        'y': y
                    })

        # Also look for commands that define functions
        for command in root.iter('command'):
            cmd_name = command.get('name', '')
            if cmd_name.lower() in ['function', 'polynomial']:
                output = command.find('.//output')
                if output is not None:
                    label = output.get('a0', '')
                    functions.append({
                        'label': label,
                        'expression': '',
                        'command': cmd_name
                    })

        return {'functions': functions, 'points': points}

    except Exception as e:
        logger.error(f"Error parsing GeoGebra XML: {e}")
        return None


def is_quadratic_function(expr):
    """Check if expression represents a quadratic function."""
    if not expr:
        return False

    expr_lower = expr.lower().replace(' ', '')

    # Patterns that indicate a quadratic function
    quadratic_patterns = [
        r'x\^2',           # x^2
        r'x²',             # x² (unicode)
        r'x\*x',           # x*x
        r'pow\(x,2\)',     # pow(x,2)
    ]

    for pattern in quadratic_patterns:
        if re.search(pattern, expr_lower):
            return True

    return False


def check_quadratic_coefficients(expr, expected_a=1, expected_b=-4, expected_c=3, tolerance=0.1):
    """
    Check if the quadratic ax² + bx + c has the expected coefficients.
    This is a simplified check - real verification would need symbolic math.
    """
    # For f(x) = x² - 4x + 3, we expect a=1, b=-4, c=3
    # This is a heuristic check based on the expression string
    expr_clean = expr.replace(' ', '').lower()

    # Look for patterns like:
    # x^2-4x+3, x^2-4*x+3, x²-4x+3, etc.
    matches_expected = False

    # Simple pattern matching for x^2 - 4x + 3 variants
    patterns = [
        r'x\^2-4\*?x\+3',
        r'x²-4\*?x\+3',
        r'x\*x-4\*?x\+3',
        r'\(x-1\)\*?\(x-3\)',  # Factored form
        r'\(x-3\)\*?\(x-1\)',  # Factored form (other order)
    ]

    for pattern in patterns:
        if re.search(pattern, expr_clean):
            matches_expected = True
            break

    return matches_expected


def check_marked_points(points, tolerance=0.1):
    """
    Check if the key points are marked on the quadratic graph.
    For f(x) = x² - 4x + 3:
    - Vertex: (2, -1)
    - X-intercepts (roots): (1, 0) and (3, 0)
    - Y-intercept: (0, 3)

    Args:
        points: List of point dicts with 'x' and 'y' coordinates
        tolerance: Maximum distance from expected point (default 0.1, matching task.json)

    Returns a dict with which points were found.
    """
    expected_points = {
        'vertex': (2, -1),
        'root1': (1, 0),
        'root2': (3, 0),
        'y_intercept': (0, 3)
    }

    found_points = {key: False for key in expected_points}

    for point in points:
        px, py = point.get('x', 0), point.get('y', 0)

        for key, (ex, ey) in expected_points.items():
            if abs(px - ex) <= tolerance and abs(py - ey) <= tolerance:
                found_points[key] = True

    return found_points


def verify_graph_quadratic_function(traj, env_info, task_info):
    """
    Verify graph quadratic function task completion.

    Checks:
    1. GeoGebra file exists and was created during task
    2. File contains at least one function definition
    3. Function is a quadratic (contains x^2 or equivalent)
    4. Key points are marked (vertex, roots, y-intercept)
    5. Optionally: function matches expected f(x) = x² - 4x + 3
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    tolerance = metadata.get('tolerance', 0.1)

    criteria_met = 0
    total_criteria = 4
    feedback_parts = []

    # Copy result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Criterion 1: File exists
    if result.get('file_found'):
        criteria_met += 1
        feedback_parts.append("GeoGebra file found")
    else:
        return {"passed": False, "score": 0, "feedback": "No GeoGebra file created"}

    # Criterion 2: File was created/modified DURING task (timestamp validation)
    # This prevents adversarial attacks using pre-made files
    file_created_during_task = result.get('file_created_during_task', False)
    task_start_time = result.get('task_start_time', 0)
    file_modified = result.get('file_modified', 0)

    # Try to parse as int if string
    try:
        file_modified = int(file_modified) if file_modified else 0
        task_start_time = int(task_start_time) if task_start_time else 0
    except (ValueError, TypeError):
        file_modified = 0
        task_start_time = 0

    if file_created_during_task:
        criteria_met += 1
        feedback_parts.append("File created during task (timestamp verified)")
    elif task_start_time > 0 and file_modified >= task_start_time:
        criteria_met += 1
        feedback_parts.append("File timestamp validated")
    else:
        # Fallback to file count check (less secure but backwards compatible)
        initial_count = result.get('initial_ggb_count', 0)
        current_count = result.get('current_ggb_count', 0)
        if current_count > initial_count:
            criteria_met += 1
            feedback_parts.append("New file detected (count increased)")
        else:
            feedback_parts.append("WARNING: File may pre-exist task (timestamp validation failed)")

    # Copy and parse the GeoGebra file
    temp_ggb = tempfile.NamedTemporaryFile(delete=False, suffix='.ggb')
    elements = None

    try:
        copy_from_env("/tmp/geogebra_result.ggb", temp_ggb.name)

        # Extract XML from .ggb (ZIP archive)
        temp_dir = tempfile.mkdtemp()
        with zipfile.ZipFile(temp_ggb.name, 'r') as z:
            z.extractall(temp_dir)

        xml_path = os.path.join(temp_dir, 'geogebra.xml')
        if os.path.exists(xml_path):
            elements = parse_geogebra_xml_for_functions(xml_path)

            # Also read the raw XML to check for quadratic patterns
            with open(xml_path, 'r') as f:
                raw_xml = f.read()
    except Exception as e:
        logger.error(f"Error extracting GeoGebra file: {e}")
        raw_xml = ""
    finally:
        if os.path.exists(temp_ggb.name):
            os.unlink(temp_ggb.name)

    # Criterion 3: Has QUADRATIC function (not just any function)
    # This prevents agents from passing by entering a wrong function type
    has_function = result.get('has_function', False)
    num_functions = result.get('num_functions', 0)

    # Check if any function is a quadratic
    is_quadratic_detected = False
    if elements:
        for func in elements.get('functions', []):
            expr = func.get('expression', '')
            if is_quadratic_function(expr):
                is_quadratic_detected = True
                break

    # Also check raw XML for quadratic patterns
    if not is_quadratic_detected and raw_xml:
        if re.search(r'x\^2|x²|x\*x|pow\(x,\s*2\)', raw_xml, re.IGNORECASE):
            is_quadratic_detected = True

    if is_quadratic_detected:
        criteria_met += 1
        feedback_parts.append(f"Quadratic function detected ({num_functions} function element(s))")
    elif has_function or num_functions > 0:
        # Function exists but it's not quadratic - no credit for criterion 3
        feedback_parts.append(f"Function detected but NOT quadratic (found {num_functions} function(s))")
    else:
        feedback_parts.append("No quadratic function detected in construction")

    # Criterion 4: Function is the expected quadratic
    function_verified = False

    if elements:
        for func in elements.get('functions', []):
            expr = func.get('expression', '')
            if is_quadratic_function(expr):
                if check_quadratic_coefficients(expr):
                    function_verified = True
                    feedback_parts.append(f"Correct quadratic f(x) = x² - 4x + 3 found")
                    break
                else:
                    feedback_parts.append(f"Quadratic found but may not match expected: {expr}")

    # Fallback: check raw XML for the expected function
    if not function_verified and raw_xml:
        if re.search(r'x\^2\s*-\s*4\*?x\s*\+\s*3', raw_xml, re.IGNORECASE):
            function_verified = True
            feedback_parts.append("Correct quadratic x² - 4x + 3 detected")
        elif re.search(r'\(x-1\).*\(x-3\)|\(x-3\).*\(x-1\)', raw_xml, re.IGNORECASE):
            function_verified = True
            feedback_parts.append("Correct quadratic (factored form) detected")

    if function_verified:
        criteria_met += 1
    else:
        # Give partial credit for any quadratic
        if re.search(r'x\^2|x²', raw_xml, re.IGNORECASE):
            feedback_parts.append("A quadratic function was graphed (may not match expected)")

    # Criterion 5: Key points are marked (vertex, roots, y-intercept)
    # This is a REQUIRED criterion - marking key points is part of the task
    total_criteria = 5

    key_points_met = False
    if elements:
        points = elements.get('points', [])
        if points:
            # Use tolerance from metadata (default 0.1) for consistent behavior
            found_points = check_marked_points(points, tolerance=tolerance)
            num_found = sum(found_points.values())

            # Require at least 3 key points to be marked (vertex + at least 2 of: roots, y-intercept)
            if num_found >= 3:
                key_points_met = True
                criteria_met += 1
                marked_names = [k for k, v in found_points.items() if v]
                feedback_parts.append(f"Key points marked: {', '.join(marked_names)}")
            elif num_found >= 1:
                # Some points marked but not enough - give informative feedback
                marked_names = [k for k, v in found_points.items() if v]
                missing_names = [k for k, v in found_points.items() if not v]
                feedback_parts.append(f"Insufficient key points: found {', '.join(marked_names)}, missing {', '.join(missing_names)}")
            else:
                feedback_parts.append("REQUIRED: Mark key points (vertex, x-intercepts, y-intercept)")
        else:
            feedback_parts.append("REQUIRED: Mark key points (vertex, x-intercepts, y-intercept)")
    else:
        feedback_parts.append("Could not verify marked points")

    # Calculate score
    score = int((criteria_met / total_criteria) * 100)

    # To pass, need at least 75% AND must have marked key points
    # This makes key points a hard requirement
    passed = score >= 75 and key_points_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
