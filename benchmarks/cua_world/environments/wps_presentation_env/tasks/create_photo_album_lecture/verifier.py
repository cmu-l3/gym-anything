#!/usr/bin/env python3
"""
Verifier for create_photo_album_lecture task.

Verification Strategy:
1. Output file exists and was created during the task.
2. File is a valid PPTX (ZIP archive).
3. Evaluates internal PPTX structure for slides count (>= 8).
4. Evaluates internal PPTX structure for embedded media size and count.
5. Verifies if slide XMLs contain DrawingML picture objects (`<p:pic` or `<a:blip`).
"""

import json
import tempfile
import os
import zipfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_photo_album(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_images = metadata.get('expected_images', 8)
    expected_slides = metadata.get('expected_slides', 8)
    output_path = metadata.get('expected_output_path', '/home/ga/Documents/presentations/architecture_lecture.pptx')

    # Copy result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    output_exists = result.get("output_exists", False)
    file_created = result.get("file_created_during_task", False)

    feedback_parts = []
    score = 0

    if not output_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output presentation file was not found.",
            "details": {"file_exists": False}
        }

    score += 15
    feedback_parts.append("File exists")

    if file_created:
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("WARNING: File timestamp predates task")

    # Metrics
    num_slides = 0
    num_media = 0
    media_size_bytes = 0
    slides_with_pics = 0

    # Copy the actual PPTX to check internal structure
    temp_pptx = tempfile.NamedTemporaryFile(delete=False, suffix='.pptx')
    try:
        copy_from_env(output_path, temp_pptx.name)
        
        # Verify ZIP/PPTX structure
        if zipfile.is_zipfile(temp_pptx.name):
            with zipfile.ZipFile(temp_pptx.name, 'r') as z:
                # 1. Check slides count
                slide_files = [f for f in z.namelist() if f.startswith('ppt/slides/slide') and f.endswith('.xml')]
                num_slides = len(slide_files)
                
                # 2. Check media files count and size
                media_files = [f for f in z.namelist() if f.startswith('ppt/media/')]
                num_media = len(media_files)
                media_size_bytes = sum(z.getinfo(m).file_size for m in media_files)
                
                # 3. Check for picture tags in slides
                for slide in slide_files:
                    xml_content = z.read(slide)
                    if b'<p:pic' in xml_content or b'<p:pic>' in xml_content or b'<a:blip' in xml_content:
                        slides_with_pics += 1
                        
            # Evaluate metrics
            if num_slides >= expected_slides:
                score += 25
                feedback_parts.append(f"Proper slide count ({num_slides})")
            elif num_slides > 0:
                score += int((num_slides / expected_slides) * 25)
                feedback_parts.append(f"Insufficient slides ({num_slides}/{expected_slides})")
                
            if num_media >= expected_images and media_size_bytes > 50000:
                score += 30
                feedback_parts.append(f"Media embedded ({num_media} files, {media_size_bytes//1024} KB)")
            elif num_media > 0:
                score += int((num_media / expected_images) * 30)
                feedback_parts.append(f"Partial media embedded ({num_media} files, {media_size_bytes//1024} KB)")
            else:
                feedback_parts.append("No media files found inside PPTX")
                
            if slides_with_pics >= expected_images:
                score += 30
                feedback_parts.append(f"Pictures inserted in {slides_with_pics} slides")
            elif slides_with_pics > 0:
                score += int((slides_with_pics / expected_images) * 30)
                feedback_parts.append(f"Pictures inserted in {slides_with_pics} slides")
            else:
                feedback_parts.append("No picture elements found in slides")
                
        else:
            feedback_parts.append("File is not a valid PPTX (ZIP) archive")

    except Exception as e:
        feedback_parts.append(f"Error validating PPTX: {str(e)}")
    finally:
        if os.path.exists(temp_pptx.name):
            os.unlink(temp_pptx.name)

    passed = score >= 85 and output_exists and (num_media >= expected_images) and (num_slides >= expected_slides)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }