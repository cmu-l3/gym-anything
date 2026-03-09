#!/usr/bin/env python3
"""
Verifier for Polar Curve Gallery task.

Scoring (100 points):
- File created during task (15 pts)
- Three-petal rose present (20 pts)
- Cardioid present (20 pts)
- Slider + Parameterized Rose present (25 pts)
- Text annotations present (20 pts)

Pass Threshold: 70 points
"""

import json
import tempfile
import os
import zipfile
import re
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70

def parse_geogebra_xml(xml_content):
    """Parse GeoGebra XML and extract curves, sliders, and text."""
    try:
        # GeoGebra XML namespacing can be tricky, strip it or handle it
        # Simple extraction using regex for commands often works better than strict XML 
        # because we are looking for patterns in algebraic input
        
        # However, let's try to parse elements
        root = ET.fromstring(xml_content)
        
        elements = {
            'curves': [],
            'sliders': [],
            'texts': [],
            'commands': []
        }
        
        # 1. Find Commands (Curve commands usually live here)
        # <command name="Curve">
        #   <input a0="..." a1="..." ... />
        #   <output a0="curve1"/>
        # </command>
        for cmd in root.findall(".//command"):
            name = cmd.get("name")
            input_node = cmd.find("input")
            if input_node is not None:
                args = input_node.attrib
                # Concatenate all input args to search for formulas
                arg_str = " ".join(args.values())
                elements['commands'].append({'name': name, 'args': arg_str})
                
                if name == 'Curve':
                    elements['curves'].append(arg_str)

        # 2. Find Sliders (Numeric elements with slider property)
        # <element type="numeric" label="n">
        #   <slider min="1" max="8" ... />
        # </element>
        for elem in root.findall(".//element"):
            etype = elem.get("type")
            label = elem.get("label")
            
            if etype == "numeric":
                if elem.find("slider") is not None:
                    elements['sliders'].append(label)
            
            if etype == "text":
                # Get text content - usually in 'val' attribute of 'value' tag or similar
                # Or sometimes just the existence is enough
                elements['texts'].append(label)

        return elements
        
    except Exception as e:
        logger.error(f"XML Parsing Error: {e}")
        # Fallback: return raw strings found via regex if XML parse fails
        return None

def verify_polar_curve_gallery(traj, env_info, task_info):
    """Verify the polar curve gallery task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # 1. Retrieve Result JSON
    try:
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}

    score = 0
    feedback_parts = []
    
    # 2. Check File Creation (15 pts)
    if result.get("file_found") and result.get("file_created_during_task"):
        score += 15
        feedback_parts.append("File created during task (+15)")
    else:
        feedback_parts.append("File not created or timestamp invalid (0/15)")
        # If file missing, fail early
        if not result.get("file_found"):
            return {"passed": False, "score": 0, "feedback": "Polar curves file not found"}

    # 3. Retrieve and Parse .ggb File
    submission_path = result.get("submission_path")
    if not submission_path:
        return {"passed": False, "score": score, "feedback": " ".join(feedback_parts) + "; No submission path"}

    try:
        temp_ggb = tempfile.NamedTemporaryFile(delete=False, suffix='.ggb')
        copy_from_env(submission_path, temp_ggb.name)
        
        xml_content = ""
        with zipfile.ZipFile(temp_ggb.name, 'r') as zf:
            if 'geogebra.xml' in zf.namelist():
                xml_content = zf.read('geogebra.xml').decode('utf-8')
        
        os.unlink(temp_ggb.name)
        
        if not xml_content:
            return {"passed": False, "score": score, "feedback": "Invalid .ggb file (no XML found)"}

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Error reading .ggb file: {str(e)}"}

    # 4. Analyze Content
    # Use regex on raw XML content for robustness against XML structure variations
    # Normalize content (remove spaces, lowercase)
    norm_xml = re.sub(r'\s+', '', xml_content.lower())
    
    # Criterion: Rose Curve (r = sin(3t)) (20 pts)
    # Pattern: sin(3*t) or sin(3t)
    # In Curve command, input usually looks like: Curve[sin(3t)cos(t), sin(3t)sin(t), t, 0, 2pi]
    # We look for "sin(3" combined with "curve" context or just the formula presence
    has_rose = False
    if "sin(3" in norm_xml and "curve" in norm_xml:
        has_rose = True
        score += 20
        feedback_parts.append("Three-petal rose found (+20)")
    else:
        feedback_parts.append("Three-petal rose (sin(3t)) not found (0/20)")

    # Criterion: Cardioid (r = 1 + cos(t)) (20 pts)
    # Pattern: 1+cos(t) or (1+cos(t))
    has_cardioid = False
    if ("1+cos" in norm_xml or "cos(t)+1" in norm_xml) and "curve" in norm_xml:
        has_cardioid = True
        score += 20
        feedback_parts.append("Cardioid found (+20)")
    else:
        feedback_parts.append("Cardioid (1+cos(t)) not found (0/20)")

    # Criterion: Slider + Parameterized Rose (25 pts)
    # Need a slider (numeric element) and a curve using that slider var
    # Parse elements to find slider names
    parsed = parse_geogebra_xml(xml_content)
    sliders = parsed.get('sliders', []) if parsed else []
    
    has_param_rose = False
    if sliders:
        # Check if any curve command uses a slider name
        # Look for pattern: sin(slider_name * t)
        for slider in sliders:
            # Simple check: does the slider name appear in the normalized xml inside a curve-like context?
            # Or just check if "sin(" + slider + "*" in raw xml
            # A slider "n" might be hard to search for (common letter), so be careful
            
            # Robust check: Check extracted curve args from parser
            curves = parsed.get('curves', [])
            for c_args in curves:
                # remove spaces
                c_clean = c_args.replace(" ", "")
                # look for sin(n*t) or sin(n t)
                if f"sin({slider}" in c_clean or f"sin({slider}*" in c_clean:
                    has_param_rose = True
                    break
            if has_param_rose:
                break
    
    if has_param_rose:
        score += 25
        feedback_parts.append("Parameterized rose with slider found (+25)")
    elif sliders:
        # Partial credit for slider only
        score += 10
        feedback_parts.append("Slider found, but not linked to rose curve (+10)")
    else:
        feedback_parts.append("No slider/parameterized curve found (0/25)")

    # Criterion: Text Annotations (20 pts)
    # Need at least 2 text elements
    # Count <element type="text"> in raw xml
    text_count = len(re.findall(r'type="text"', xml_content))
    if text_count >= 2:
        score += 20
        feedback_parts.append(f"Text annotations found ({text_count}) (+20)")
    elif text_count == 1:
        score += 10
        feedback_parts.append("Only 1 text annotation found (+10)")
    else:
        feedback_parts.append("No text annotations found (0/20)")

    return {
        "passed": score >= PASS_THRESHOLD,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }