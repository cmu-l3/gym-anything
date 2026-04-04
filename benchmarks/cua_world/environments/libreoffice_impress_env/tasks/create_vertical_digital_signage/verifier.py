#!/usr/bin/env python3
"""
Verifier for Create Vertical Digital Signage task.

Checks:
1. File exists and is a valid ODP.
2. Slide orientation is Vertical (Width < Height).
3. Slide count is 4.
4. Text content includes required city names.
5. Presentation is set to loop.
6. Slides are set to auto-advance.
"""

import json
import os
import tempfile
import zipfile
import xml.etree.ElementTree as ET
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_odp_xml(filepath):
    """
    Manually parse ODP XML to check specific settings not always exposed by libraries.
    Returns a dict with parsed properties.
    """
    info = {
        "valid": False,
        "orientation": "unknown",
        "width": 0,
        "height": 0,
        "slide_count": 0,
        "text_content": [],
        "auto_advance": False,
        "loop_endless": False,
        "image_count": 0
    }
    
    if not os.path.exists(filepath):
        return info

    try:
        with zipfile.ZipFile(filepath, 'r') as z:
            # 1. Parse styles.xml for page layout (Orientation)
            if 'styles.xml' in z.namelist():
                with z.open('styles.xml') as f:
                    tree = ET.parse(f)
                    root = tree.getroot()
                    
                    # Namespaces
                    ns = {
                        'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
                        'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0'
                    }
                    
                    # Find master page layout properties
                    # Look for <style:page-layout-properties> inside <style:page-layout>
                    for pl in root.findall('.//style:page_layout', ns): # Note: underscores vs hyphens vary in some parsers, using wildcards if needed
                        # In standard ODF: <style:page-layout><style:page-layout-properties fo:page-width="..." fo:page-height="...">
                        props = pl.find('style:page-layout-properties', ns)
                        if props is not None:
                            w_str = props.get(f"{{{ns['fo']}}}page-width")
                            h_str = props.get(f"{{{ns['fo']}}}page-height")
                            
                            if w_str and h_str:
                                # Convert units roughly to check ratio
                                def parse_dim(s):
                                    val = float(''.join(c for c in s if c.isdigit() or c == '.'))
                                    return val
                                
                                w = parse_dim(w_str)
                                h = parse_dim(h_str)
                                info['width'] = w
                                info['height'] = h
                                if h > w:
                                    info['orientation'] = "portrait"
                                else:
                                    info['orientation'] = "landscape"
                                break # Assume all slides same master

            # 2. Parse content.xml for Slides, Text, Images, and Presentation Settings
            if 'content.xml' in z.namelist():
                with z.open('content.xml') as f:
                    tree = ET.parse(f)
                    root = tree.getroot()
                    
                    ns = {
                        'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
                        'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
                        'presentation': 'urn:oasis:names:tc:opendocument:xmlns:presentation:1.0'
                    }
                    
                    # Slide count
                    slides = root.findall('.//draw:page', ns)
                    info['slide_count'] = len(slides)
                    
                    # Text content
                    texts = root.findall('.//text:p', ns)
                    for t in texts:
                        if t.text:
                            info['text_content'].append(t.text)
                        # Also check spans
                        for s in t.findall('.//text:span', ns):
                            if s.text:
                                info['text_content'].append(s.text)
                                
                    # Images (frames with image)
                    images = root.findall('.//draw:image', ns)
                    info['image_count'] = len(images)
                    
                    # Auto-advance check
                    # Look for presentation:transition-type="automatic" on draw:page
                    auto_pages = 0
                    for slide in slides:
                        trans_type = slide.get(f"{{{ns['presentation']}}}transition-type")
                        duration = slide.get(f"{{{ns['presentation']}}}duration")
                        if trans_type == "automatic":
                            auto_pages += 1
                    
                    if auto_pages >= len(slides) and len(slides) > 0:
                        info['auto_advance'] = True
                        
                    # Loop setting
                    # <presentation:settings presentation:endless="true" ... />
                    settings = root.find('.//presentation:settings', ns)
                    if settings is not None:
                        endless = settings.get(f"{{{ns['presentation']}}}endless")
                        if endless == "true":
                            info['loop_endless'] = True

            info['valid'] = True

    except Exception as e:
        logger.error(f"Error parsing ODP: {e}")
    
    return info

def verify_vertical_signage(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/Presentations/vertical_signage.odp')
    required_cities = metadata.get('required_cities', ["New York", "Paris", "Tokyo", "London"])
    
    # 1. Get Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    if not result_data.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # 2. Get ODP File
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env(expected_path, temp_odp.name)
        
        # Parse ODP
        info = parse_odp_xml(temp_odp.name)
        
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse ODP file: {e}"}
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)

    # 3. Scoring
    score = 0
    feedback = []
    
    # Criterion 1: Valid File (10pts)
    if info['valid']:
        score += 10
    else:
        return {"passed": False, "score": 0, "feedback": "File is corrupted or not a valid ODP."}
        
    # Criterion 2: Vertical Orientation (20pts)
    if info['orientation'] == 'portrait':
        score += 20
        feedback.append("✅ Orientation is Vertical")
    else:
        feedback.append(f"❌ Orientation is {info['orientation']} (Expected: Portrait)")

    # Criterion 3: Content Completeness (20pts)
    cities_found = 0
    full_text = " ".join(info['text_content']).lower()
    for city in required_cities:
        if city.lower() in full_text:
            cities_found += 1
            
    if info['slide_count'] == 4:
        score += 10
        feedback.append("✅ 4 Slides present")
    else:
        feedback.append(f"❌ Found {info['slide_count']} slides (Expected: 4)")
        
    if cities_found == 4:
        score += 10
        feedback.append("✅ All city names found")
    else:
        feedback.append(f"⚠️ Found {cities_found}/4 city names")

    # Criterion 4: Images Present (20pts)
    if info['image_count'] >= 4:
        score += 20
        feedback.append("✅ Images present")
    elif info['image_count'] > 0:
        score += 10
        feedback.append(f"⚠️ Only {info['image_count']} images found")
    else:
        feedback.append("❌ No images found")

    # Criterion 5: Auto-Advance (15pts)
    if info['auto_advance']:
        score += 15
        feedback.append("✅ Auto-advance enabled")
    else:
        feedback.append("❌ Slides not set to auto-advance")

    # Criterion 6: Looping Enabled (15pts)
    if info['loop_endless']:
        score += 15
        feedback.append("✅ Endless loop enabled")
    else:
        feedback.append("❌ Presentation loop not enabled")

    passed = score >= 75 and info['orientation'] == 'portrait' and info['auto_advance']
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }