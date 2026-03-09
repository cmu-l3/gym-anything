#!/usr/bin/env python3
"""
Verifier for CNN Neural Network Visualization Task.
Verifies that the agent created a diagram matching the model summary
with correct shapes, labels, and colors.
"""

import json
import os
import tempfile
import logging
import base64
import zlib
import urllib.parse
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def decode_drawio_content(encoded_text):
    """
    Decodes the Draw.io XML format.
    Draw.io files often compress the diagram data.
    """
    try:
        # Standard draw.io compression: URL decode -> Base64 decode -> Inflate (no header)
        if not encoded_text or not encoded_text.strip():
            return None
        
        # Check if it's already plain XML (starts with <)
        if encoded_text.strip().startswith('<'):
            return encoded_text

        url_decoded = urllib.parse.unquote(encoded_text)
        data = base64.b64decode(url_decoded)
        # Decompress (wbits=-15 for raw deflate)
        xml_str = zlib.decompress(data, -15).decode('utf-8')
        return xml_str
    except Exception as e:
        logger.debug(f"Failed to decode content: {e}")
        return None

def parse_drawio_file(file_path):
    """
    Parses a .drawio file to extract shapes, labels, and styles.
    Returns a list of dicts representing cells.
    """
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        
        # draw.io files can have a <diagram> tag containing compressed data
        diagram_node = root.find('diagram')
        if diagram_node is not None and diagram_node.text:
            decoded_xml = decode_drawio_content(diagram_node.text)
            if decoded_xml:
                # Parse the inner XML
                root = ET.fromstring(decoded_xml)
            else:
                # Fallback: maybe uncompressed inside diagram tag?
                pass
        
        cells = []
        for mx_cell in root.findall(".//mxCell"):
            cell_data = {
                'id': mx_cell.get('id'),
                'value': mx_cell.get('value', ''),
                'style': mx_cell.get('style', ''),
                'vertex': mx_cell.get('vertex') == '1',
                'edge': mx_cell.get('edge') == '1'
            }
            # Normalize label: remove HTML tags if present, lower case
            value_clean = cell_data['value']
            # Simple strip of HTML-like tags if they exist (rough approximation)
            if '&lt;' in value_clean or '<' in value_clean:
                # Very basic cleanup, or just inspect raw
                pass
            cells.append(cell_data)
            
        return cells
    except Exception as e:
        logger.error(f"Error parsing drawio file: {e}")
        return []

def verify_cnn_neural_network_viz(traj, env_info, task_info):
    """
    Main verification function.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    required_labels = metadata.get('required_labels', [])
    colors = metadata.get('layer_colors', {})
    
    score = 0
    feedback = []

    # 1. Get Export Result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        os.unlink(temp_json.name)

    # 2. Check File Existence (10 pts)
    if result_data.get('drawio_exists') and result_data.get('drawio_modified_during_task'):
        score += 10
        feedback.append("Draw.io file created and modified.")
    else:
        feedback.append("Draw.io file missing or not saved.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    if result_data.get('pdf_exists'):
        score += 10
        feedback.append("PDF export found.")
    else:
        feedback.append("PDF export missing.")

    # 3. Analyze Content
    temp_drawio = tempfile.NamedTemporaryFile(delete=False, suffix='.drawio')
    try:
        copy_from_env("/home/ga/Diagrams/cnn_architecture.drawio", temp_drawio.name)
        cells = parse_drawio_file(temp_drawio.name)
    except Exception as e:
        feedback.append(f"Failed to analyze diagram content: {e}")
        cells = []
    finally:
        os.unlink(temp_drawio.name)

    # 4. Score Content (80 pts distributed)
    
    # Filter for visible shapes (vertices)
    shapes = [c for c in cells if c['vertex']]
    edges = [c for c in cells if c['edge']]
    
    # Criterion: Layer Count (20 pts)
    # Model has 8 layers (Input + 2xConv + 2xPool + Flatten + 2xDense) = 8 shapes expected
    # Prompt implies explicitly labeling output shapes. 
    # Let's count vertices that have text content.
    labeled_shapes = [s for s in shapes if s['value'].strip()]
    if len(labeled_shapes) >= 7:
        score += 20
        feedback.append(f"Layer count looks good ({len(labeled_shapes)} shapes found).")
    elif len(labeled_shapes) >= 4:
        score += 10
        feedback.append(f"Partial layer count ({len(labeled_shapes)}/7+ found).")
    else:
        feedback.append(f"Insufficient shapes found ({len(labeled_shapes)}).")

    # Criterion: Dimension Labels (30 pts)
    # Check if required dimension strings appear in the values
    found_dims = 0
    missing_dims = []
    
    # Normalize values for search
    all_text = " ".join([s['value'] for s in shapes]).lower()
    
    # Clean up required labels for searching (e.g. ensure x is handled)
    # The summary has: (None, 32, 32, 3), (None, 28, 28, 32), etc.
    # We look for "32x32x3", "28x28x32", etc.
    for lbl in required_labels:
        # Search strategy: strict substring
        if lbl in all_text:
            found_dims += 1
        else:
            missing_dims.append(lbl)
            
    if found_dims == len(required_labels):
        score += 30
        feedback.append("All dimension labels found.")
    elif found_dims >= len(required_labels) // 2:
        score += 15
        feedback.append(f"Some dimension labels found ({found_dims}/{len(required_labels)}). Missing: {missing_dims[:3]}...")
    else:
        feedback.append("Most dimension labels missing.")

    # Criterion: Color Coding (20 pts)
    # Check styles for hex codes
    # Blue: dae8fc, Red: f8cecc, Green: d5e8d4
    
    has_blue = any('dae8fc' in s['style'] for s in shapes)
    has_red = any('f8cecc' in s['style'] for s in shapes)
    has_green = any('d5e8d4' in s['style'] for s in shapes)
    
    colors_found = sum([has_blue, has_red, has_green])
    if colors_found == 3:
        score += 20
        feedback.append("Correct color coding applied (Blue/Red/Green).")
    elif colors_found > 0:
        score += 10
        feedback.append(f"Partial color coding ({colors_found}/3 colors found).")
    else:
        feedback.append("No correct color coding found.")

    # Criterion: Connectivity (10 pts)
    if len(edges) >= 6:
        score += 10
        feedback.append("Diagram is connected.")
    elif len(edges) > 0:
        score += 5
        feedback.append("Diagram partially connected.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }