#!/usr/bin/env python3
"""
Verifier for Optimize Presentation File Size task.

Criteria:
1. File must exist and be a valid ODP/Zip.
2. File size must be < 5 MB.
3. Content integrity: Must still contain 5 slides and ~5 images (to prevent deletion).
4. Anti-gaming: File must have been modified during the task.
"""

import json
import os
import tempfile
import zipfile
import logging
from xml.etree import ElementTree

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_optimize_file_size(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_path = metadata.get('target_file', "/home/ga/Documents/Presentations/product_showcase_heavy.odp")
    target_size_mb = metadata.get('target_size_mb', 5.0)
    expected_slides = metadata.get('expected_slide_count', 5)
    
    # 1. Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check basic existence
    if not result_data.get('file_exists', False):
        return {"passed": False, "score": 0, "feedback": "Presentation file was not found."}

    if not result_data.get('file_modified', False):
        return {"passed": False, "score": 0, "feedback": "File was not modified during the task."}

    # 2. Check File Size
    size_bytes = result_data.get('file_size_bytes', 0)
    size_mb = size_bytes / (1024 * 1024)
    
    score = 0
    feedback_parts = []
    
    if size_mb < target_size_mb:
        score += 40
        feedback_parts.append(f"✅ Size optimized: {size_mb:.2f} MB (< {target_size_mb} MB)")
    else:
        feedback_parts.append(f"❌ File too large: {size_mb:.2f} MB (Target < {target_size_mb} MB)")

    # 3. Content Integrity Check (Parse ODP)
    # Copy the actual ODP file to temp for inspection
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env(target_path, temp_odp.name)
        
        # ODP is a zip file. We need to check content.xml for slides and internal structure for images.
        if not zipfile.is_zipfile(temp_odp.name):
            return {"passed": False, "score": 0, "feedback": "Result file is not a valid ODP/Zip archive."}

        with zipfile.ZipFile(temp_odp.name, 'r') as z:
            # Count images in the Pictures/ directory of the zip
            # Note: Optimized images might be renamed, but should still be in Pictures/
            image_files = [f for f in z.namelist() if f.startswith('Pictures/') and len(f) > 9]
            image_count = len(image_files)
            
            # Parse content.xml for slide count
            if 'content.xml' in z.namelist():
                with z.open('content.xml') as f:
                    tree = ElementTree.parse(f)
                    root = tree.getroot()
                    # Define namespaces usually found in ODP
                    ns = {
                        'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
                        'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0'
                    }
                    # Count draw:page elements
                    # Note: ElementTree with wildcards can be tricky, we'll try robust finding
                    # Try finding all elements and filtering by tag name ending in 'page'
                    slides = [elem for elem in root.iter() if elem.tag.endswith('}page')]
                    slide_count = len(slides)
            else:
                slide_count = 0
                feedback_parts.append("❌ Invalid ODP: content.xml missing")

        # Evaluate Integrity
        integrity_score = 0
        
        # Slide Count
        if slide_count == expected_slides:
            integrity_score += 30
            feedback_parts.append(f"✅ {slide_count} slides preserved")
        else:
            feedback_parts.append(f"❌ Slide count changed: Found {slide_count}, expected {expected_slides}")

        # Image Count
        # We expect at least the same number of images (or maybe more if thumbnails generated, but usually not fewer)
        # Allow small deviation if optimization merged things, but usually it shouldn't.
        # Strict check: at least 4 images (allowing 1 accidental loss)
        if image_count >= 4:
            integrity_score += 30
            feedback_parts.append(f"✅ Images preserved ({image_count} found)")
        elif image_count > 0:
            integrity_score += 15
            feedback_parts.append(f"⚠️ Some images lost: Found {image_count}, expected ~{expected_slides}")
        else:
            feedback_parts.append("❌ All images removed")

        score += integrity_score

    except Exception as e:
        logger.error(f"Error verification ODP content: {e}")
        feedback_parts.append(f"Error verifying file content: {str(e)}")
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)

    # Final scoring
    # Pass if size is good AND integrity is perfect (100 points)
    # or size is good and integrity is decent (>80 points)
    
    passed = (score >= 90)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }