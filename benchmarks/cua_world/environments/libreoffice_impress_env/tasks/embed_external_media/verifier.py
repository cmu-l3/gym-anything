#!/usr/bin/env python3
"""
Verifier for Embed External Media task
"""

import sys
import os
import logging
import json
import zipfile
import tempfile
import shutil
import xml.etree.ElementTree as ET

# Define namespaces usually found in ODP
NAMESPACES = {
    'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
    'xlink': 'http://www.w3.org/1999/xlink',
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'presentation': 'urn:oasis:names:tc:opendocument:xmlns:presentation:1.0'
}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_embed_media(traj, env_info, task_info):
    """
    Verify that external media links have been replaced with embedded resources.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    pres_path = metadata.get('presentation_path', '/home/ga/Documents/Presentations/company_overview.odp')
    
    # Setup temporary directory for verification
    temp_dir = tempfile.mkdtemp()
    local_pres_path = os.path.join(temp_dir, "presentation.odp")
    local_result_path = os.path.join(temp_dir, "task_result.json")
    
    score = 0
    feedback_parts = []
    
    try:
        # 1. Retrieve files
        try:
            copy_from_env(pres_path, local_pres_path)
            copy_from_env("/tmp/task_result.json", local_result_path)
            
            with open(local_result_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to retrieve task files: {str(e)}"
            }

        # 2. Check File Metadata (Anti-Gaming)
        if not result_data.get('file_exists', False):
            return {"passed": False, "score": 0, "feedback": "Presentation file not found"}
        
        if not result_data.get('file_modified', False):
            feedback_parts.append("⚠️ File timestamp not updated (did you save?)")
            # We continue checking in case the timestamp check was flaky, but deduct points
        else:
            score += 10
            feedback_parts.append("✅ File saved successfully")

        # 3. Analyze ODP Content
        # ODP is a zip file. We need to check content.xml for link references.
        try:
            is_embedded_image = False
            is_embedded_audio = False
            has_external_links = False
            
            with zipfile.ZipFile(local_pres_path, 'r') as z:
                # Check for internal media folders
                file_list = z.namelist()
                has_pictures_dir = any(f.startswith('Pictures/') for f in file_list)
                has_media_dir = any(f.startswith('Media/') for f in file_list)
                
                # Parse content.xml
                content_xml = z.read('content.xml')
                root = ET.fromstring(content_xml)
                
                # Register namespaces for findall
                for prefix, uri in NAMESPACES.items():
                    ET.register_namespace(prefix, uri)
                
                # Find all images
                # Note: ElementTree finding with namespaces can be verbose.
                # We'll iterate and check tags to be robust.
                for elem in root.iter():
                    tag = elem.tag
                    
                    # Check <draw:image>
                    if tag.endswith('}image'):
                        href = elem.get(f"{{{NAMESPACES['xlink']}}}href")
                        if href:
                            if href.startswith('Pictures/'):
                                is_embedded_image = True
                            elif href.startswith('file:') or '/' in href:
                                has_external_links = True
                                feedback_parts.append(f"❌ Found external image link: {href}")
                    
                    # Check <draw:plugin> (often used for media/audio)
                    elif tag.endswith('}plugin'):
                        href = elem.get(f"{{{NAMESPACES['xlink']}}}href")
                        if href:
                            if href.startswith('Media/') or href.startswith('Pictures/'): # Sometimes audio goes to Pictures or similar depending on LO version
                                is_embedded_audio = True
                            elif href.startswith('file:') or '/' in href:
                                has_external_links = True
                                feedback_parts.append(f"❌ Found external media link: {href}")

            # 4. Scoring Logic
            
            # Image Embedding
            if is_embedded_image and has_pictures_dir:
                score += 40
                feedback_parts.append("✅ Logo image successfully embedded")
            else:
                feedback_parts.append("❌ Logo image not embedded")

            # Audio Embedding
            # Note: Sometimes audio embedding behavior varies by LO version, but breaking link should create internal ref
            if is_embedded_audio and (has_media_dir or has_pictures_dir):
                score += 40
                feedback_parts.append("✅ Audio file successfully embedded")
            elif is_embedded_audio:
                 score += 30
                 feedback_parts.append("✅ Audio ref changed but Media dir missing? (Partial credit)")
            else:
                feedback_parts.append("❌ Audio file not embedded")

            # Penalty for remaining external links
            if has_external_links:
                score = max(0, score - 20)
                feedback_parts.append("⚠️ Presentation still contains external links")
            else:
                score += 10 # Bonus for clean file
                feedback_parts.append("✅ No external links remaining")

        except zipfile.BadZipFile:
            return {"passed": False, "score": 0, "feedback": "Saved file is not a valid ODP archive"}
        except ET.ParseError:
            return {"passed": False, "score": 0, "feedback": "Saved file has corrupted XML content"}
            
        passed = score >= 90
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification failed: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)