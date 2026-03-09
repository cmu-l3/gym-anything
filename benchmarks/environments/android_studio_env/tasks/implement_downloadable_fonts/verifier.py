#!/usr/bin/env python3
"""
Verifier for implement_downloadable_fonts task.
"""

import json
import logging
import os
import re
import tempfile
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_downloadable_fonts(traj, env_info, task_info):
    """
    Verify the implementation of downloadable fonts and styles.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Font XML Created (20 pts) ---
    font_exists = result.get("font_exists", False)
    font_is_xml = result.get("font_is_xml", False)
    font_content = result.get("font_content", "")

    if font_exists and font_is_xml:
        score += 20
        feedback_parts.append("Font XML file created (20/20)")
    elif font_exists:
        feedback_parts.append("Font file exists but is not valid XML (0/20)")
    else:
        feedback_parts.append("Font file res/font/pacifico.xml missing (0/20)")

    # --- Criterion 2: Downloadable Provider Configuration (20 pts) ---
    # Check if the XML references the correct provider (not just a local file)
    # Expected: android:fontProviderAuthority="com.google.android.gms.fonts"
    provider_correct = False
    if "com.google.android.gms.fonts" in font_content:
        provider_correct = True
        score += 20
        feedback_parts.append("Downloadable font provider configured (20/20)")
    else:
        feedback_parts.append("Font XML does not use Google Fonts provider (0/20)")

    # --- Criterion 3: Manifest Meta-data (10 pts) ---
    manifest_content = result.get("manifest_content", "")
    if "com.google.android.gms.fonts" in manifest_content and "<meta-data" in manifest_content:
        score += 10
        feedback_parts.append("Manifest meta-data present (10/10)")
    else:
        feedback_parts.append("Manifest missing font provider meta-data (0/10)")

    # --- Criterion 4: Style Created (20 pts) ---
    # Check both themes.xml and styles.xml content
    themes_content = result.get("themes_content", "")
    styles_content = result.get("styles_content", "")
    combined_styles = themes_content + "\n" + styles_content

    style_name_found = "QuoteTextStyle" in combined_styles
    font_attr_found = "@font/pacifico" in combined_styles
    size_attr_found = "24sp" in combined_styles
    
    if style_name_found and font_attr_found and size_attr_found:
        score += 20
        feedback_parts.append("QuoteTextStyle correctly defined (20/20)")
    elif style_name_found:
        score += 10
        feedback_parts.append("QuoteTextStyle exists but missing font or size attributes (10/20)")
    else:
        feedback_parts.append("QuoteTextStyle not found (0/20)")

    # --- Criterion 5: Style Applied (20 pts) ---
    layout_content = result.get("layout_content", "")
    # Look for style="@style/QuoteTextStyle" inside the TextView
    # Simple regex check
    style_applied = False
    if re.search(r'style="@style/QuoteTextStyle"', layout_content):
        style_applied = True
    
    # Also ensure the hardcoded text attributes are removed (optional but good practice)
    # The task asks to remove conflicting attributes, but we won't penalize heavily if they kept them,
    # as long as the style is applied.
    
    if style_applied:
        score += 20
        feedback_parts.append("Style applied to TextView (20/20)")
    else:
        feedback_parts.append("Style not applied to TextView in layout (0/20)")

    # --- Criterion 6: Build Success (10 pts) ---
    if result.get("build_success", False):
        score += 10
        feedback_parts.append("Project builds successfully (10/10)")
    else:
        feedback_parts.append("Build failed (0/10)")

    # --- Final Scoring ---
    # Pass threshold is 70, but we also require the Font XML and Style Applied
    passed = (score >= 70) and font_exists and provider_correct and style_applied
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }