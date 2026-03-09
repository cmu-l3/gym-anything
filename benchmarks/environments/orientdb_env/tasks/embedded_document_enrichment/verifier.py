#!/usr/bin/env python3
"""
Verifier for embedded_document_enrichment task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_embedded_document_enrichment(traj, env_info, task_info):
    """
    Verifies the Hotel Data Enrichment task.
    
    Criteria:
    1. Schema: Hotels class has Amenities (EMBEDDEDLIST) and SocialMedia (EMBEDDEDMAP) properties.
    2. Data: The 5 specific hotels have correct embedded data.
    3. Output: JSON report file exists, created during task, and contains correct hotels.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Extract data
    db_state = result.get('database_state', {})
    schema = db_state.get('schema', {})
    hotel_data_result = db_state.get('hotel_data', {})
    hotel_records = hotel_data_result.get('result', [])
    
    # ---------------------------------------------------------
    # 1. Verify Schema (20 points)
    # ---------------------------------------------------------
    amenities_ok = False
    social_ok = False
    
    classes = schema.get('classes', [])
    hotels_class = next((c for c in classes if c['name'] == 'Hotels'), None)
    
    if hotels_class:
        properties = {p['name']: p['type'] for p in hotels_class.get('properties', [])}
        
        # Check Amenities
        if 'Amenities' in properties:
            if properties['Amenities'] == 'EMBEDDEDLIST':
                score += 10
                amenities_ok = True
                feedback.append("Schema: Amenities (EMBEDDEDLIST) exists.")
            else:
                score += 5
                feedback.append(f"Schema: Amenities exists but type is {properties['Amenities']} (expected EMBEDDEDLIST).")
        else:
            feedback.append("Schema: Amenities property missing.")

        # Check SocialMedia
        if 'SocialMedia' in properties:
            if properties['SocialMedia'] == 'EMBEDDEDMAP':
                score += 10
                social_ok = True
                feedback.append("Schema: SocialMedia (EMBEDDEDMAP) exists.")
            else:
                score += 5
                feedback.append(f"Schema: SocialMedia exists but type is {properties['SocialMedia']} (expected EMBEDDEDMAP).")
        else:
            feedback.append("Schema: SocialMedia property missing.")
    else:
        feedback.append("Schema: Hotels class not found.")

    # ---------------------------------------------------------
    # 2. Verify Hotel Data (40 points)
    # ---------------------------------------------------------
    # Define expectations
    expectations = {
        "Hotel Artemide": {"amenity": "WiFi", "social": "twitter"},
        "Hotel Adlon Kempinski": {"amenity": "Pool", "social": "facebook"},
        "The Savoy": {"amenity": "Pool", "social": "instagram"},
        "Park Hyatt Tokyo": {"amenity": "Pool", "social": "facebook"},
        "Copacabana Palace": {"amenity": "Pool", "social": "instagram"}
    }
    
    hotels_found = 0
    hotels_correct = 0
    
    for record in hotel_records:
        name = record.get('Name')
        if name in expectations:
            hotels_found += 1
            req = expectations[name]
            
            # Check Amenities
            p_amenities = record.get('Amenities')
            has_amenity = isinstance(p_amenities, list) and req['amenity'] in p_amenities
            
            # Check SocialMedia
            p_social = record.get('SocialMedia')
            has_social = isinstance(p_social, dict) and req['social'] in p_social
            
            if has_amenity and has_social:
                score += 8
                hotels_correct += 1
            elif has_amenity or has_social:
                score += 4 # Partial credit
    
    feedback.append(f"Data: {hotels_correct}/5 hotels fully enriched correctly.")

    # ---------------------------------------------------------
    # 3. Verify Output File (40 points)
    # ---------------------------------------------------------
    output_info = result.get('output_file', {})
    
    if output_info.get('exists'):
        # Check timestamp
        if output_info.get('created_during_task'):
            score += 10
            feedback.append("Output: File created during task.")
            
            # Check content
            content_str = output_info.get('content_preview', '')
            try:
                # Parse the content string (which might be double encoded)
                if isinstance(content_str, str):
                    try:
                        content = json.loads(content_str)
                    except json.JSONDecodeError:
                        # Sometimes content is raw string not double encoded
                        content = content_str
                        # Try parsing again if it looks like json
                        if content.strip().startswith('['):
                             content = json.loads(content)
                else:
                    content = content_str

                expected_pool_hotels = {
                    "Hotel Adlon Kempinski",
                    "The Savoy",
                    "Park Hyatt Tokyo",
                    "Copacabana Palace"
                }
                
                if isinstance(content, list):
                    found_names = set(content)
                    intersection = found_names.intersection(expected_pool_hotels)
                    
                    if found_names == expected_pool_hotels:
                        score += 30
                        feedback.append("Output: File content is perfectly correct.")
                    elif len(intersection) >= 2:
                        partial = int(30 * (len(intersection) / 4))
                        score += partial
                        feedback.append(f"Output: File content partially correct ({len(intersection)}/4 matches).")
                    else:
                        feedback.append("Output: File content incorrect.")
                else:
                    feedback.append("Output: File is not a JSON list.")
            except Exception as e:
                feedback.append(f"Output: Error parsing file content: {str(e)}")
        else:
            feedback.append("Output: File exists but timestamp is too old (anti-gaming).")
    else:
        feedback.append("Output: File not found.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }