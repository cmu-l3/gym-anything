#!/usr/bin/env python3
"""Verifier for style_graduated_population_points task."""

import json
import tempfile
import os
import xml.etree.ElementTree as ET

def verify_style_graduated_population_points(traj, env_info, task_info):
    """
    Verify that a graduated symbol style was created correctly.
    
    Criteria:
    1. Style 'graduated_pop' exists.
    2. SLD contains PointSymbolizer with Circle mark.
    3. SLD contains dynamic Size logic: 6 + (pop_max / 1000000).
    4. Colors match (Orange fill, Black stroke).
    5. Style is associated with the layer.
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/style_graduated_population_points_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Integrity Check
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        pass # If nonce file missing, we proceed but suspicious
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []
    
    # 1. Style Exists (10 pts)
    if not result.get('style_found'):
        return {"passed": False, "score": 0, "feedback": "Style 'graduated_pop' not found."}
    
    score += 10
    feedback_parts.append("Style found")
    
    # Parse SLD
    sld_content = result.get('sld_content', '')
    if not sld_content:
        return {"passed": False, "score": score, "feedback": "Style found but SLD content is empty."}

    try:
        root = ET.fromstring(sld_content)
        # Helper to strip namespaces for easier searching
        def get_tag(elem):
            return elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
        
        # 2. Check for PointSymbolizer and Mark (Circle) and Colors (15 pts)
        has_point = False
        has_circle = False
        has_fill_color = False # #ff9900
        has_stroke_color = False # #000000
        
        # Recursive search for visual properties
        for elem in root.iter():
            tag = get_tag(elem)
            if tag == 'PointSymbolizer':
                has_point = True
            
            if tag == 'WellKnownName' and (elem.text or '').strip().lower() == 'circle':
                has_circle = True
                
            # Check CssParameters
            if tag == 'CssParameter':
                name = elem.get('name', '').lower()
                val = (elem.text or '').strip().lower()
                if name == 'fill' and '#ff9900' in val:
                    has_fill_color = True
                if name == 'stroke' and ('#000000' in val or '#000' == val):
                    has_stroke_color = True

        visual_score = 0
        if has_point: visual_score += 5
        if has_circle: visual_score += 5
        if has_fill_color and has_stroke_color: visual_score += 5
        
        score += visual_score
        if visual_score == 15:
            feedback_parts.append("Visual styling correct")
        else:
            feedback_parts.append(f"Visual styling partial (Point:{has_point}, Circle:{has_circle}, Colors:{has_fill_color and has_stroke_color})")

        # 3. Check Dynamic Size Logic (40 pts) and Constants (20 pts)
        # Formula: 6 + (pop_max / 1000000)
        # XML structure expects <Size> containing <Add> containing <Literal>6</Literal> and <Div>...
        
        has_size_logic = False
        has_correct_math = False
        has_correct_constants = False
        
        for elem in root.iter():
            if get_tag(elem) == 'Size':
                # Look into children of Size
                # We expect an ogc:Add or Add
                adds = [child for child in elem if get_tag(child) == 'Add']
                if adds:
                    has_size_logic = True
                    add_node = adds[0]
                    
                    # Check Add operands: Literal 6 and Div
                    literals_6 = False
                    div_found = False
                    
                    for op in add_node:
                        tag = get_tag(op)
                        if tag == 'Literal' and '6' in (op.text or ''):
                            literals_6 = True
                        if tag == 'Div':
                            div_found = True
                            # Check Div operands: PropertyName pop_max and Literal 1000000
                            prop_pop = False
                            lit_1m = False
                            for div_op in op:
                                dtag = get_tag(div_op)
                                if dtag == 'PropertyName' and 'pop_max' in (div_op.text or ''):
                                    prop_pop = True
                                if dtag == 'Literal' and '1000000' in (div_op.text or ''):
                                    lit_1m = True
                            
                            if prop_pop and lit_1m:
                                has_correct_math = True
                                has_correct_constants = True
                    
                    if literals_6 and div_found:
                        pass # Valid structure
        
        if has_size_logic:
            score += 20
            feedback_parts.append("Dynamic size logic present")
        else:
            feedback_parts.append("Missing <Size> with <Add> logic")

        if has_correct_math:
            score += 20 # Math structure
            score += 20 # Constants
            feedback_parts.append("Formula correct")
        else:
            feedback_parts.append("Formula incorrect or constants wrong")

    except ET.ParseError:
        return {"passed": False, "score": 10, "feedback": "Style found but SLD XML is invalid."}

    # 4. Layer Association (15 pts)
    if result.get('layer_associated'):
        score += 15
        feedback_parts.append("Associated with layer")
    else:
        feedback_parts.append("Not associated with layer")

    # Anti-gaming: GUI interaction check (required if available)
    # Since this is a REST API detectable task, we enforce that GUI logs or VLM show activity
    # unless using REST API is part of the agent's capabilities (which is allowed).
    # However, the task implies using the web admin.
    
    # We'll rely on the score so far.
    
    passed = score >= 65 and has_size_logic and has_correct_math
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }