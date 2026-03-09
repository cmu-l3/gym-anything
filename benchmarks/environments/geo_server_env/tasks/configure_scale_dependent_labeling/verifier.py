#!/usr/bin/env python3
"""Verifier for configure_scale_dependent_labeling task."""

import json
import tempfile
import os
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_scale_dependent_labeling(traj, env_info, task_info):
    """
    Verify the scale-dependent styling task.
    
    Criteria:
    1. Style 'scaled_cities' exists (10 pts)
    2. Style is assigned to 'ne_populated_places' (10 pts)
    3. SLD Analysis:
       - Contains PointSymbolizer (20 pts)
       - Contains TextSymbolizer with Font/Halo (20 pts)
       - Contains correct ScaleDenominator (~20M) (20 pts)
    4. Visual Verification: Zoomed-in map has significantly higher complexity (labels) than zoomed-out map (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Style Exists
    if result.get('style_exists'):
        score += 10
        feedback_parts.append("Style 'scaled_cities' created")
    else:
        return {"passed": False, "score": 0, "feedback": "Style 'scaled_cities' not found"}

    # 2. Assignment
    assigned = result.get('assigned_style', '')
    if assigned == 'scaled_cities':
        score += 10
        feedback_parts.append("Style correctly assigned to layer")
    else:
        feedback_parts.append(f"Layer uses style '{assigned}' (expected 'scaled_cities')")

    # 3. SLD Analysis
    sld_content = result.get('sld_content', '')
    has_point = False
    has_text = False
    has_font = False
    has_halo = False
    max_scale_val = 0
    
    if sld_content:
        try:
            # Simple parsing ignoring namespaces for robustness
            root = ET.fromstring(sld_content)
            
            # Helper to strip namespace
            def local_tag(tag):
                return tag.split('}')[-1] if '}' in tag else tag
                
            for elem in root.iter():
                tag = local_tag(elem.tag)
                
                if tag == 'PointSymbolizer':
                    has_point = True
                
                if tag == 'TextSymbolizer':
                    has_text = True
                    # Check children for Font/Halo
                    for child in elem.iter():
                        ctag = local_tag(child.tag)
                        if ctag == 'Font': has_font = True
                        if ctag == 'Halo': has_halo = True
                
                if tag == 'MaxScaleDenominator':
                    try:
                        val = float(elem.text)
                        # We are looking for the scale constraint on labels
                        # There might be multiple rules, but we look for one around 20M
                        if 15000000 <= val <= 25000000:
                            max_scale_val = val
                    except:
                        pass
        except Exception as e:
            feedback_parts.append(f"SLD parsing error: {str(e)}")

    if has_point:
        score += 20
        feedback_parts.append("Point symbolizer found")
    else:
        feedback_parts.append("Missing PointSymbolizer")
        
    if has_text and has_font and has_halo:
        score += 20
        feedback_parts.append("Text symbolizer with halo found")
    elif has_text:
        score += 10
        feedback_parts.append("Text symbolizer found but missing Font or Halo")
    else:
        feedback_parts.append("Missing TextSymbolizer")

    if max_scale_val > 0:
        score += 20
        feedback_parts.append(f"Scale denominator correct ({max_scale_val})")
    else:
        feedback_parts.append("Scale denominator missing or incorrect (expected ~20,000,000)")

    # 4. Visual Verification
    stats = result.get('visual_stats', {})
    colors_out = stats.get('zoomed_out_colors', 0)
    colors_in = stats.get('zoomed_in_colors', 0)
    
    # Logic: Zoomed in map should have significantly more unique colors due to text rendering (anti-aliasing)
    # A map with just red dots (zoomed out) has very few unique colors.
    # A map with text labels and halos has many more.
    
    # Safety check: ensure images were generated
    if stats.get('zoomed_in_size', 0) > 1000 and stats.get('zoomed_out_size', 0) > 1000:
        if colors_in > (colors_out * 1.5) and colors_in > 50:
            score += 20
            feedback_parts.append("Visual check passed: Labels visible only when zoomed in")
        elif colors_in > 50 and colors_out > 50:
            # Both complex? Maybe labels are always on
            feedback_parts.append("Visual check warning: Labels might be visible at all scales")
            score += 5 # Partial credit if at least map is rendering
        elif colors_in < 20 and colors_out < 20:
             feedback_parts.append("Visual check failed: Map appears empty or simple geometry only")
        else:
             feedback_parts.append(f"Visual check inconclusive (Out:{colors_out} cols, In:{colors_in} cols)")
    else:
        feedback_parts.append("Visual check failed: WMS generation failed")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }