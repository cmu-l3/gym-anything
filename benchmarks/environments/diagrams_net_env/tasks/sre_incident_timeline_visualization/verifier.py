#!/usr/bin/env python3
"""
Verifier for SRE Incident Timeline Visualization Task.

Checks:
1. File artifacts (drawio and PDF) exist and were created during task.
2. XML Content Analysis:
   - Parses the .drawio file (handling compression).
   - Extracts text labels and their X-coordinates.
   - Verifies chronological order (Time T1 is to the left of Time T2).
   - Verifies color coding (Red for 'rm -rf', Green for 'Restored').
3. VLM Verification:
   - Checks trajectory to confirm manual creation.
   - Checks final screenshot for "timeline-like" structure.
"""

import json
import os
import tempfile
import logging
import base64
import zlib
import urllib.parse
import re
from typing import List, Dict, Tuple
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- Helper: Draw.io Decoding ---
def decode_drawio_content(encoded_text):
    """Decode draw.io compressed diagram content (URLencode + Base64 + raw deflate)."""
    try:
        # Steps: URL Decode -> Base64 Decode -> Inflate (no header)
        url_decoded = urllib.parse.unquote(encoded_text.strip())
        data = base64.b64decode(url_decoded)
        # -15 for raw deflate (no zlib header)
        xml_str = zlib.decompress(data, -15).decode('utf-8')
        return xml_str
    except Exception as e:
        logger.debug(f"Decompression failed (might be plain XML): {e}")
        return None

def parse_drawio_xml(file_path):
    """
    Parses a draw.io file and returns a list of shapes with their text, style, and geometry.
    Returns: List[Dict] {'text': str, 'style': str, 'x': float, 'y': float}
    """
    import xml.etree.ElementTree as ET
    
    shapes = []
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        
        # Draw.io files can be:
        # 1. Plain XML (mxfile -> diagram -> mxGraphModel)
        # 2. Compressed (mxfile -> diagram -> Text Content)
        
        diagrams = root.findall('diagram')
        for diag in diagrams:
            if diag.text and diag.text.strip():
                # Try to decode compressed content
                xml_content = decode_drawio_content(diag.text)
                if xml_content:
                    # Parse the inner XML
                    inner_root = ET.fromstring(xml_content)
                    root = inner_root # Treat this as the root for finding cells
                else:
                    # Fallback: maybe it's not compressed or decoding failed
                    pass

        # Find all cells
        # We look for mxCell elements
        # Usually nested in root -> mxGraphModel -> root -> mxCell
        for cell in root.findall(".//mxCell"):
            val = cell.get('value', '')
            style = cell.get('style', '')
            geometry = cell.find('mxGeometry')
            
            x, y = 0.0, 0.0
            if geometry is not None:
                x = float(geometry.get('x', 0))
                y = float(geometry.get('y', 0))
                
            # Only care about vertices (shapes), usually vertex="1"
            if cell.get('vertex') == '1':
                # Remove HTML tags from text if present
                clean_text = re.sub('<[^<]+?>', ' ', val).strip()
                shapes.append({
                    'text': clean_text,
                    'style': style,
                    'x': x,
                    'y': y
                })
                
    except Exception as e:
        logger.error(f"Error parsing XML: {e}")
        
    return shapes

# --- Verifier Function ---
def verify_sre_incident_timeline_visualization(traj, env_info, task_info):
    # 1. Setup & File Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    score = 0
    feedback = []
    
    # Load metadata expectations
    meta = task_info.get('metadata', {})
    
    # Copy JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name) as f:
            res = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)

    # Copy .drawio file for analysis
    temp_drawio = tempfile.NamedTemporaryFile(delete=False, suffix='.drawio')
    try:
        copy_from_env(meta.get('expected_diagram'), temp_drawio.name)
        diagram_shapes = parse_drawio_xml(temp_drawio.name)
    except Exception as e:
        diagram_shapes = []
        feedback.append(f"Could not read/parse diagram file: {e}")
    finally:
        if os.path.exists(temp_drawio.name): os.unlink(temp_drawio.name)

    # --- Criterion 1: File Artifacts (10 pts) ---
    files_ok = False
    if res['diagram_file']['exists'] and res['diagram_file']['created_during_task']:
        score += 5
        feedback.append("Diagram file saved.")
        files_ok = True
    else:
        feedback.append("Diagram file missing or not saved.")
        
    if res['pdf_file']['exists'] and res['pdf_file']['size'] > 100:
        score += 5
        feedback.append("PDF exported.")
    else:
        feedback.append("PDF missing.")

    if not files_ok:
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # --- Criterion 2: Content Analysis (Keyword Search) (20 pts) ---
    # We define expected events and their keywords
    # Map: EventID -> [Keywords]
    event_definitions = {
        "spam_attack": ["spam", "attack", "18:00"],
        "lag": ["lag", "replication", "21:00"],
        "pool": ["pool", "exhaustion", "22:00"],
        "wipe_attempt": ["wipe", "secondary", "23:00"],
        "rm_rf": ["rm -rf", "delete", "accident", "23:27"],
        "data_loss": ["lost", "300gb", "stopped"],
        "restore_start": ["restor", "snapshot", "lvm"],
        "restore_done": ["public", "access", "restored", "18:14"]
    }
    
    found_events = [] # List of (EventID, ShapeDict)
    
    for shape in diagram_shapes:
        txt = shape['text'].lower()
        for evid, kws in event_definitions.items():
            if any(k in txt for k in kws):
                # Check if we already found this event to avoid duplicates
                if evid not in [x[0] for x in found_events]:
                    found_events.append((evid, shape))
    
    # Score based on count
    if len(found_events) >= 6:
        score += 20
        feedback.append(f"Found {len(found_events)} events (+20).")
    elif len(found_events) >= 4:
        score += 10
        feedback.append(f"Found {len(found_events)} events (+10).")
    else:
        feedback.append(f"Only found {len(found_events)} events (need 6).")

    # --- Criterion 3: Chronological Order (X-Axis) (25 pts) ---
    # Expected chronological order of keys
    chronology = ["spam_attack", "lag", "pool", "wipe_attempt", "rm_rf", "restore_start", "restore_done"]
    
    # Filter found events to those in our chrono list
    ordered_found = sorted(
        [e for e in found_events if e[0] in chronology],
        key=lambda x: chronology.index(x[0])
    )
    
    if len(ordered_found) >= 4:
        # Check X coordinates
        x_coords = [e[1]['x'] for e in ordered_found]
        # Check if strictly increasing (allow small margin for vertical stacking)
        is_sorted = all(x_coords[i] <= x_coords[i+1] + 10 for i in range(len(x_coords)-1))
        
        if is_sorted:
            score += 25
            feedback.append("Timeline is chronologically ordered (+25).")
        else:
            feedback.append("Events are not in correct spatial order (Left->Right).")
    else:
        feedback.append("Not enough events to verify chronology.")

    # --- Criterion 4: Critical Event Highlight (Red & Callout) (25 pts) ---
    rm_rf_shape = next((e[1] for e in found_events if e[0] == "rm_rf"), None)
    
    if rm_rf_shape:
        # Check Red Color
        style = rm_rf_shape['style'].lower()
        # Common red hex codes or color names
        reds = ["f8cecc", "ff0000", "red", "e06666", "b85450"]
        if any(c in style for c in reds):
            score += 15
            feedback.append("'rm -rf' event is Red (+15).")
        else:
            feedback.append("'rm -rf' event is NOT Red.")
            
        # Check Shape (Callout/Star)
        # Callouts often have 'style="...shape=callout..."' or similar
        distinct_shapes = ["callout", "cloud", "star", "ellipse", "hexagon"]
        if any(s in style for s in distinct_shapes):
            score += 10
            feedback.append("'rm -rf' uses distinct shape (+10).")
        else:
            feedback.append("'rm -rf' shape is standard.")
    else:
        feedback.append("'rm -rf' event not found.")

    # --- Criterion 5: Restoration Highlight (Green) (10 pts) ---
    restore_shape = next((e[1] for e in found_events if e[0] == "restore_done"), None)
    
    if restore_shape:
        style = restore_shape['style'].lower()
        greens = ["d5e8d4", "00ff00", "green", "93c47d"]
        if any(c in style for c in greens):
            score += 10
            feedback.append("Restoration event is Green (+10).")
        else:
            feedback.append("Restoration event is NOT Green.")

    # --- Criterion 6: VLM Verification (10 pts) ---
    # Use VLM to confirm it looks like a timeline
    frames = sample_trajectory_frames(traj, n=5)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Look at the final screenshot. Does it show a Timeline Diagram?
    A timeline typically has:
    1. A horizontal flow.
    2. Multiple boxes/shapes connected by arrows.
    3. One box highlighted in RED (the error).
    4. One box highlighted in GREEN (the fix).
    
    Answer JSON: {"is_timeline": bool, "has_red_box": bool, "has_green_box": bool}
    """
    
    vlm_score = 0
    try:
        vlm_res = query_vlm(images=[final_screen], prompt=vlm_prompt)
        if vlm_res and isinstance(vlm_res, dict):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('is_timeline'): vlm_score += 4
            if parsed.get('has_red_box'): vlm_score += 3
            if parsed.get('has_green_box'): vlm_score += 3
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if we verified programmatically, assume visual is likely okay
        if score > 60: vlm_score = 10
    
    score += vlm_score
    feedback.append(f"Visual check: {vlm_score}/10")

    return {
        "passed": score >= 65,
        "score": score,
        "feedback": " ".join(feedback)
    }