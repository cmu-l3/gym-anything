#!/usr/bin/env python3
"""Verifier for create_external_image_gallery task."""

import json
import tempfile
import os
import re

def verify_image_gallery(traj, env_info, task_info):
    """Verify that external image tiddlers and a gallery dashboard were properly created."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_landmarks = metadata.get('landmarks', {})

    # Copy result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/image_gallery_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    landmarks_data = result.get('landmarks', {})
    gallery_data = result.get('gallery', {})
    
    # Trackers for sub-scores
    tiddlers_exist = 0
    types_correct = 0
    uris_correct = 0
    metadata_correct = 0
    bloat_detected = False
    
    landmark_keys = [("Colosseum", "Colosseum"), ("Taj Mahal", "Taj_Mahal"), ("Machu Picchu", "Machu_Picchu")]
    
    for real_name, json_key in landmark_keys:
        ld = landmarks_data.get(json_key, {})
        expected = expected_landmarks.get(real_name, {})
        
        # 1. Image Tiddlers Exist (Max 15 pts -> 5 pts each)
        if ld.get('exists', False):
            tiddlers_exist += 1
            
            # 2. Content Type Set (Max 15 pts -> 5 pts each)
            if ld.get('type', '').lower() == 'image/jpeg':
                types_correct += 1
                
            # 3. Canonical URIs Set (Max 30 pts -> 10 pts each)
            uri = ld.get('uri', '').strip()
            exp_uri = expected.get('uri', '').strip()
            if uri and (uri == exp_uri or exp_uri in uri):
                uris_correct += 1
                
            # 4. Metadata Fields Set (Max 15 pts -> 2.5 pts each for loc/year -> 5 pts each tiddler)
            loc = ld.get('location', '').strip()
            year = ld.get('year', '').strip()
            exp_loc = expected.get('location', '')
            exp_year = expected.get('year', '')
            
            meta_pts = 0
            if loc.lower() == exp_loc.lower():
                meta_pts += 1
            if year.lower() == exp_year.lower():
                meta_pts += 1
            if meta_pts == 2:
                metadata_correct += 1
                
            # Base64 Bloat Check (Text length should be tiny, e.g., < 1000 characters)
            text_len = ld.get('text_length', 0)
            if text_len > 1000:
                bloat_detected = True
        else:
            feedback_parts.append(f"Missing: {real_name}")

    # Accumulate points
    score += (tiddlers_exist * 5)
    score += (types_correct * 5)
    score += (uris_correct * 10)
    score += (metadata_correct * 5)

    if tiddlers_exist > 0:
        feedback_parts.append(f"{tiddlers_exist}/3 Tiddlers exist")
    if types_correct > 0:
        feedback_parts.append(f"{types_correct}/3 Types set")
    if uris_correct > 0:
        feedback_parts.append(f"{uris_correct}/3 URIs correct")
    if metadata_correct > 0:
        feedback_parts.append(f"{metadata_correct}/3 Metadata correct")

    # 5. No Base64 Bloat (Max 10 pts)
    if tiddlers_exist > 0 and not bloat_detected:
        score += 10
        feedback_parts.append("No base64 bloat detected")
    elif bloat_detected:
        feedback_parts.append("FAIL: Base64/Text bloat detected in image tiddlers")

    # 6. Gallery Created (Max 15 pts)
    gallery_exists = gallery_data.get('exists', False)
    gallery_text = gallery_data.get('text', '')
    
    gallery_refs_count = 0
    if gallery_exists:
        # Check if gallery text contains references to the landmarks or a list filter
        references = ['Colosseum', 'Taj Mahal', 'Machu Picchu', 'Landmark', 'landmark']
        for ref in references:
            if re.search(re.escape(ref), gallery_text, re.IGNORECASE):
                gallery_refs_count += 1
                
        if gallery_refs_count > 0 and len(gallery_text.split()) >= 3:
            score += 15
            feedback_parts.append("Gallery created and populated")
        elif gallery_refs_count > 0:
            score += 10
            feedback_parts.append("Gallery created but missing intro text")
        else:
            score += 5
            feedback_parts.append("Gallery created but no references to images found")
    else:
        feedback_parts.append("FAIL: Gallery not created")

    # Anti-gaming: Ensure it was done via GUI
    if not result.get('gui_save_detected', False):
        feedback_parts.append("(Warning: GUI save not detected in logs)")

    # Key criteria threshold
    key_criteria_met = (uris_correct >= 3 and not bloat_detected)
    passed = (score >= 80) and key_criteria_met

    if passed:
        feedback_parts.insert(0, "SUCCESS")
    else:
        feedback_parts.insert(0, "INCOMPLETE")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }