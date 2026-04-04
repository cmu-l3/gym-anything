#!/usr/bin/env python3
"""
Verifier for Archimedes Pi Polygon Exhaustion task.
"""

import json
import tempfile
import os
import zipfile
import re
import xml.etree.ElementTree as ET
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70


def parse_geogebra_xml(xml_content: str) -> Dict[str, Any]:
    """Parse key elements from GeoGebra XML content."""
    elements = {
        'sliders': [],
        'points': [],
        'polygons': [],
        'circles': [],
        'texts': [],
        'commands': [],
        'expressions': []
    }
    
    try:
        root = ET.fromstring(xml_content)
        
        # 1. Scan <element> tags
        for elem in root.iter('element'):
            etype = elem.get('type', '')
            label = elem.get('label', '')
            
            if etype == 'numeric':
                # Check for slider attributes
                slider = elem.find('slider')
                if slider is not None:
                    elements['sliders'].append({
                        'label': label,
                        'min': slider.get('min'),
                        'max': slider.get('max'),
                        'step': slider.get('step')
                    })
            elif etype == 'point':
                elements['points'].append({'label': label})
            elif etype == 'polygon':
                elements['polygons'].append({'label': label})
            elif etype == 'conic':
                # Check if it's a circle
                # GeoGebra defines circle x^2+y^2=r^2 with matrix:
                # x^2: 1, y^2: 1, const: -r^2
                matrix = elem.find('matrix')
                if matrix is not None:
                    a0 = float(matrix.get('A0', 0)) # x^2
                    a1 = float(matrix.get('A1', 0)) # xy
                    a3 = float(matrix.get('A3', 0)) # y^2
                    # Heuristic for circle
                    if abs(a0 - a3) < 0.001 and abs(a1) < 0.001 and abs(a0) > 0:
                        elements['circles'].append({'label': label})
            elif etype == 'text':
                # Get text content from val attribute (HTML encoded) or direct text
                # Often stored in 'val' or 'startPoint' attributes not obvious here
                # Easier to regex the XML for text content
                pass

        # 2. Scan <command> tags
        for cmd in root.iter('command'):
            name = cmd.get('name', '')
            elements['commands'].append({'name': name})

        # 3. Scan <expression> tags
        for expr in root.iter('expression'):
            exp_str = expr.get('exp', '')
            label = expr.get('label', '')
            elements['expressions'].append({'label': label, 'exp': exp_str})
            
        # 4. Extract text content specifically
        # Text elements often contain strings like "pi approx..."
        # We'll regex the whole content for efficiency in finding "pi" or "π"
        pass
        
    except ET.ParseError as e:
        logger.error(f"XML Parse Error: {e}")
        
    return elements


def verify_archimedes_pi_polygon_exhaustion(traj, env_info, task_info):
    """
    Verify the Archimedes Pi construction.
    
    Criteria:
    1. File created during task (15 pts)
    2. Unit circle present (15 pts)
    3. Slider 'n' present with range >= 3 to 48 (15 pts)
    4. Inscribed polygon present (20 pts)
    5. Circumscribed polygon or upper bound present (15 pts)
    6. Text annotation referencing Pi (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # Check Criterion 1: File Creation (15 pts)
    if result.get('file_exists') and result.get('file_created_during_task'):
        score += 15
        feedback_parts.append("File created (+15)")
    elif result.get('file_exists'):
        feedback_parts.append("File exists but not created during task (0/15)")
    else:
        feedback_parts.append("File not found (0/15)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Retrieve and Parse .ggb File
    temp_ggb = tempfile.NamedTemporaryFile(delete=False, suffix='.ggb')
    xml_content = ""
    try:
        copy_from_env(result['file_path'], temp_ggb.name)
        with zipfile.ZipFile(temp_ggb.name, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8')
    except Exception as e:
        feedback_parts.append(f"Failed to read .ggb file: {e}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    finally:
        if os.path.exists(temp_ggb.name):
            os.unlink(temp_ggb.name)

    if not xml_content:
        return {"passed": False, "score": score, "feedback": "Empty or invalid .ggb file"}

    parsed = parse_geogebra_xml(xml_content)
    xml_lower = xml_content.lower()
    
    # Check Criterion 2: Unit Circle (15 pts)
    # Looking for Circle((0,0), 1) or x^2 + y^2 = 1
    has_circle = False
    # Check commands
    if any(c['name'] == 'Circle' for c in parsed['commands']):
        has_circle = True
    # Check expressions
    elif 'x^2 + y^2 = 1' in xml_content or 'x² + y² = 1' in xml_content:
        has_circle = True
    # Check conics (simplified check)
    elif len(parsed['circles']) > 0:
        has_circle = True
        
    if has_circle:
        score += 15
        feedback_parts.append("Unit circle found (+15)")
    else:
        feedback_parts.append("Unit circle not found (0/15)")

    # Check Criterion 3: Slider n (15 pts)
    slider_found = False
    slider_correct = False
    for s in parsed['sliders']:
        if s['label'] == 'n':
            slider_found = True
            try:
                # Evaluating min/max which might be expressions or numbers
                # Simple check for numeric strings
                s_min = float(s['min']) if s['min'].replace('.','',1).isdigit() else 0
                s_max = float(s['max']) if s['max'].replace('.','',1).isdigit() else 100
                if s_min <= 3.5 and s_max >= 47.5:
                    slider_correct = True
            except:
                # If they are expressions, give benefit of doubt if name is 'n'
                slider_correct = True 
    
    if slider_correct:
        score += 15
        feedback_parts.append("Slider 'n' with correct range found (+15)")
    elif slider_found:
        score += 10
        feedback_parts.append("Slider 'n' found but range unclear (+10)")
    else:
        feedback_parts.append("Slider 'n' not found (0/15)")

    # Check Criterion 4: Inscribed Polygon (20 pts)
    # Look for Polygon command dependent on n, or Sequence command
    has_inscribed = False
    # Check for Sequence command which is typical for n-gons
    if any(c['name'] == 'Sequence' for c in parsed['commands']):
        # If sequence exists and polygon exists, likely constructed
        if len(parsed['polygons']) > 0 or any(c['name'] == 'Polygon' for c in parsed['commands']):
            has_inscribed = True
    # Check for Polygon(A, B, n) signature
    elif 'Polygon' in [c['name'] for c in parsed['commands']]:
        has_inscribed = True
        
    if has_inscribed:
        score += 20
        feedback_parts.append("Inscribed polygon construction found (+20)")
    else:
        feedback_parts.append("Inscribed polygon not found (0/20)")

    # Check Criterion 5: Circumscribed Polygon / Upper Bound (15 pts)
    # Evidence: Second polygon OR use of tan() function
    has_circumscribed = False
    if len(parsed['polygons']) >= 2:
        has_circumscribed = True
    elif 'tan(' in xml_lower or 'tan[' in xml_lower:
        has_circumscribed = True # likely computing n*tan(pi/n)
        
    if has_circumscribed:
        score += 15
        feedback_parts.append("Circumscribed polygon/upper bound found (+15)")
    else:
        feedback_parts.append("Circumscribed polygon/upper bound not found (0/15)")

    # Check Criterion 6: Text Annotation (20 pts)
    # Look for "pi" or "π" in text elements
    has_text = False
    if 'text' in xml_lower:
        # Simple regex for text content
        if re.search(r'(pi|π|3\.14)', xml_lower):
            has_text = True
            
    if has_text:
        score += 20
        feedback_parts.append("Text annotation found (+20)")
    else:
        feedback_parts.append("Text annotation referencing Pi not found (0/20)")

    # Check Pass Threshold
    passed = score >= PASS_THRESHOLD
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }