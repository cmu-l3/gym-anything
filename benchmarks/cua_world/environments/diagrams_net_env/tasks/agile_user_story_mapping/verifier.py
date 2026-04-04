#!/usr/bin/env python3
"""
Verifier for Agile User Story Mapping task.
Verifies the existence of specific text labels and their spatial relationships
(User Activities in columns, Releases in rows).
"""

import json
import os
import sys
import xml.etree.ElementTree as ET
import urllib.parse
import base64
import zlib
import logging
from typing import Dict, Any, List, Optional

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_agile_user_story_mapping(traj, env_info, task_info):
    """
    Verifies the User Story Map.
    
    Scoring Criteria:
    1. Files exist and modified (10 pts)
    2. Content Coverage: Keywords from requirements present (20 pts)
    3. Spatial Structure - Columns: Features aligned horizontally with Activities (35 pts)
    4. Spatial Structure - Rows: MVP features above Future features (35 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load Metadata
    metadata = task_info.get('metadata', {})
    features_map = metadata.get('features_map', {})
    
    # Copy result JSON
    try:
        import tempfile
        tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_json.close()
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name) as f:
            result_data = json.load(f)
        os.unlink(tmp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}

    score = 0
    feedback = []

    # 1. File Check (10 pts)
    drawio_stats = result_data.get("drawio_file", {})
    png_stats = result_data.get("png_file", {})
    
    if drawio_stats.get("exists") and drawio_stats.get("modified"):
        score += 5
        feedback.append("Draw.io file created and modified.")
    else:
        feedback.append("Draw.io file missing or not modified.")

    if png_stats.get("exists") and png_stats.get("modified"):
        score += 5
        feedback.append("PNG export created.")
    else:
        feedback.append("PNG export missing.")

    if not drawio_stats.get("exists"):
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    # 2. Parse Diagram Content
    try:
        tmp_drawio = tempfile.NamedTemporaryFile(delete=False, suffix=".drawio")
        tmp_drawio.close()
        # The export script copies the drawio file to /tmp/submission.drawio
        submission_path = result_data.get("submission_path", "/tmp/submission.drawio")
        copy_from_env(submission_path, tmp_drawio.name)
        
        cells = parse_drawio(tmp_drawio.name)
        os.unlink(tmp_drawio.name)
        
        if not cells:
            return {"passed": False, "score": score, "feedback": "Could not parse diagram content (empty or invalid format)."}
            
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Error parsing diagram: {str(e)}"}

    # 3. Content Coverage (20 pts)
    # Check for presence of Activity headers and Feature cards
    found_cells = {} # Map text -> cell_data
    
    # Flatten expected features for search
    all_expected_texts = list(features_map.keys()) # Activities
    for f_list in features_map.values():
        all_expected_texts.extend(f_list) # Features
    
    normalized_cells = {} # normalized_text -> cell
    for c in cells:
        txt = normalize_text(c['text'])
        if txt:
            normalized_cells[txt] = c

    found_count = 0
    total_expected = len(all_expected_texts)
    
    for expected in all_expected_texts:
        norm = normalize_text(expected)
        # partial match check
        match = None
        for cell_txt, cell_data in normalized_cells.items():
            if norm in cell_txt:
                match = cell_data
                break
        
        if match:
            found_count += 1
            found_cells[expected] = match
    
    coverage_score = min(20, int((found_count / total_expected) * 20))
    score += coverage_score
    feedback.append(f"Content Coverage: Found {found_count}/{total_expected} items ({coverage_score}/20 pts).")

    # 4. Spatial Verification - Column Alignment (35 pts)
    # Features should be roughly in the same X-column as their Activity Header
    # We define "same column" as being closer to that header's X than any other header's X
    
    # Identify Activity Headers in the diagram
    activity_headers = {}
    for act in features_map.keys():
        if act in found_cells:
            activity_headers[act] = found_cells[act]
    
    if len(activity_headers) < 2:
        feedback.append("Cannot verify column alignment: Fewer than 2 activity headers found.")
    else:
        aligned_count = 0
        total_features_checked = 0
        
        for activity, features in features_map.items():
            if activity not in activity_headers:
                continue
            
            header = activity_headers[activity]
            header_x = header['x'] + (header['width'] / 2) # Center X
            
            for feat in features:
                if feat in found_cells:
                    total_features_checked += 1
                    feat_cell = found_cells[feat]
                    feat_x = feat_cell['x'] + (feat_cell['width'] / 2)
                    
                    # Find closest header
                    closest_act = None
                    min_dist = float('inf')
                    
                    for other_act, other_header in activity_headers.items():
                        other_x = other_header['x'] + (other_header['width'] / 2)
                        dist = abs(feat_x - other_x)
                        if dist < min_dist:
                            min_dist = dist
                            closest_act = other_act
                    
                    if closest_act == activity:
                        aligned_count += 1
        
        if total_features_checked > 0:
            align_score = int((aligned_count / total_features_checked) * 35)
            score += align_score
            feedback.append(f"Column Alignment: {aligned_count}/{total_features_checked} features aligned with correct activity ({align_score}/35 pts).")
        else:
            feedback.append("Column Alignment: No features found to check.")


    # 5. Spatial Verification - Row Ordering (35 pts)
    # MVP features (Release 1) should be Higher (lower Y value) than Future features (Release 3)
    # We compare Y values of found MVP items vs Future items.
    
    mvp_features = features_map["Onboarding"][:2] + features_map["Device Control"][:2] # Heuristic sample
    future_features = ["Music Sync", "Geofencing", "Energy Usage Reports"] # From requirements
    
    mvp_y_values = []
    future_y_values = []
    
    # Gather Y centroids
    for name, cell in found_cells.items():
        # Check if it matches any MVP keyword
        if any(m in name for m in mvp_features):
            mvp_y_values.append(cell['y'])
        # Check if it matches any Future keyword
        if any(f in name for f in future_features):
            future_y_values.append(cell['y'])
            
    if mvp_y_values and future_y_values:
        avg_mvp_y = sum(mvp_y_values) / len(mvp_y_values)
        avg_future_y = sum(future_y_values) / len(future_y_values)
        
        # In screen coords, Lower Y is Higher up. MVP should be above Future.
        if avg_mvp_y < avg_future_y:
            score += 35
            feedback.append("Row Ordering: MVP features are positioned above Future features (35/35 pts).")
        else:
            feedback.append(f"Row Ordering Failed: MVP avg Y ({avg_mvp_y}) is below Future avg Y ({avg_future_y}).")
    else:
        feedback.append("Row Ordering: Could not find enough MVP/Future items to compare.")

    return {
        "passed": score >= 65,
        "score": score,
        "feedback": "\n".join(feedback)
    }

# --- Helpers ---

def normalize_text(text):
    if not text: return ""
    # Remove HTML tags if present (drawio often wraps text in div/span)
    if "<" in text and ">" in text:
        try:
            return "".join(ET.fromstring(f"<root>{text}</root>").itertext()).lower().strip()
        except:
            pass # Fallback to raw string cleanup
    return text.lower().replace("&nbsp;", " ").strip()

def decode_drawio_content(raw_text):
    """
    Decodes the diagram data from a .drawio file.
    Draw.io XML is often compressed (deflate) and base64 encoded inside the <diagram> tag.
    """
    try:
        # It's URL encoded -> Base64 -> Deflate (raw, no header)
        decoded_url = urllib.parse.unquote(raw_text)
        decoded_b64 = base64.b64decode(decoded_url)
        # -15 for raw deflate (no zlib header)
        decoded_xml = zlib.decompress(decoded_b64, -15).decode('utf-8')
        return decoded_xml
    except Exception as e:
        logger.warning(f"Failed to decompress diagram text: {e}")
        return raw_text # Return raw if decompression fails (might be plain XML)

def parse_drawio(file_path: str) -> List[Dict[str, Any]]:
    """
    Parses a .drawio file and returns a list of cell objects with text and geometry.
    """
    cells = []
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        
        # <mxfile> -> <diagram> -> (compressed text)
        diagram_nodes = root.findall("diagram")
        
        xml_content = None
        if diagram_nodes:
            # Take the first page
            text_content = diagram_nodes[0].text
            if text_content:
                xml_content = decode_drawio_content(text_content)
        
        if not xml_content:
            # Fallback: maybe it's uncompressed XML already
            xml_content = ET.tostring(root, encoding='utf8').decode('utf8')

        # Parse the inner MXGraphModel
        # Wrap in fake root to ensure valid XML if just a fragment
        if not xml_content.strip().startswith("<"):
             # If decoding failed completely
             return []
             
        # Often the decompressed content is <mxGraphModel>...</mxGraphModel>
        inner_root = ET.fromstring(xml_content)
        
        # Find all mxCell elements
        # They can be nested or flat. .iter() finds them all.
        for cell in inner_root.iter("mxCell"):
            value = cell.get("value", "")
            style = cell.get("style", "")
            geometry = cell.find("mxGeometry")
            
            if geometry is not None:
                x = float(geometry.get("x", 0))
                y = float(geometry.get("y", 0))
                width = float(geometry.get("width", 0))
                height = float(geometry.get("height", 0))
                
                # Filter out pure edges (usually have source/target but maybe no value)
                # We want shapes with text.
                if value.strip():
                     cells.append({
                         "text": value,
                         "x": x,
                         "y": y,
                         "width": width,
                         "height": height,
                         "style": style
                     })
                     
    except Exception as e:
        logger.error(f"XML Parsing Error: {e}")
        
    return cells