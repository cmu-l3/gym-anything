#!/usr/bin/env python3
"""
Verifier for Customer Journey Map task.
Checks the draw.io XML content for expected shapes, text, colors, and connections.
"""

import json
import tempfile
import os
import logging
import re
import xml.etree.ElementTree as ET
import base64
import zlib
import urllib.parse

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_drawio_content(file_path):
    """
    Parses a .drawio file which might be plain XML or compressed/URI-encoded.
    Returns list of all mxCell elements.
    """
    if not os.path.exists(file_path):
        return []

    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        cells = []

        # Iterate through all diagrams in the file
        for diagram in root.findall('diagram'):
            # Check if content is compressed (text node) or plain XML (sub-elements)
            if diagram.text and diagram.text.strip():
                # Compressed content: Base64 -> Inflate -> URI Decode
                try:
                    b64_data = base64.b64decode(diagram.text.strip())
                    # Drop header if present? Python's zlib usually needs raw deflate for draw.io
                    # draw.io uses raw deflate (no zlib header), -15 window bits
                    xml_str = zlib.decompress(b64_data, -15).decode('utf-8')
                    xml_str = urllib.parse.unquote(xml_str)
                    
                    diagram_tree = ET.fromstring(xml_str)
                    cells.extend(diagram_tree.findall('.//mxCell'))
                except Exception as e:
                    logger.warning(f"Failed to decompress diagram content: {e}")
            else:
                # Uncompressed XML
                cells.extend(diagram.findall('.//mxCell'))
                
        # Also check if root is mxGraphModel directly (plain xml save)
        if root.tag == 'mxGraphModel':
            cells.extend(root.findall('.//mxCell'))
            
        return cells
    except Exception as e:
        logger.error(f"Error parsing drawio file: {e}")
        return []

def extract_text(cell):
    """Extracts text value from a cell, handling HTML tags."""
    val = cell.get('value', '')
    if not val:
        return ""
    # Simple regex to strip HTML tags
    clean = re.sub(r'<[^>]+>', ' ', val)
    return clean.lower()

def verify_customer_journey_return_map(traj, env_info, task_info):
    """
    Verify completion of the customer journey map.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Get basic result info
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Get the draw.io file for deep inspection
    temp_drawio = tempfile.NamedTemporaryFile(delete=False, suffix='.drawio')
    drawio_path = result.get('diagram_path', '/home/ga/Diagrams/return_journey.drawio')
    
    try:
        copy_from_env(drawio_path, temp_drawio.name)
        cells = parse_drawio_content(temp_drawio.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse diagram file: {e}"}
    finally:
        if os.path.exists(temp_drawio.name):
            os.unlink(temp_drawio.name)

    # Initialize scoring
    score = 0
    feedback = []
    
    # CRITERION 1: File Modified (5 pts)
    if result.get('file_modified', False):
        score += 5
        feedback.append("File modified successfully.")
    else:
        feedback.append("File was NOT modified (save failed?).")

    # CRITERION 2: Content Quantity (15 pts)
    # Start file has ~12 shapes. Full grid is 5x5=25 + 12 = 37.
    # We count cells that are vertices and have values.
    content_cells = [c for c in cells if c.get('vertex') == '1' and c.get('value')]
    cell_count = len(content_cells)
    
    if cell_count >= 35:
        score += 15
        feedback.append(f"Content quantity sufficient ({cell_count} shapes).")
    elif cell_count >= 25:
        score += 10
        feedback.append(f"Content quantity partial ({cell_count} shapes).")
    elif cell_count >= 15:
        score += 5
        feedback.append(f"Content quantity low ({cell_count} shapes).")
    else:
        feedback.append(f"Minimal content added ({cell_count} shapes).")

    # CRITERION 3: Content Quality (40 pts - 8 per stage)
    # Check for keywords from metadata for each stage
    all_text = " ".join([extract_text(c) for c in content_cells])
    
    stages_found = 0
    key_phrases = metadata.get('key_phrases', {})
    
    for stage, phrases in key_phrases.items():
        # Count how many phrases for this stage appear in the document
        hits = sum(1 for p in phrases if p.lower() in all_text)
        if hits >= 2: # At least 2 key phrases found for the stage
            score += 8
            stages_found += 1
            # feedback.append(f"Stage {stage} content found.")
        elif hits == 1:
            score += 4
    
    if stages_found == 5:
        feedback.append("All 5 journey stages populated with correct content.")
    else:
        feedback.append(f"Only {stages_found}/5 stages fully populated.")

    # CRITERION 4: Color Coding (15 pts)
    # Look for the specific hex codes in 'style' attributes
    colors = metadata.get('colors', {})
    style_text = " ".join([c.get('style', '').lower() for c in content_cells])
    
    green_found = colors['positive'].lower() in style_text
    yellow_found = colors['neutral'].lower() in style_text
    red_found = colors['negative'].lower() in style_text
    
    color_score = 0
    if green_found: color_score += 5
    if yellow_found: color_score += 5
    if red_found: color_score += 5
    
    score += color_score
    feedback.append(f"Color coding: Green={green_found}, Yellow={yellow_found}, Red={red_found}.")

    # CRITERION 5: Connections (15 pts)
    # Count edges
    edges = [c for c in cells if c.get('edge') == '1']
    edge_count = len(edges)
    
    if edge_count >= 5:
        score += 15
        feedback.append(f"Connections sufficient ({edge_count} arrows).")
    elif edge_count >= 3:
        score += 8
        feedback.append(f"Connections partial ({edge_count} arrows).")
    elif edge_count > 0:
        score += 4
        feedback.append(f"Connections minimal ({edge_count} arrows).")
    else:
        feedback.append("No connections/arrows found.")

    # CRITERION 6: Export (10 pts)
    if result.get('export_exists') and result.get('export_size', 0) > 1000:
        score += 10
        feedback.append("PNG export found and valid.")
    else:
        feedback.append("PNG export missing or empty.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }