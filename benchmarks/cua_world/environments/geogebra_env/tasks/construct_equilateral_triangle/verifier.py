#!/usr/bin/env python3
"""
Verifier for Construct Equilateral Triangle task.
"""

import json
import tempfile
import os
import zipfile
import xml.etree.ElementTree as ET
import math
import logging
from itertools import combinations

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_geogebra_xml(xml_path):
    """Parse GeoGebra XML and extract construction elements."""
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()

        elements = {
            'points': [],
            'segments': [],
            'polygons': [],
            'circles': [],
            'lines': [],
            'polygon_vertices': []  # Track polygon vertex labels
        }

        # Find all elements in the construction
        construction = root.find('.//construction')
        if construction is None:
            # Try alternate structure
            construction = root

        # First, find polygon commands to identify vertex points
        for command in construction.findall('.//command'):
            cmd_name = command.get('name', '').lower()
            if cmd_name == 'polygon':
                # Extract input vertices (a0, a1, a2, etc.)
                input_elem = command.find('.//input')
                if input_elem is not None:
                    for attr in input_elem.attrib:
                        if attr.startswith('a'):
                            vertex_label = input_elem.get(attr)
                            if vertex_label:
                                elements['polygon_vertices'].append(vertex_label)

        for element in construction.findall('.//element'):
            elem_type = element.get('type', '').lower()
            elem_label = element.get('label', '')

            if elem_type == 'point':
                # Extract coordinates
                coords = element.find('.//coords')
                if coords is not None:
                    x = float(coords.get('x', 0))
                    y = float(coords.get('y', 0))
                    elements['points'].append({
                        'label': elem_label,
                        'x': x,
                        'y': y
                    })
            elif elem_type == 'segment':
                elements['segments'].append({'label': elem_label})
            elif elem_type == 'polygon':
                elements['polygons'].append({'label': elem_label})
            elif elem_type == 'circle':
                elements['circles'].append({'label': elem_label})
            elif elem_type == 'line':
                elements['lines'].append({'label': elem_label})

        return elements
    except Exception as e:
        logger.error(f"Error parsing GeoGebra XML: {e}")
        return None


def calculate_distance(p1, p2):
    """Calculate distance between two points."""
    return math.sqrt((p2['x'] - p1['x'])**2 + (p2['y'] - p1['y'])**2)


def calculate_angle(p1, p2, p3):
    """Calculate angle at p2 formed by p1-p2-p3 in degrees."""
    # Vectors from p2 to p1 and p2 to p3
    v1 = (p1['x'] - p2['x'], p1['y'] - p2['y'])
    v2 = (p3['x'] - p2['x'], p3['y'] - p2['y'])

    # Dot product and magnitudes
    dot = v1[0]*v2[0] + v1[1]*v2[1]
    mag1 = math.sqrt(v1[0]**2 + v1[1]**2)
    mag2 = math.sqrt(v2[0]**2 + v2[1]**2)

    if mag1 == 0 or mag2 == 0:
        return 0

    cos_angle = max(-1, min(1, dot / (mag1 * mag2)))
    return math.degrees(math.acos(cos_angle))


def check_triangle(p1, p2, p3, side_tolerance=0.1, angle_tolerance=2.0):
    """
    Check if three points form an equilateral triangle.
    Returns (is_equilateral, side_lengths, angles, score, details)

    score: 0-100 based on how close to equilateral
    """
    # Calculate side lengths
    side_a = calculate_distance(p1, p2)
    side_b = calculate_distance(p2, p3)
    side_c = calculate_distance(p3, p1)
    sides = [side_a, side_b, side_c]

    if min(sides) < 0.1:
        return False, sides, [], 0, "Triangle has near-zero side length"

    # Calculate angles
    angle_at_p1 = calculate_angle(p2, p1, p3)
    angle_at_p2 = calculate_angle(p1, p2, p3)
    angle_at_p3 = calculate_angle(p1, p3, p2)
    angles = [angle_at_p1, angle_at_p2, angle_at_p3]

    # Check if sides are equal (within tolerance)
    avg_side = sum(sides) / 3
    side_dev = max(abs(s - avg_side) / avg_side for s in sides) if avg_side > 0 else 1
    sides_equal = side_dev <= side_tolerance

    # Check if angles are 60 degrees (within tolerance)
    max_angle_dev = max(abs(a - 60.0) for a in angles)
    angles_equal = max_angle_dev <= angle_tolerance

    is_equilateral = sides_equal and angles_equal

    # Calculate a score based on how close to equilateral (0-100)
    # Lower deviation = higher score
    side_score = max(0, 100 - (side_dev * 500))  # 0.2 deviation = 0 score
    angle_score = max(0, 100 - (max_angle_dev * 10))  # 10 degree deviation = 0 score
    score = (side_score + angle_score) / 2

    details = f"Sides: {side_a:.2f}, {side_b:.2f}, {side_c:.2f} | Angles: {angle_at_p1:.1f}°, {angle_at_p2:.1f}°, {angle_at_p3:.1f}°"

    return is_equilateral, sides, angles, score, details


def find_best_triangle(points, polygon_vertices=None, strict_polygon_only=True, angle_tolerance=2.0):
    """
    Find the triangle to verify.

    STRICT MODE (default): Only uses polygon vertices. This prevents exploitation
    where an agent creates many random points hoping 3 accidentally form equilateral.

    Priority:
    1. If polygon_vertices are specified, use ONLY those points
    2. If strict_polygon_only=False and no polygon, fall back to first 3 points

    Args:
        points: List of point dicts with 'label', 'x', 'y'
        polygon_vertices: List of vertex labels from polygon command
        strict_polygon_only: If True, require polygon vertices (default True)
        angle_tolerance: Tolerance in degrees for equilateral check (default 2.0)

    Returns (best_points, is_equilateral, sides, angles, details, used_polygon)
    The used_polygon flag indicates whether polygon vertices were used (for scoring).
    """
    if len(points) < 3:
        return None, False, [], [], "Need at least 3 points", False

    # Create a lookup dict for points by label
    point_by_label = {p['label']: p for p in points}

    # Priority 1: Use polygon vertices if available (REQUIRED in strict mode)
    if polygon_vertices and len(polygon_vertices) >= 3:
        vertex_points = []
        for label in polygon_vertices[:3]:  # Take first 3 vertex labels
            if label in point_by_label:
                vertex_points.append(point_by_label[label])

        if len(vertex_points) == 3:
            is_eq, sides, angles, score, details = check_triangle(
                vertex_points[0], vertex_points[1], vertex_points[2],
                angle_tolerance=angle_tolerance
            )
            return vertex_points, is_eq, sides, angles, details, True

    # If strict mode and no polygon found, this is a failure
    if strict_polygon_only:
        # Agent must create a polygon, not just random points
        return None, False, [], [], "No polygon found - triangle must be constructed with connected vertices (use Polygon tool)", False

    # Non-strict fallback: use first 3 points (with penalty indicated by used_polygon=False)
    if len(points) >= 3:
        p1, p2, p3 = points[0], points[1], points[2]
        is_eq, sides, angles, score, details = check_triangle(p1, p2, p3, angle_tolerance=angle_tolerance)
        return [p1, p2, p3], is_eq, sides, angles, details + " (WARNING: no polygon, using first 3 points)", False

    return None, False, [], [], "Not enough points", False


def verify_construct_equilateral_triangle(traj, env_info, task_info):
    """
    Verify equilateral triangle construction task completion.

    Checks:
    1. GeoGebra file exists
    2. File was created/modified DURING the task (timestamp validation)
    3. File contains geometric construction (points, segments/polygon)
    4. Triangle vertices form an equilateral triangle (equal sides, 60° angles ±2°)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    tolerance_degrees = metadata.get('tolerance_degrees', 2.0)

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

    # Try to parse file_modified as int if it's a string
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
        # Double-check timestamp validation
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
    temp_xml = None
    elements = None

    try:
        copy_from_env("/tmp/geogebra_result.ggb", temp_ggb.name)

        # Extract XML from .ggb (ZIP archive)
        temp_dir = tempfile.mkdtemp()
        with zipfile.ZipFile(temp_ggb.name, 'r') as z:
            z.extractall(temp_dir)

        xml_path = os.path.join(temp_dir, 'geogebra.xml')
        if os.path.exists(xml_path):
            elements = parse_geogebra_xml(xml_path)
    except Exception as e:
        logger.error(f"Error extracting GeoGebra file: {e}")
    finally:
        if os.path.exists(temp_ggb.name):
            os.unlink(temp_ggb.name)

    if elements is None:
        return {
            "passed": False,
            "score": int((criteria_met / total_criteria) * 100),
            "feedback": " | ".join(feedback_parts) + " | Could not parse GeoGebra file"
        }

    # Criterion 3: Has sufficient construction elements
    num_points = len(elements.get('points', []))
    has_segments = len(elements.get('segments', [])) > 0
    has_polygons = len(elements.get('polygons', [])) > 0

    if num_points >= 3 and (has_segments or has_polygons):
        criteria_met += 1
        feedback_parts.append(f"Construction has {num_points} points, segments/polygon present")
    else:
        feedback_parts.append(f"Incomplete construction: {num_points} points, segments={has_segments}, polygons={has_polygons}")

    # Criterion 4: Triangle is equilateral
    # STRICT: Only use polygon vertices to prevent random point exploitation
    points = elements.get('points', [])
    polygon_vertices = elements.get('polygon_vertices', [])

    if len(points) >= 3:
        # strict_polygon_only=True requires a proper polygon construction
        # Pass tolerance_degrees from metadata to ensure consistent tolerance checking
        result = find_best_triangle(
            points, polygon_vertices,
            strict_polygon_only=True,
            angle_tolerance=tolerance_degrees
        )
        best_points, is_equilateral, sides, angles, details, used_polygon = result

        if best_points is None:
            # No polygon found - strict mode requires polygon
            feedback_parts.append(details)  # Will contain "No polygon found..." message
        elif is_equilateral:
            # Triangle passes the equilateral check with the configured tolerance
            criteria_met += 1
            vertex_labels = [p['label'] for p in best_points] if best_points else []
            feedback_parts.append(f"Equilateral triangle verified! Vertices: {vertex_labels} | {details}")
        else:
            # Triangle exists but doesn't meet equilateral criteria
            # Provide informative feedback about how close it was
            if angles and all(55 <= a <= 65 for a in angles):
                # Somewhat close but outside strict tolerance
                feedback_parts.append(f"Nearly equilateral (outside ±{tolerance_degrees}° tolerance): {details}")
            else:
                feedback_parts.append(f"Not equilateral: {details}")
    else:
        feedback_parts.append("Not enough points for triangle verification")

    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
