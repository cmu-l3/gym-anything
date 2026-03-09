#!/usr/bin/env python3
"""
Verifier for create_print_ready_chart_and_export task.

Scoring Breakdown (100 points):
1. Template Management (20 pts): 'PrintReady' template saved and modified during task.
2. Visual Styling (40 pts):
   - Background is White (20 pts)
   - Grid lines hidden/transparent (10 pts)
   - Text/Axis colors contrasting (10 pts - inferred from template or lenient)
3. Indicator Config (20 pts): 
   - SMA(50) present
   - SMA color is NOT default Gold/Yellow (must be visible on white)
4. Export (20 pts): PNG image exists on desktop.

VLM Check (Secondary): Can be used to verify visual look if needed.
"""

import json
import tempfile
import os
import re
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_print_ready_chart(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    template_path_env = metadata.get('template_path', r"C:\Users\Docker\Documents\NinjaTrader 8\templates\Chart\PrintReady.xml")
    
    score = 0
    feedback_parts = []
    
    # 1. Read Basic Result JSON
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}

    # CRITERION 1: Template Saved (20 pts)
    if result.get("template_exists") and result.get("template_modified"):
        score += 20
        feedback_parts.append("Template saved (+20)")
    elif result.get("template_exists"):
        score += 5
        feedback_parts.append("Template exists but not modified during task (+5)")
    else:
        feedback_parts.append("Template 'PrintReady' not found")

    # CRITERION 2 & 3: XML Content Analysis (Colors & Indicators)
    template_content = ""
    try:
        if result.get("template_exists"):
            temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
            copy_from_env(template_path_env, temp_xml.name)
            
            # NinjaTrader XML can be complex, usually serialized XAML or custom XML
            # We will read as string to use regex for robustness against schema variations
            with open(temp_xml.name, 'r', encoding='utf-8', errors='ignore') as f:
                template_content = f.read()
            os.unlink(temp_xml.name)
            
            # Check Background Color (White)
            # Look for ChartBackground with White hex codes (#FFFFFFFF or #FFFFFF or named color)
            # Regex for <ChartBackground ... >#FFFFFFFF</ChartBackground> or value="White"
            if re.search(r'ChartBackground[^>]*>.*?(#FFFFFFFF|#FFFFFF|White).*?<', template_content, re.IGNORECASE) or \
               re.search(r'Property="ChartBackground".*?Value="(#FFFFFFFF|White)"', template_content, re.IGNORECASE):
                score += 20
                feedback_parts.append("Background is White (+20)")
            else:
                feedback_parts.append("Background not detected as White (0)")

            # Check Grid Lines (Hidden or Transparent)
            # Look for IsVisible="false" in GridLine blocks OR Color="Transparent"
            # This is tricky as there are multiple grid lines.
            if re.search(r'GridLine[^>]*IsVisible.*?(false|False)', template_content) or \
               re.search(r'GridLine[^>]*>.*?Transparent.*?<', template_content):
                score += 10
                feedback_parts.append("Grid lines hidden/transparent (+10)")
            else:
                feedback_parts.append("Grid lines visible (0)")
                
            # Check SMA Configuration
            # Look for <ClassName>NinjaTrader.NinjaScript.Indicators.SMA</ClassName> ... <Period>50</Period>
            if "NinjaTrader.NinjaScript.Indicators.SMA" in template_content and ">50<" in template_content:
                # Check SMA Color
                # The default is often Goldenrod (#FFDAA520). We want something else.
                # Find the SMA block is hard with regex, simplified check:
                # If we find SMA and do NOT find the default color associated with it, or find Blue.
                
                # Robust approach: Check if default gold color exists near SMA definition?
                # Alternative: Just check if DarkBlue/Blue exists in the file (likely the user selected it)
                if re.search(r'(#FF00008B|#FF0000FF|Blue|DarkBlue|Black)', template_content, re.IGNORECASE):
                    score += 20
                    feedback_parts.append("SMA(50) present with high-contrast color (+20)")
                elif "DAA520" in template_content: # Default Goldenrod
                    score += 5
                    feedback_parts.append("SMA(50) present but color seems default (hard to see on white) (+5)")
                else:
                    score += 20
                    feedback_parts.append("SMA(50) present (color check permissive) (+20)")
            else:
                feedback_parts.append("SMA(50) not found in template (0)")
            
            # Check Axis/Text Contrast (Simple check for Black text definitions)
            if "Black" in template_content or "#FF000000" in template_content:
                score += 10
                feedback_parts.append("Black text/elements detected (+10)")
            else:
                feedback_parts.append("No Black text elements found (risk of low contrast) (0)")

    except Exception as e:
        feedback_parts.append(f"Template analysis failed: {e}")

    # CRITERION 4: Image Export (20 pts)
    if result.get("image_exists") and result.get("image_created_during_task"):
        if result.get("image_size_bytes", 0) > 1000: # Valid image
            score += 20
            feedback_parts.append("Chart exported to Desktop (+20)")
        else:
            score += 5
            feedback_parts.append("Export file exists but empty (+5)")
    else:
        feedback_parts.append("Image export missing (0)")

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }