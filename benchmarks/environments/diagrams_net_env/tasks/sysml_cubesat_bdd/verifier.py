#!/usr/bin/env python3
"""
Verifier for SysML CubeSat BDD Task.
Checks for correct file creation, SysML specific shapes/labels, and diagram structure.
"""

import json
import os
import tempfile
import zlib
import base64
import urllib.parse
import xml.etree.ElementTree as ET
import logging
import sys

# Add VLM support if available in the environment
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def decode_drawio_xml(raw_xml_data):
    """
    Decodes draw.io XML which might be compressed and base64 encoded.
    Draw.io files often look like: <mxfile><diagram>BASE64...</diagram></mxfile>
    """
    try:
        # Parse the outer XML
        tree = ET.ElementTree(ET.fromstring(raw_xml_data))
        root = tree.getroot()
        
        # Look for diagram node
        diagram_node = root.find('diagram')
        if diagram_node is None:
            # Maybe it's uncompressed XML already?
            return raw_xml_data
            
        # Get content
        content = diagram_node.text
        if not content:
            return raw_xml_data
            
        # Decode
        # 1. Base64 decode
        compressed_data = base64.b64decode(content)
        # 2. Inflate (raw deflate)
        # Check if it has header, usually -15 for raw deflate
        try:
            xml_content = zlib.decompress(compressed_data, -15).decode('utf-8')
            # URL decode the result
            xml_content = urllib.parse.unquote(xml_content)
            return xml_content
        except Exception:
            # sometimes simple inflate
            return zlib.decompress(compressed_data).decode('utf-8')
            
    except Exception as e:
        logger.warning(f"Failed to decode compressed draw.io XML: {e}")
        # Return original, maybe it wasn't compressed
        return raw_xml_data

def analyze_diagram_content(xml_content):
    """
    Analyzes the XML content for specific shapes, labels, and styles.
    """
    stats = {
        "block_count": 0,
        "diamond_connectors": 0,
        "labels_found": [],
        "sysml_styles": False
    }
    
    try:
        # Wrap if strictly fragment
        if not xml_content.strip().startswith('<'):
             # If decoding failed, we might have partial strings, skip XML parse
             pass
        else:
            root = ET.fromstring(xml_content)
            
            # Find all cells
            for cell in root.findall(".//mxCell"):
                value = cell.get('value', '').lower()
                style = cell.get('style', '').lower()
                
                # Check labels
                if value:
                    stats["labels_found"].append(value)
                
                # Check for SysML/Block styles
                # Draw.io SysML blocks often use 'swimlane' or explicit style names if library loaded
                # or just 'whiteSpace=wrap;html=1;' for generic rectangles. 
                # We rely heavily on labels for block identification.
                if 'sysml' in style or 'block' in style:
                    stats["sysml_styles"] = True
                
                # Check for Diamond connectors (Composition)
                # Style usually contains 'endArrow=diamond' or 'startArrow=diamond' or 'diamondThin'
                if 'arrow=diamond' in style or 'arrow=diamondthin' in style:
                    stats["diamond_connectors"] += 1
                    
                # Count general blocks (vertices)
                if cell.get('vertex') == '1':
                    stats["block_count"] += 1

    except Exception as e:
        logger.warning(f"XML parsing error: {e}")
        # Fallback: simple string matching
        lower_content = xml_content.lower()
        stats["diamond_connectors"] = lower_content.count("arrow=diamond")
        stats["sysml_styles"] = "sysml" in lower_content
    
    return stats

def verify_sysml_cubesat_bdd(traj, env_info, task_info):
    """
    Verifies the SysML CubeSat BDD task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_blocks = [b.lower() for b in metadata.get('required_blocks', [])]
    
    # 1. Read Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Analyze Drawio File
    drawio_content = ""
    if result_data.get("drawio_exists"):
        temp_drawio = tempfile.NamedTemporaryFile(delete=False, suffix='.drawio')
        try:
            copy_from_env(result_data["drawio_path"], temp_drawio.name)
            with open(temp_drawio.name, 'rb') as f:
                raw_data = f.read().decode('utf-8', errors='ignore')
                drawio_content = decode_drawio_xml(raw_data)
        except Exception as e:
            logger.error(f"Failed to read drawio file: {e}")
        finally:
            if os.path.exists(temp_drawio.name):
                os.unlink(temp_drawio.name)
    
    diagram_stats = analyze_diagram_content(drawio_content)
    
    # --- SCORING ---
    score = 0
    feedback_parts = []
    
    # Criterion 1: Files Exist (20 pts)
    if result_data.get("drawio_exists") and result_data.get("drawio_modified"):
        score += 10
        feedback_parts.append("Draw.io file created and modified.")
    elif result_data.get("drawio_exists"):
        score += 5
        feedback_parts.append("Draw.io file exists but not modified (?).")
    
    if result_data.get("pdf_exists"):
        score += 10
        feedback_parts.append("PDF export found.")
    else:
        feedback_parts.append("PDF export missing.")

    # Criterion 2: Content - Blocks (30 pts)
    # Check if required labels exist in the diagram content
    found_labels_str = " ".join(diagram_stats["labels_found"]).lower()
    found_blocks_count = 0
    for rb in required_blocks:
        if rb in found_labels_str:
            found_blocks_count += 1
    
    # Need at least 3 of the 5 main blocks
    if found_blocks_count >= 5:
        score += 30
        feedback_parts.append("All required blocks found.")
    elif found_blocks_count >= 3:
        score += 20
        feedback_parts.append(f"Some required blocks found ({found_blocks_count}/5).")
    else:
        feedback_parts.append(f"Missing key blocks. Found only {found_blocks_count}.")

    # Criterion 3: Composition Diamonds (20 pts)
    # SysML BDD relies on composition.
    if diagram_stats["diamond_connectors"] >= 3:
        score += 20
        feedback_parts.append("Composition relationships (diamonds) detected.")
    elif diagram_stats["diamond_connectors"] > 0:
        score += 10
        feedback_parts.append("Few composition relationships detected.")
    else:
        feedback_parts.append("No composition diamonds detected in XML styles.")

    # Criterion 4: Value Properties (10 pts)
    # Check for text like 'mass', 'kg', 'Wh'
    props_found = 0
    required_props = ['mass', 'kg', 'capacity', 'wh', 'efficiency', 'voltage', 'v']
    for prop in required_props:
        if prop in found_labels_str:
            props_found += 1
            
    if props_found >= 3:
        score += 10
        feedback_parts.append("Value properties (mass/capacity) found.")
    else:
        feedback_parts.append("Value properties missing or sparse.")

    # Criterion 5: VLM Verification (20 pts)
    # Use VLM to confirm the visual structure matches a BDD
    vlm_score = 0
    if VLM_AVAILABLE:
        try:
            final_screenshot = get_final_screenshot(traj)
            # Sample a few frames to see workflow
            frames = sample_trajectory_frames(traj, n=3)
            all_images = frames + [final_screenshot]
            
            prompt = """
            Review these screenshots of a Diagrams.net (draw.io) session.
            The user is creating a SysML Block Definition Diagram (BDD).
            
            Check for:
            1. A hierarchical diagram with rectangular blocks.
            2. Lines connecting blocks, preferably with Diamond heads (composition).
            3. Text inside blocks like "Power Subsystem", "Solar Panel", "Battery".
            4. Does the final diagram look like a structured engineering diagram?
            
            Answer YES or NO for 'Valid BDD Diagram' and provide a confidence score (0-100).
            """
            
            response = query_vlm(prompt, images=all_images)
            
            if response and response.get('success'):
                # Simple keyword parsing of VLM response
                text = response.get('text', '').lower()
                if 'yes' in text and 'valid' in text:
                    vlm_score = 20
                    feedback_parts.append("VLM confirms valid BDD structure.")
                elif 'yes' in text:
                    vlm_score = 15
                    feedback_parts.append("VLM sees a diagram.")
                else:
                    feedback_parts.append("VLM did not recognize a valid BDD.")
            else:
                # Fallback if VLM fails: assume visual structure is okay if XML elements existed
                if diagram_stats["block_count"] >= 5:
                    vlm_score = 10
                    feedback_parts.append("VLM unavailable, using XML block count fallback.")
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            
    score += vlm_score

    # Final Result
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }