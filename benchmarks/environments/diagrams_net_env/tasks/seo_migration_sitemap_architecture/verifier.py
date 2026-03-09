#!/usr/bin/env python3
"""
Verifier for SEO Migration Sitemap Architecture task.
Checks:
1. File creation/modification.
2. Structure of the sitemap (XML parsing of .drawio).
3. Data filtering logic (exclusion of low traffic pages).
4. Color coding semantics.
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

def decode_drawio_xml(raw_xml):
    """
    Decodes the Draw.io XML format.
    Draw.io often stores compressed data inside the <diagram> tag.
    Format: URL-encoded -> Base64 -> Raw Deflate (no header) -> XML
    """
    try:
        # Check if it's standard XML first
        root = ET.fromstring(raw_xml)
        if root.tag == 'mxfile':
            for diagram in root.findall('diagram'):
                if diagram.text and diagram.text.strip():
                    # It is compressed
                    try:
                        # 1. Decode generic XML entities if any (rare in the text block itself but good practice)
                        text = diagram.text.strip()
                        # 2. Base64 decode
                        compressed_data = base64.b64decode(text)
                        # 3. Inflate (raw deflate, negative window size)
                        decompressed_xml = zlib.decompress(compressed_data, -15).decode('utf-8')
                        # 4. URL Unquote (sometimes needed, sometimes not, standard drawio is usually raw after inflate)
                        # Actually, standard flow is:
                        # If the text is simple, it might be just base64.
                        # Usually it is: raw text -> inflate -> url decode.
                        # Let's try standard decompression sequence for draw.io
                        return ET.fromstring(urllib.parse.unquote(decompressed_xml))
                    except Exception as e:
                        # If decompression fails, it might be uncompressed?
                        logger.warning(f"Decompression failed, trying raw: {e}")
                        return root 
            return root # Return root if no compressed text found (uncompressed file)
        return root
    except Exception as e:
        logger.error(f"Failed to parse XML: {e}")
        return None

def verify_seo_migration_sitemap(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_json = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Retrieve Draw.io File
    temp_drawio = tempfile.NamedTemporaryFile(delete=False, suffix='.drawio')
    drawio_content = None
    try:
        copy_from_env("/home/ga/Diagrams/sitemap_architecture.drawio", temp_drawio.name)
        with open(temp_drawio.name, 'rb') as f:
            drawio_content = f.read()
    except Exception:
        # File might not exist
        pass
    finally:
        if os.path.exists(temp_drawio.name):
            os.unlink(temp_drawio.name)

    # --- Scoring Logic ---
    score = 0
    feedback = []

    # Criterion 1: Files Exist (10 pts)
    if result_json.get("drawio_exists"):
        score += 5
        feedback.append("Draw.io file created.")
    else:
        feedback.append("Draw.io file missing.")
    
    if result_json.get("pdf_exists"):
        score += 5
        feedback.append("PDF export created.")
    else:
        feedback.append("PDF export missing.")

    if not drawio_content:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Criterion 2: Content Analysis (Parsing)
    # Parse the diagram
    xml_root = decode_drawio_xml(drawio_content)
    if xml_root is None:
        return {"passed": False, "score": score, "feedback": "Failed to parse draw.io file content."}

    # Extract all text labels and styles
    all_text = []
    all_styles = []
    
    # mxCell elements usually hold the data
    # Recursively find all mxCell
    for cell in xml_root.iter('mxCell'):
        val = cell.get('value', '')
        style = cell.get('style', '')
        if val:
            all_text.append(val.lower())
        if style:
            all_styles.append(style.lower())

    text_combined = " ".join(all_text)
    
    # Criterion 3: Data Filtering / Pruning (20 pts)
    # Check for EXCLUDED pages (Low traffic)
    # Forbidden: "/shop/mens/discontinued-boots", "Company Picnic"
    # Allowed/Required: "Returns" (low traffic but exception)
    
    forbidden_terms = ["discontinued", "company picnic", "legacy", "wipes"]
    found_forbidden = [term for term in forbidden_terms if term in text_combined]
    
    if not found_forbidden:
        score += 20
        feedback.append("Correctly filtered low-traffic pages.")
    else:
        feedback.append(f"Failed to filter low-traffic pages: {found_forbidden}")

    # Criterion 4: Restructuring Logic (20 pts)
    # Should see "Footwear" and "Apparel" (Consolidated)
    # Should NOT see "Men's Hiking Boots" distinct from Women's, but generic labels are okay.
    # The key is the presence of the NEW categories.
    required_new = ["footwear", "apparel", "journal", "brands"]
    found_required = [term for term in required_new if term in text_combined]
    
    if len(found_required) == len(required_new):
        score += 20
        feedback.append("Structure updated correctly (Footwear/Apparel/Journal/Brands found).")
    elif len(found_required) >= 2:
        score += 10
        feedback.append(f"Partial structure update. Found: {found_required}")
    else:
        feedback.append("Failed to create new consolidated categories.")

    # Criterion 5: Exception Logic (15 pts)
    # "Returns" has 85 views (<100) but is an exception. Must be present.
    if "returns" in text_combined:
        score += 15
        feedback.append("Correctly retained 'Returns' utility page.")
    else:
        feedback.append("Incorrectly pruned 'Returns' page (should be kept).")

    # Criterion 6: Color Coding (15 pts)
    # We check the styles for the specific hex codes requested.
    # Blue: #dae8fc, Green: #d5e8d4, Orange: #ffe6cc
    # Draw.io styles often look like: "fillColor=#dae8fc"
    
    style_blob = " ".join(all_styles)
    has_blue = "#dae8fc" in style_blob
    has_green = "#d5e8d4" in style_blob
    has_orange = "#ffe6cc" in style_blob
    
    if has_blue and has_green and has_orange:
        score += 15
        feedback.append("Color coding applied correctly.")
    elif has_blue or has_green or has_orange:
        score += 5
        feedback.append("Partial color coding detected.")
    else:
        feedback.append("No requested color coding found.")

    # Criterion 7: Hierarchy (20 pts)
    # Ideally check connections (source/target), but simplified check:
    # Does 'Home' exist? Do we have enough items (at least 5-6)?
    if "home" in text_combined and len(all_text) > 5:
        score += 20
        feedback.append("Basic hierarchy established.")
    else:
        feedback.append("Hierarchy too sparse or missing Home node.")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }