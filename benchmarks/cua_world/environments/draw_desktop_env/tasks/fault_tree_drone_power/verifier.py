#!/usr/bin/env python3
"""
Verifier for fault_tree_drone_power task.

Verification Logic:
1. File Existence: Checks for .drawio and .png files created during task.
2. XML Structural Analysis:
   - Decompresses draw.io XML (often base64/deflate).
   - Counts Logic Gates: Needs at least 1 AND gate (for redundancy) and 2 OR gates (for failures).
   - Counts Basic Events: Needs leaf nodes (circles) for root causes.
   - Heuristic: "AND" gate implies the agent understood the redundancy requirement.
3. VLM Verification (Backup):
   - Visually confirms the diagram looks like a tree structure.
"""

import json
import tempfile
import os
import zlib
import base64
import xml.etree.ElementTree as ET
from urllib.parse import unquote
import logging

# Import VLM utils if available in the environment
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def decompress_diagram(content):
    """Decompress draw.io XML content which can be plain, URL-encoded, or Deflate+Base64."""
    content = content.strip()
    
    # Case 1: Plain XML
    if content.startswith('<') and content.endswith('>'):
        try:
            return ET.fromstring(content)
        except ET.ParseError:
            pass

    # Case 2: URL Encoded
    try:
        decoded = unquote(content)
        if decoded.startswith('<'):
            return ET.fromstring(decoded)
    except:
        pass

    # Case 3: Deflate + Base64 (Standard draw.io format)
    try:
        # draw.io often wraps the payload in <mxfile><diagram>PAYLOAD</diagram></mxfile>
        # If we passed the raw file content, we might need to extract the payload first
        if '<mxfile' in content:
            root = ET.fromstring(content)
            diagram_node = root.find('.//diagram')
            if diagram_node is not None and diagram_node.text:
                payload = diagram_node.text
                decoded_b64 = base64.b64decode(payload)
                # -15 tells zlib to ignore header
                xml_str = zlib.decompress(decoded_b64, -15).decode('utf-8')
                # The result is typically URL encoded XML
                xml_str = unquote(xml_str)
                return ET.fromstring(xml_str)
    except Exception as e:
        logger.warning(f"Decompression failed: {e}")

    return None

def parse_fault_tree_xml(xml_content):
    """
    Parse the XML to count gates and events.
    Returns a dict of counts.
    """
    root = decompress_diagram(xml_content)
    if root is None:
        # Try parsing directly if it was just a raw mxGraphModel
        try:
            root = ET.fromstring(xml_content)
        except:
            return None

    stats = {
        "or_gates": 0,
        "and_gates": 0,
        "basic_events": 0,
        "blocks": 0
    }

    # Iterate over all cells
    for cell in root.iter('mxCell'):
        style = (cell.get('style') or "").lower()
        val = (cell.get('value') or "").lower()
        
        # Check for Logic Gates via style or shape name
        # draw.io styles: 'shape=mxgraph.logic.or', 'verticalLabelPosition=...;shape=or', etc.
        if 'shape=mxgraph.logic.or' in style or 'shape=or' in style:
            stats["or_gates"] += 1
        elif 'shape=mxgraph.logic.and' in style or 'shape=and' in style:
            stats["and_gates"] += 1
        
        # Fallback: Check text label if shape is generic
        # e.g., A rectangle with text "AND"
        elif 'vertex=1' in cell.attrib:
            if 'and' == val.strip():
                stats["and_gates"] += 1
            elif 'or' == val.strip():
                stats["or_gates"] += 1
        
        # Check for Basic Events (Circles)
        # Style often contains 'ellipse' or 'shape=mxgraph.flowchart.start_1'
        if 'ellipse' in style or 'shape=circle' in style:
            stats["basic_events"] += 1
        
        if cell.get('vertex') == '1':
            stats["blocks"] += 1

    return stats

def verify_fault_tree_drone_power(traj, env_info, task_info):
    """
    Main verification entry point.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Get JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            res_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # 2. Check File Existence & Timestamp (20 pts)
    if res_data.get('drawio_exists') and res_data.get('file_modified'):
        score += 15
        feedback.append("Draw.io file saved and modified.")
    elif res_data.get('drawio_exists'):
        score += 5
        feedback.append("Draw.io file exists but timestamp check inconclusive.")
    else:
        feedback.append("Draw.io file not found.")

    if res_data.get('png_exists'):
        score += 5
        feedback.append("PNG export found.")

    # 3. Analyze XML Content (50 pts)
    drawio_path = res_data.get('drawio_path')
    xml_stats = None
    
    if drawio_path and res_data.get('drawio_exists'):
        temp_drawio = tempfile.NamedTemporaryFile(delete=False, suffix='.drawio')
        try:
            copy_from_env(drawio_path, temp_drawio.name)
            with open(temp_drawio.name, 'r') as f:
                content = f.read()
                xml_stats = parse_fault_tree_xml(content)
        except Exception as e:
            feedback.append(f"Failed to parse diagram XML: {e}")
        finally:
            if os.path.exists(temp_drawio.name):
                os.unlink(temp_drawio.name)

    if xml_stats:
        # Check AND Gate (Critical for redundancy logic)
        if xml_stats['and_gates'] >= 1:
            score += 20
            feedback.append(f"Success: Found {xml_stats['and_gates']} AND gate(s) (Redundancy Logic).")
        else:
            feedback.append("Failure: No AND gates found. Redundant batteries require AND logic (both must fail).")

        # Check OR Gates (Critical for single points of failure)
        if xml_stats['or_gates'] >= 2:
            score += 20
            feedback.append(f"Success: Found {xml_stats['or_gates']} OR gate(s) (Failure Logic).")
        elif xml_stats['or_gates'] == 1:
            score += 10
            feedback.append("Found 1 OR gate (Partial credit).")
        else:
            feedback.append("Failure: No OR gates found.")

        # Check Basic Events
        if xml_stats['basic_events'] >= 3:
            score += 10
            feedback.append(f"Found {xml_stats['basic_events']} Basic Events (circles).")
        elif xml_stats['blocks'] >= 5:
            # Fallback if they didn't use circles but have enough blocks
            score += 5
            feedback.append("Found sufficient blocks, but basic events should be circles.")
    else:
        feedback.append("Could not analyze diagram structure.")

    # 4. VLM Verification (30 pts)
    # Visual check to ensure it looks like a tree and isn't just random shapes
    if VLM_AVAILABLE:
        try:
            final_ss = get_final_screenshot(traj)
            if final_ss:
                prompt = (
                    "Verify if this image shows a Fault Tree Analysis diagram. "
                    "It should have a hierarchical tree structure with a top event box, "
                    "logic gates (AND/OR symbols), and circular basic events at the bottom. "
                    "Does it look like a valid Fault Tree?"
                )
                vlm_res = query_vlm(images=[final_ss], prompt=prompt)
                
                if "yes" in vlm_res.lower() or "valid" in vlm_res.lower():
                    score += 30
                    feedback.append("VLM: Diagram visually confirmed as Fault Tree.")
                else:
                    feedback.append(f"VLM: Diagram visual check failed: {vlm_res[:50]}...")
            else:
                feedback.append("VLM: No screenshot available.")
        except Exception as e:
            logger.warning(f"VLM error: {e}")
            # Graceful degradation if VLM fails - normalize score
            if score > 0:
                score = int(score * (100/70)) # Scale up remaining points
                feedback.append("VLM skipped (error), score normalized.")

    return {
        "passed": score >= 60,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }