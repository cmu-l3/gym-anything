#!/usr/bin/env python3
"""
Verifier for devops_cicd_pipeline_viz task.

Checks:
1. .drawio file exists and was modified/created during task.
2. PNG export exists.
3. Content analysis of .drawio XML:
   - Identifies specific tools (Maven, SonarQube, Docker, Kubernetes, Slack) from text labels.
   - Identifies structural logic (Parallel tests, Conditional branching).
"""

import json
import tempfile
import os
import logging
import base64
import zlib
import urllib.parse
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def decode_drawio_content(encoded_text):
    """
    Decode draw.io compressed diagram content.
    Format is typically: URL encoded -> Base64 encoded -> Deflate compressed (raw, no header)
    """
    try:
        # 1. URL Decode
        url_decoded = urllib.parse.unquote(encoded_text.strip())
        # 2. Base64 Decode
        data = base64.b64decode(url_decoded)
        # 3. Deflate Decompress (wbits=-15 for raw deflate)
        xml_str = zlib.decompress(data, -15).decode('utf-8')
        return xml_str
    except Exception as e:
        logger.warning(f"Failed to decode drawio content: {e}")
        return None

def extract_text_from_drawio(file_path):
    """
    Parse .drawio file (XML) and extract all text values from cells.
    Handles both plain XML and compressed diagram nodes.
    """
    all_text = []
    
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        
        # Draw.io files usually have a <diagram> tag
        # If the text inside <diagram> is encrypted/compressed, we need to decode it
        for diagram in root.findall('diagram'):
            if diagram.text and diagram.text.strip():
                # Try to decode
                decoded_xml = decode_drawio_content(diagram.text)
                if decoded_xml:
                    try:
                        # Parse the inner XML
                        inner_root = ET.fromstring(decoded_xml)
                        # Extract value attributes from mxCell
                        for cell in inner_root.findall(".//mxCell"):
                            val = cell.get('value', '')
                            if val:
                                all_text.append(val.lower())
                    except Exception:
                        pass
                else:
                    # Maybe it's not compressed?
                    pass
            
            # Sometimes data is in child nodes if not compressed (less common in .drawio default save)
            for cell in diagram.findall(".//mxCell"):
                 val = cell.get('value', '')
                 if val:
                     all_text.append(val.lower())

        # Also check if it's an uncompressed file format directly
        if root.tag == 'mxfile':
            pass # handled above by iterating diagrams
        
    except Exception as e:
        logger.error(f"Error parsing drawio XML: {e}")
        return []
        
    return all_text

def verify_devops_cicd_pipeline_viz(traj, env_info, task_info):
    """
    Verifies the CI/CD pipeline diagram task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Get JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # 2. Check File Existence
    drawio_exists = result.get('drawio_exists', False)
    png_exists = result.get('png_exists', False)
    
    if drawio_exists and result.get('drawio_created_during_task', False):
        score += 10
        feedback.append("Diagram file created (+10)")
    elif drawio_exists:
        score += 5
        feedback.append("Diagram file exists but old timestamp (+5)")
    else:
        feedback.append("Diagram file missing (0)")
        return {"passed": False, "score": 0, "feedback": "Diagram file not found"}

    if png_exists and result.get('png_created_during_task', False):
        score += 10
        feedback.append("PNG export created (+10)")
    elif png_exists:
        score += 5
        feedback.append("PNG export exists but old timestamp (+5)")
    else:
        feedback.append("PNG export missing (0)")

    # 3. Analyze Content
    # We need to copy the actual .drawio file to parse it
    temp_drawio = tempfile.NamedTemporaryFile(delete=False, suffix='.drawio')
    try:
        copy_from_env(result['drawio_path'], temp_drawio.name)
        # Extract all text
        text_content = extract_text_from_drawio(temp_drawio.name)
        full_text_blob = " ".join(text_content)
        
        logger.info(f"Extracted text from diagram: {full_text_blob}")

        # Check for Tools (Domain Mapping)
        # Maven
        if any(x in full_text_blob for x in ['mvn', 'maven']):
            score += 10
            feedback.append("Tool: Maven identified (+10)")
        else:
            feedback.append("Missing 'Maven' tool label")

        # SonarQube
        if any(x in full_text_blob for x in ['sonar', 'sonarqube']):
            score += 10
            feedback.append("Tool: SonarQube identified (+10)")
        else:
            feedback.append("Missing 'SonarQube' tool label")

        # Docker
        if 'docker' in full_text_blob:
            score += 10
            feedback.append("Tool: Docker identified (+10)")
        else:
            feedback.append("Missing 'Docker' tool label")

        # Kubernetes
        if any(x in full_text_blob for x in ['kube', 'k8s']):
            score += 10
            feedback.append("Tool: Kubernetes identified (+10)")
        else:
            feedback.append("Missing 'Kubernetes' tool label")
            
        # Slack (Failure Handler)
        if 'slack' in full_text_blob:
            score += 10
            feedback.append("Tool: Slack identified (+10)")
        else:
            feedback.append("Missing 'Slack' failure handler")

        # Check for Logic Structure Labels
        # Parallel Testing
        has_unit = 'unit' in full_text_blob
        has_integration = 'integration' in full_text_blob
        if has_unit and has_integration:
            score += 15
            feedback.append("Logic: Parallel testing stages labeled (+15)")
        elif has_unit or has_integration:
            score += 7
            feedback.append("Logic: Partial testing stages (+7)")
        else:
            feedback.append("Missing specific test stages (Unit/Integration)")

        # Conditional Deployment
        if any(x in full_text_blob for x in ['main', 'branch', 'condition']):
            score += 15
            feedback.append("Logic: Conditional deployment labeled (+15)")
        else:
            feedback.append("Missing conditional logic label (e.g. 'Main Branch')")

    except Exception as e:
        feedback.append(f"Error analyzing diagram content: {e}")
    finally:
        if os.path.exists(temp_drawio.name):
            os.unlink(temp_drawio.name)

    # Calculate final result
    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }