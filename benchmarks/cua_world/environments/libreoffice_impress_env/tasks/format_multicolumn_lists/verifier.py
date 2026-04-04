#!/usr/bin/env python3
"""
Verifier for format_multicolumn_lists task.

Verifies that:
1. The ODP file exists and was modified.
2. The specific text box on Slide 2 has been set to 2 columns.
3. The spacing is approximately 0.5cm.
4. The text content (sponsors) is still intact and in a single object (not manually split).
"""

import json
import tempfile
import os
import zipfile
import logging
import shutil
from lxml import etree

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Namespaces for ODF parsing
NS = {
    'office': "urn:oasis:names:tc:opendocument:xmlns:office:1.0",
    'draw': "urn:oasis:names:tc:opendocument:xmlns:drawing:1.0",
    'style': "urn:oasis:names:tc:opendocument:xmlns:style:1.0",
    'fo': "urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0",
    'text': "urn:oasis:names:tc:opendocument:xmlns:text:1.0"
}

def verify_multicolumn_list(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    metadata = task_info.get('metadata', {})
    target_path = metadata.get('target_file', '/home/ga/Documents/Presentations/gala_sponsors.odp')
    expected_cols = metadata.get('expected_column_count', 2)
    expected_spacing = metadata.get('expected_spacing_cm', 0.5)
    
    # Create temp directory
    temp_dir = tempfile.mkdtemp()
    local_odp = os.path.join(temp_dir, "presentation.odp")
    
    score = 0
    feedback = []
    
    try:
        # 1. Check file existence and modification
        copy_from_env("/tmp/task_result.json", os.path.join(temp_dir, "result.json"))
        with open(os.path.join(temp_dir, "result.json"), 'r') as f:
            result_data = json.load(f)
            
        if not result_data.get("file_exists"):
            return {"passed": False, "score": 0, "feedback": "Presentation file not found"}
        
        if not result_data.get("was_modified"):
            feedback.append("⚠️ File timestamp indicates no save operation performed")
        else:
            score += 10
            feedback.append("✅ File saved")

        # Copy the ODP file
        copy_from_env(target_path, local_odp)
        
        # 2. Extract content.xml and styles.xml
        with zipfile.ZipFile(local_odp, 'r') as z:
            content_xml = z.read('content.xml')
        
        # Parse XML
        root = etree.fromstring(content_xml)
        
        # Locate Slide 2 (draw:page index 1)
        pages = root.xpath('//draw:page', namespaces=NS)
        if len(pages) < 2:
            return {"passed": False, "score": score, "feedback": "Presentation structure corrupted (missing slides)"}
        
        slide2 = pages[1] # 0-indexed, so 1 is Slide 2
        
        # Locate the text box with sponsors
        # We look for a text box containing "Riverfront Catering" or "TechStart"
        text_frames = slide2.xpath('.//draw:frame[.//text:p[contains(text(), "Riverfront")]]', namespaces=NS)
        
        if not text_frames:
            # Maybe the user split the text? Check for partial content
            return {"passed": False, "score": score, "feedback": "Could not find the original sponsor list text box. Did you delete or overwrite it?"}
        
        if len(text_frames) > 1:
            # If multiple frames match the content, they might have duplicated it or split it
            feedback.append("⚠️ Detected multiple objects with sponsor text")
        
        frame = text_frames[0]
        
        # Verify it's a single object containing all/most text (Anti-gaming check)
        # Check integrity of content inside this frame
        frame_text = "".join(frame.xpath('.//text:p//text()', namespaces=NS))
        sponsor_samples = ["Riverfront", "TechStart", "Urban Design", "Citywide"]
        found_samples = sum(1 for s in sponsor_samples if s in frame_text)
        
        if found_samples < 3:
             feedback.append("❌ Content appears missing or split into multiple manual boxes")
        else:
             score += 20
             feedback.append("✅ Content intact in single object")

        # 3. Check column properties
        # The frame has a 'draw:style-name' attribute
        style_name = frame.get(f"{{{NS['draw']}}}style-name")
        if not style_name:
             return {"passed": False, "score": score, "feedback": "Text box has no style applied"}
        
        # Look for the style definition in content.xml (automatic styles)
        # It's usually in <office:automatic-styles>
        style_node = root.xpath(f'//style:style[@style:name="{style_name}"]', namespaces=NS)
        
        if not style_node:
            feedback.append(f"❌ Style definition '{style_name}' not found")
        else:
            style = style_node[0]
            # Column properties are usually in <style:graphic-properties> -> <style:columns>
            columns_node = style.xpath('.//style:columns', namespaces=NS)
            
            if not columns_node:
                feedback.append("❌ No column formatting applied to text box")
            else:
                cols = columns_node[0]
                col_count = cols.get(f"{{{NS['fo']}}}column-count")
                col_gap = cols.get(f"{{{NS['fo']}}}column-gap")
                
                # Check Column Count
                if col_count and int(col_count) == expected_cols:
                    score += 40
                    feedback.append(f"✅ Correct column count ({col_count})")
                else:
                    feedback.append(f"❌ Incorrect column count: found {col_count}, expected {expected_cols}")
                
                # Check Spacing
                # Spacing string can be "0.5cm", "0.50cm", "5mm", etc.
                # We do a basic check
                if col_gap:
                    # Normalized check
                    is_correct_spacing = False
                    if "0.5" in col_gap and "cm" in col_gap: is_correct_spacing = True
                    if "5" in col_gap and "mm" in col_gap: is_correct_spacing = True
                    # ODF sometimes uses inch
                    if "0.19" in col_gap or "0.2" in col_gap: is_correct_spacing = True # approx 0.5cm
                    
                    if is_correct_spacing:
                        score += 30
                        feedback.append(f"✅ Correct column spacing ({col_gap})")
                    else:
                        feedback.append(f"❌ Incorrect spacing: found {col_gap}, expected 0.5cm")
                else:
                    feedback.append("❌ Spacing not specified")

    except Exception as e:
        logger.error(f"Verification Failed: {e}")
        return {"passed": False, "score": score, "feedback": f"Verification error: {str(e)}"}
    finally:
        shutil.rmtree(temp_dir)

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }