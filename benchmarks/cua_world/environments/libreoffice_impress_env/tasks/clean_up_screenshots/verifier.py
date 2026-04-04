#!/usr/bin/env python3
"""
Verifier for clean_up_screenshots task.

Checks:
1. File was modified/saved.
2. Image on Slide 2 has cropping applied (fo:clip).
3. Image on Slide 2 has a border applied (fo:border).
4. Border color is blue-ish.
"""

import json
import tempfile
import os
import logging
import zipfile
import re
from xml.dom import minidom

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_clean_up_screenshots(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_path = metadata.get('target_file', "/home/ga/Documents/Presentations/HR_Portal_Guide.odp")
    
    # Scoring breakdown
    score = 0
    feedback_parts = []
    
    # 1. Get Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_data.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Target file HR_Portal_Guide.odp not found"}
    
    if result_data.get("file_modified"):
        score += 10
        feedback_parts.append("File saved successfully (10/10)")
    else:
        feedback_parts.append("Warning: File timestamp indicates no save occurred")

    # 2. Analyze ODP Content
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env(target_path, temp_odp.name)
        
        # Extract content.xml
        with zipfile.ZipFile(temp_odp.name, 'r') as z:
            content_xml = z.read('content.xml')
            
        dom = minidom.parseString(content_xml)
        
        # Find Slide 2 (draw:page)
        pages = dom.getElementsByTagName('draw:page')
        if len(pages) < 2:
            return {"passed": False, "score": score, "feedback": "Presentation structure corrupted (missing slides)"}
        
        slide2 = pages[1]
        
        # Find Image Frame on Slide 2
        # Look for draw:frame containing draw:image
        frames = slide2.getElementsByTagName('draw:frame')
        target_frame = None
        for frame in frames:
            if frame.getElementsByTagName('draw:image'):
                target_frame = frame
                break
        
        if not target_frame:
             return {"passed": False, "score": score, "feedback": "No image found on Slide 2"}
             
        # Get Style Name
        style_name = target_frame.getAttribute('draw:style-name')
        if not style_name:
             # Sometimes style is on the image element itself or parent
             # But usually draw:frame handles crop/border
             pass

        # Find the Automatic Style definition
        auto_styles = dom.getElementsByTagName('office:automatic-styles')[0]
        style_node = None
        for s in auto_styles.getElementsByTagName('style:style'):
            if s.getAttribute('style:name') == style_name:
                style_node = s
                break
        
        if not style_node:
            return {"passed": False, "score": score, "feedback": "Could not locate image style definition"}
            
        # Get Graphic Properties
        graphic_props = style_node.getElementsByTagName('style:graphic-properties')
        if not graphic_props:
            return {"passed": False, "score": score, "feedback": "No graphic properties found for image"}
        
        props = graphic_props[0]
        
        # --- VERIFY CROP (fo:clip) ---
        # Format: "rect(top right bottom left)" e.g. "rect(2.54cm 0cm 1.27cm 0cm)"
        clip_attr = props.getAttribute('fo:clip')
        
        top_crop_val = 0.0
        bottom_crop_val = 0.0
        
        if clip_attr and clip_attr.startswith("rect("):
            # Clean up string: remove rect( and )
            inner = clip_attr.replace("rect(", "").replace(")", "").replace(",", " ")
            parts = inner.split()
            if len(parts) == 4:
                # Top is index 0, Bottom is index 2
                # Need to parse "2.54cm" or "1in"
                def parse_length(s):
                    s = s.lower()
                    if 'cm' in s: return float(s.replace('cm',''))
                    if 'mm' in s: return float(s.replace('mm','')) / 10
                    if 'in' in s: return float(s.replace('in','')) * 2.54
                    if 'pt' in s: return float(s.replace('pt','')) * 0.0352778
                    return 0.0
                
                top_crop_val = parse_length(parts[0])
                bottom_crop_val = parse_length(parts[2])

        # Score Crop
        if top_crop_val > 0.4: # Tolerance > 0.4cm
            score += 30
            feedback_parts.append(f"Top crop applied ({top_crop_val:.2f}cm) (30/30)")
        elif top_crop_val > 0:
            score += 15
            feedback_parts.append(f"Top crop too small ({top_crop_val:.2f}cm) (15/30)")
        else:
            feedback_parts.append("No top crop detected (0/30)")
            
        if bottom_crop_val > 0.1: # Tolerance > 0.1cm
            score += 20
            feedback_parts.append(f"Bottom crop applied ({bottom_crop_val:.2f}cm) (20/20)")
        elif bottom_crop_val > 0:
            score += 10
            feedback_parts.append(f"Bottom crop too small ({bottom_crop_val:.2f}cm) (10/20)")
        else:
            feedback_parts.append("No bottom crop detected (0/20)")

        # --- VERIFY BORDER (fo:border) ---
        # Attribute could be fo:border, or distinct fo:border-top, etc.
        # Format: "0.07cm solid #0000ff"
        border_attr = props.getAttribute('fo:border')
        border_width = props.getAttribute('style:border-line-width') # Sometimes separate
        
        has_border = False
        is_blue = False
        
        if border_attr and border_attr != "none":
            has_border = True
            # Check color in string
            if "#" in border_attr:
                # Extract hex
                color_match = re.search(r'#(?:[0-9a-fA-F]{3}){1,2}', border_attr)
                if color_match:
                    c = color_match.group(0).lower()
                    # Check if blue-ish (High blue component, lower red/green)
                    # Simplified check for standard blue hexes or just "blue"
                    if "blue" in border_attr.lower():
                        is_blue = True
                    elif len(c) == 7:
                        r, g, b = int(c[1:3], 16), int(c[3:5], 16), int(c[5:7], 16)
                        if b > r and b > g and b > 100:
                            is_blue = True
        
        # Score Border
        if has_border:
            score += 20
            feedback_parts.append("Border applied (20/20)")
        else:
            feedback_parts.append("No border found (0/20)")
            
        if has_border and is_blue:
            score += 20
            feedback_parts.append("Border color is blue (20/20)")
        elif has_border:
            feedback_parts.append("Border color is not blue (0/20)")
        else:
            # Cannot have correct color without border
            pass

    except Exception as e:
        logger.error(f"Error parsing ODP: {e}")
        return {"passed": False, "score": score, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }