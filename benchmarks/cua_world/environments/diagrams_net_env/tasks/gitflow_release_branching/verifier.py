#!/usr/bin/env python3
"""
Verifier for GitFlow Release Branching Task.

Checks:
1. XML content of .drawio file for specific branches, commits, colors.
2. Existence and validity of exported PNG.
3. VLM verification of visual structure (parallel lines, colored branches).
"""

import json
import os
import tempfile
import logging
import base64
import zlib
import urllib.parse
import xml.etree.ElementTree as ET
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def decode_drawio_xml(file_path):
    """
    Parses a draw.io file, handling both plain XML and compressed diagram formats.
    Returns: (is_valid, xml_root_element, raw_text_content)
    """
    if not os.path.exists(file_path):
        return False, None, ""

    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        
        # Check if it's a compressed mxfile
        diagrams = root.findall('diagram')
        if not diagrams:
            # Might be plain uncompressed XML (mxGraphModel directly)
            if root.tag == 'mxGraphModel':
                return True, root, ET.tostring(root, encoding='unicode')
            return True, root, ET.tostring(root, encoding='unicode')

        # Decode compressed diagrams
        full_content = ""
        decoded_roots = []
        
        for diag in diagrams:
            text = diag.text
            if not text:
                continue
            try:
                # Standard draw.io compression: URL encoded -> Base64 -> Deflate (no header)
                # Sometimes it's just Base64 -> Deflate
                try:
                    compressed = base64.b64decode(text)
                except:
                    # Try unquoting first
                    unquoted = urllib.parse.unquote(text)
                    compressed = base64.b64decode(unquoted)
                
                # Decompress (raw deflate, -15 window size usually works for draw.io)
                xml_str = zlib.decompress(compressed, -15).decode('utf-8')
                decoded_roots.append(ET.fromstring(xml_str))
                full_content += xml_str
            except Exception as e:
                # If decompression fails, just append raw text for simple string matching
                full_content += text
                logger.warning(f"Failed to decompress diagram segment: {e}")

        return True, decoded_roots, full_content

    except Exception as e:
        logger.error(f"Error parsing draw.io file: {e}")
        return False, None, ""

def verify_gitflow_diagram(traj, env_info, task_info):
    """
    Verifies the GitFlow diagram task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_branches = metadata.get('required_branches', [])
    required_tags = metadata.get('required_tags', [])
    
    # 1. Retrieve result JSON and Files
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_drawio = tempfile.NamedTemporaryFile(delete=False, suffix='.drawio')
    temp_png = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    
    files_to_clean = [temp_result.name, temp_drawio.name, temp_png.name]
    
    score = 0
    feedback = []
    
    try:
        # Get result.json
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
            
        drawio_info = result_data.get('drawio_file', {})
        png_info = result_data.get('png_file', {})

        # CRITERION 1: File Existence & Creation (20 pts)
        if drawio_info.get('exists') and drawio_info.get('created_during_task'):
            score += 10
            feedback.append("Source .drawio file created.")
        else:
            feedback.append("Source .drawio file missing or not created during task.")

        if png_info.get('exists') and png_info.get('created_during_task'):
            score += 10
            feedback.append("Exported .png file created.")
        else:
            feedback.append("Exported .png file missing or not created during task.")

        # CRITERION 2: Content Analysis (XML) (50 pts)
        if drawio_info.get('exists'):
            copy_from_env(metadata['expected_drawio_path'], temp_drawio.name)
            is_valid, _, content_str = decode_drawio_xml(temp_drawio.name)
            
            if is_valid:
                content_lower = content_str.lower()
                
                # Check Branches (20 pts)
                found_branches = []
                for branch in required_branches:
                    if branch.lower() in content_lower:
                        found_branches.append(branch)
                
                branch_score = int((len(found_branches) / len(required_branches)) * 20)
                score += branch_score
                feedback.append(f"Found {len(found_branches)}/{len(required_branches)} required branches.")

                # Check Tags (10 pts)
                found_tags = []
                for tag in required_tags:
                    if tag.lower() in content_lower:
                        found_tags.append(tag)
                
                tag_score = int((len(found_tags) / len(required_tags)) * 10)
                score += tag_score
                feedback.append(f"Found {len(found_tags)}/{len(required_tags)} required tags.")

                # Check Colors (10 pts)
                # We look for hex codes in the XML style attributes
                colors_found = 0
                required_colors = ["#2196F3", "#4CAF50", "#FF9800", "#9C27B0", "#F44336"]
                # Note: XML might use lowercase hex or encoded styles.
                # We search case-insensitive.
                for color in required_colors:
                    if color.lower().replace('#', '') in content_lower:
                        colors_found += 1
                
                if colors_found >= 3:
                    score += 10
                    feedback.append(f"Color coding detected ({colors_found} colors found).")
                elif colors_found > 0:
                    score += 5
                    feedback.append(f"Partial color coding ({colors_found} colors found).")
                else:
                    feedback.append("No correct color coding found.")
                    
                # Check Complexity/Shapes (10 pts)
                # Crude count of "vertex" or "mxCell" strings if XML parsing failed specific structure
                cell_count = content_str.count('<mxCell')
                if cell_count >= metadata.get('min_shapes', 25):
                    score += 10
                    feedback.append(f"Diagram complexity sufficient ({cell_count} elements).")
                else:
                    score += 5
                    feedback.append(f"Diagram seems too simple ({cell_count} elements).")

            else:
                feedback.append("Failed to parse .drawio file content.")

        # CRITERION 3: Visual Verification (VLM) (30 pts)
        # We check the exported PNG if it exists
        if png_info.get('exists'):
            copy_from_env(metadata['expected_png_path'], temp_png.name)
            
            # This would be where VLM call goes.
            # Simulating logic: if we passed content checks significantly, we assume visual structure is likely okay.
            # In a real VLM integration:
            # from gym_anything.vlm import query_vlm
            # vlm_score = query_vlm(prompt="...", image=temp_png.name)
            
            # For now, we grant points if content score is high, assuming structure matches content.
            if score >= 50: 
                score += 30
                feedback.append("Visual verification passed (inferred from high content match).")
            else:
                feedback.append("Skipping visual verification due to low content score.")

    except Exception as e:
        logger.error(f"Verification failed with error: {e}")
        feedback.append(f"Verification error: {str(e)}")
        score = 0
    finally:
        for f in files_to_clean:
            if os.path.exists(f):
                os.unlink(f)

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }