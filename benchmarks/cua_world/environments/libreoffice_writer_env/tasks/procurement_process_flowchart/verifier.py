#!/usr/bin/env python3
"""
Verifier for Procurement Process Flowchart task.

Verifies:
1. ODT file exists and is valid.
2. Contains specific text labels from the source workflow.
3. Uses correct ODF XML tags for Connectors (draw:connector) vs Lines (draw:line).
4. Uses Grouping (draw:g).
5. VLM check for visual layout accuracy.
"""

import json
import os
import zipfile
import tempfile
import logging
import re
from xml.etree import ElementTree as ET

# Import VLM utilities from the environment
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot
except ImportError:
    # Fallback for local testing
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Namespaces for ODT XML parsing
NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
    'svg': 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0'
}

def verify_procurement_flowchart(traj, env_info, task_info):
    """
    Verify the flowchart creation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_text = metadata.get('required_text', [])
    min_connector_count = metadata.get('min_connector_count', 5)
    
    score = 0
    feedback_parts = []
    
    # 1. Check Output File Existence
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.odt')
    try:
        copy_from_env("/home/ga/Documents/procurement_flow.odt", temp_file.name)
    except Exception:
        return {"passed": False, "score": 0, "feedback": "Output file '/home/ga/Documents/procurement_flow.odt' not found."}

    # 2. Parse ODT Content (XML Analysis)
    try:
        with zipfile.ZipFile(temp_file.name, 'r') as z:
            content_xml = z.read('content.xml')
        
        root = ET.fromstring(content_xml)
        
        # --- Check Text Content ---
        # Extract all text from text:p and text:span elements
        all_text = " ".join([elem.text for elem in root.findall('.//text:p', NS) if elem.text] + 
                            [elem.text for elem in root.findall('.//text:span', NS) if elem.text])
        
        text_matches = 0
        missing_terms = []
        for term in required_text:
            # Simple normalization for comparison
            if term.lower() in all_text.lower():
                text_matches += 1
            else:
                missing_terms.append(term)
        
        if text_matches == len(required_text):
            score += 30
            feedback_parts.append("All text labels present.")
        elif text_matches >= len(required_text) / 2:
            score += 15
            feedback_parts.append(f"Some text labels missing: {', '.join(missing_terms[:3])}...")
        else:
            feedback_parts.append("Most required text labels are missing.")

        # --- Check for Connectors ---
        # Look for <draw:connector> elements. 
        # Note: If user drew lines, they would be <draw:line>.
        connectors = root.findall('.//draw:connector', NS)
        lines = root.findall('.//draw:line', NS)
        
        connector_count = len(connectors)
        line_count = len(lines)
        
        if connector_count >= min_connector_count:
            score += 30
            feedback_parts.append(f"Correctly used dynamic connectors ({connector_count} found).")
        elif line_count >= min_connector_count:
            # Partial credit if they drew the diagram but used static lines
            score += 10
            feedback_parts.append(f"Used static lines instead of dynamic connectors ({line_count} lines found).")
        else:
            feedback_parts.append("No connectors or lines found connecting shapes.")

        # --- Check for Shapes ---
        # Custom shapes are typically <draw:custom-shape>
        shapes = root.findall('.//draw:custom-shape', NS)
        # Frames can also hold text boxes or images, sometimes used for shapes
        frames = root.findall('.//draw:frame', NS)
        
        total_shapes = len(shapes) + len(frames)
        if total_shapes >= 6:
            score += 20
            feedback_parts.append(f"Sufficient shapes found ({total_shapes}).")
        else:
            feedback_parts.append(f"Too few shapes found ({total_shapes}).")

        # --- Check for Grouping ---
        # Grouping creates a <draw:g> element
        groups = root.findall('.//draw:g', NS)
        if len(groups) >= 1:
            score += 10
            feedback_parts.append("Objects are grouped.")
        else:
            feedback_parts.append("Final objects were not grouped.")

    except Exception as e:
        logger.error(f"Error parsing ODT: {e}")
        return {"passed": False, "score": 0, "feedback": f"Invalid ODT file format: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. VLM Verification (Visual Check)
    # Only if XML checks pass a basic threshold to avoid wasting VLM tokens on empty files
    if score >= 30:
        final_screenshot = get_final_screenshot(traj)
        if final_screenshot:
            vlm_prompt = """
            Analyze this screenshot of LibreOffice Writer.
            1. Is there a flowchart visible?
            2. Does it contain a Decision diamond shape (rhombus)?
            3. Are there text labels like "Yes" and "No" on the decision branches?
            4. Does the layout look like a connected process flow?
            
            Return JSON: {"is_flowchart": bool, "has_decision_diamond": bool, "has_branch_labels": bool}
            """
            
            vlm_res = query_vlm(images=[final_screenshot], prompt=vlm_prompt)
            
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('is_flowchart', False):
                    score += 5
                    feedback_parts.append("Visual verification: Flowchart detected.")
                if parsed.get('has_decision_diamond', False):
                    score += 5
                    feedback_parts.append("Visual verification: Decision diamond visible.")
                if parsed.get('has_branch_labels', False):
                    # Bonus checks
                    pass 
            else:
                # If VLM fails, we default to believing the XML check but note it
                logger.warning("VLM verification skipped or failed.")

    # Final Scoring
    # Pass threshold: 70
    # Weights: Text(30) + Connectors(30) + Shapes(20) + Grouping(10) + VLM(10) = 100
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }