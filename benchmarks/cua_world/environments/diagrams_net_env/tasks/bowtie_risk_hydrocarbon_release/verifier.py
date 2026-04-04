#!/usr/bin/env python3
"""
Verifier for bowtie_risk_hydrocarbon_release task.
Checks:
1. File existence and modification time.
2. Structure of the Bow-Tie diagram (Threats -> Barriers -> Top -> Barriers -> Consequences).
3. Presence of Risk Matrix on a second page.
4. Correct color coding and content.
"""

import json
import tempfile
import os
import sys
import zlib
import base64
import urllib.parse
from xml.etree import ElementTree as ET

def decode_diagram(encoded_text):
    """Decode draw.io diagram content (Deflate + Base64 + URL decode)."""
    try:
        # 1. URL Decode
        decoded = urllib.parse.unquote(encoded_text)
        # 2. Base64 Decode
        decoded = base64.b64decode(decoded)
        # 3. Inflate (raw deflate)
        # -15 indicates raw deflate (no zlib header)
        xml_content = zlib.decompress(decoded, -15).decode('utf-8')
        return xml_content
    except Exception as e:
        # If it fails, it might be plain XML already
        return encoded_text

def parse_drawio_file(file_path):
    """Parse a .drawio file and return list of cells per page."""
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        pages = []
        
        # Check if multiple pages (diagram tags)
        diagram_nodes = root.findall('diagram')
        if not diagram_nodes:
            # Maybe just a graph model directly?
            model = root.find('mxGraphModel')
            if model is not None:
                pages.append(list(model.iter('mxCell')))
        else:
            for diag in diagram_nodes:
                content = diag.text
                if content:
                    xml_content = decode_diagram(content)
                    page_root = ET.fromstring(xml_content)
                    # Extract all mxCell elements
                    cells = list(page_root.iter('mxCell'))
                    pages.append({'name': diag.get('name', 'Page'), 'cells': cells})
        return pages
    except Exception as e:
        print(f"Error parsing drawio file: {e}")
        return []

def verify_bowtie_risk_hydrocarbon_release(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
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

    # Check 1: File Modification (Anti-gaming)
    if not result.get('file_modified_during_task'):
        return {"passed": False, "score": 0, "feedback": "Task failed: Output file was not created or modified during the task."}
    score += 10
    feedback.append("File created/modified.")

    # Check 2: PDF Export
    if result.get('pdf_exists') and result.get('pdf_size', 0) > 1000:
        score += 10
        feedback.append("PDF export successful.")
    else:
        feedback.append("PDF export missing or empty.")

    # Check 3: Analyze .drawio content
    drawio_path = "/home/ga/Diagrams/bowtie_hydrocarbon_release.drawio"
    temp_drawio = tempfile.NamedTemporaryFile(delete=False, suffix='.drawio')
    
    try:
        copy_from_env(drawio_path, temp_drawio.name)
        pages = parse_drawio_file(temp_drawio.name)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to retrieve/parse .drawio file: {e}"}
    finally:
        if os.path.exists(temp_drawio.name):
            os.unlink(temp_drawio.name)

    if not pages:
        return {"passed": False, "score": score, "feedback": "Diagram file is empty or invalid XML."}

    # Verify Page Count
    if len(pages) >= 2:
        score += 10
        feedback.append(f"Multiple pages found ({len(pages)}).")
    else:
        feedback.append(f"Only {len(pages)} page(s) found (expected 2).")

    # Content Verification
    all_text = []
    all_styles = []
    
    # Flatten all text and styles for easy searching
    for page in pages:
        for cell in page['cells']:
            val = cell.get('value', '')
            style = cell.get('style', '')
            if val: all_text.append(val.lower())
            if style: all_styles.append(style.lower())

    joined_text = " ".join(all_text)
    joined_styles = " ".join(all_styles)

    # Check 4: Top Event (10 pts)
    if "uncontrolled hydrocarbon" in joined_text or "top event" in joined_text:
        score += 10
        feedback.append("Top Event found.")
    else:
        feedback.append("Top Event text missing.")

    # Check 5: Threats (10 pts) - Look for keywords
    threats_found = 0
    threat_keywords = ["wellbore", "process equipment", "flowline", "human error", "extreme weather"]
    for kw in threat_keywords:
        if kw in joined_text:
            threats_found += 1
    
    if threats_found >= 4:
        score += 10
        feedback.append(f"Threats found ({threats_found}/5).")
    else:
        feedback.append(f"Missing threats ({threats_found}/5).")

    # Check 6: Barriers (Prevention & Mitigation) (20 pts)
    barrier_keywords = ["integrity management", "pressure safety", "subsea", "permit", "met-ocean", 
                        "gas detection", "emergency response", "oil spill", "business continuity", "investigation"]
    barriers_found = 0
    for kw in barrier_keywords:
        if kw in joined_text:
            barriers_found += 1
    
    if barriers_found >= 8:
        score += 20
        feedback.append(f"Barriers found ({barriers_found}/10).")
    elif barriers_found >= 4:
        score += 10
        feedback.append(f"Some barriers found ({barriers_found}/10).")
    else:
        feedback.append("Insufficient barriers found.")

    # Check 7: Consequences (10 pts)
    consequence_keywords = ["fire", "casualt", "environmental", "asset damage", "regulatory"]
    cons_found = 0
    for kw in consequence_keywords:
        if kw in joined_text:
            cons_found += 1
    
    if cons_found >= 3:
        score += 10
        feedback.append(f"Consequences found ({cons_found}/5).")
    else:
        feedback.append("Insufficient consequences found.")

    # Check 8: Risk Matrix (10 pts)
    matrix_keywords = ["likelihood", "severity", "rare", "almost certain", "catastrophic", "negligible"]
    matrix_score = 0
    for kw in matrix_keywords:
        if kw in joined_text:
            matrix_score += 1
    
    if matrix_score >= 4:
        score += 10
        feedback.append("Risk Matrix content found.")
    else:
        feedback.append("Risk Matrix content missing.")

    # Check 9: Color Coding (10 pts) - Looking for Hex codes in styles
    # Red, Blue, Green, Orange
    colors_found = 0
    # Common draw.io hex codes might be lower or uppercase
    if "f8cecc" in joined_styles or "ff4444" in joined_styles or "ff0000" in joined_styles: colors_found += 1 # Red-ish
    if "dae8fc" in joined_styles or "4488cc" in joined_styles or "0000ff" in joined_styles: colors_found += 1 # Blue-ish
    if "d5e8d4" in joined_styles or "44aa44" in joined_styles or "00ff00" in joined_styles: colors_found += 1 # Green-ish
    if "ffe6cc" in joined_styles or "ff8800" in joined_styles or "ff8000" in joined_styles: colors_found += 1 # Orange-ish

    if colors_found >= 3:
        score += 10
        feedback.append("Semantic color coding applied.")
    else:
        feedback.append("Insufficient color coding detected.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }