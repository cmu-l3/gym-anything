#!/usr/bin/env python3
"""
Verifier for Fix Slide Layering Visibility task.

Verification Logic:
1. Parse the ODP file XML (content.xml).
2. For Slide 1:
   - Identify "Map" object, "Yellow Box" object, and "Text" objects.
   - Verify index(Map) < index(Yellow Box) < index(Text).
3. For Slide 2:
   - Identify "Watermark" object and "Text" content.
   - Verify index(Watermark) < index(Text).
4. Verify file modification.
"""

import json
import tempfile
import os
import zipfile
import logging
from xml.dom import minidom

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_layering(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_meta.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Presentation file not found"}

    if not result_meta.get('file_modified'):
        return {"passed": False, "score": 0, "feedback": "File was not saved (timestamp not updated)"}

    # Retrieve the ODP file
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env("/tmp/task_result.odp", temp_odp.name)
        
        # Parse ODP structure
        # ODP is a zip file containing content.xml
        with zipfile.ZipFile(temp_odp.name, 'r') as z:
            with z.open('content.xml') as f:
                content_xml = f.read()
                
        dom = minidom.parseString(content_xml)
        
        score = 0
        feedback_parts = []
        
        # Get all slides (draw:page)
        # Note: Tag names might be prefixed with 'draw:'
        pages = dom.getElementsByTagName('draw:page')
        if len(pages) < 2:
            return {"passed": False, "score": 0, "feedback": "Presentation structure corrupted (missing slides)"}
        
        # --- VERIFY SLIDE 1 ---
        # Objects:
        # - Map: Frame with name="MapImage" (or identified by size/style)
        # - Text: Frame containing "West Region" / "East Region"
        # - Box: Rect (draw:rect)
        
        slide1 = pages[0]
        # Get direct children (shapes) in order
        children = [c for c in slide1.childNodes if c.nodeType == 1] # 1 is Element Node
        
        map_idx = -1
        box_idx = -1
        text_indices = []
        
        for idx, child in enumerate(children):
            node_name = child.nodeName
            
            # Check for Map (Frame with specific name or large size)
            if node_name == 'draw:frame' and child.getAttribute('draw:name') == 'MapImage':
                map_idx = idx
                
            # Check for Yellow Box (Rect)
            # In setup we used draw:rect. 
            if node_name == 'draw:rect':
                # Assuming only one rect on this slide based on setup
                box_idx = idx
                
            # Check for Text Labels
            if node_name == 'draw:frame':
                # Check content for "West Region" or "East Region"
                text_content = child.toxml()
                if "West Region" in text_content or "East Region" in text_content:
                    text_indices.append(idx)

        # Check Slide 1 Logic
        s1_passed = True
        
        # 1. Map must be at bottom relative to others
        if map_idx == -1:
            feedback_parts.append("Slide 1: Map object missing")
            s1_passed = False
        else:
            # Check Map < Text
            for t_idx in text_indices:
                if map_idx > t_idx:
                    feedback_parts.append("Slide 1: Map is covering text")
                    s1_passed = False
                    break
            
            # Check Map < Box
            if box_idx != -1 and map_idx > box_idx:
                feedback_parts.append("Slide 1: Map is covering highlight box")
                s1_passed = False

        # 2. Box must be behind Text
        if box_idx != -1 and text_indices:
            for t_idx in text_indices:
                if box_idx > t_idx:
                    feedback_parts.append("Slide 1: Highlight box is covering text")
                    s1_passed = False
                    break
        
        if s1_passed:
            score += 60
            feedback_parts.append("Slide 1: Layering correct")

        # --- VERIFY SLIDE 2 ---
        # Objects:
        # - Watermark: Frame with name="DraftWatermark"
        # - Content: Frame with name="ContentText"
        
        slide2 = pages[1]
        children_s2 = [c for c in slide2.childNodes if c.nodeType == 1]
        
        watermark_idx = -1
        content_idx = -1
        
        for idx, child in enumerate(children_s2):
            # Check Watermark
            if child.getAttribute('draw:name') == 'DraftWatermark':
                watermark_idx = idx
            # Check Content
            if child.getAttribute('draw:name') == 'ContentText':
                content_idx = idx
                
        # Check Slide 2 Logic
        s2_passed = True
        
        if watermark_idx == -1:
            feedback_parts.append("Slide 2: Watermark missing")
            s2_passed = False
        elif content_idx == -1:
            feedback_parts.append("Slide 2: Content text missing")
            s2_passed = False
        else:
            if watermark_idx > content_idx:
                feedback_parts.append("Slide 2: Watermark is covering text")
                s2_passed = False
            else:
                score += 30
                feedback_parts.append("Slide 2: Layering correct")

        # File saved points
        score += 10
        
        return {
            "passed": score >= 100,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error analyzing ODP file: {e}"}
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)