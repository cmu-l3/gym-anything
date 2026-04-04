#!/usr/bin/env python3
"""
Verifier for spatial_migration_and_cleanup task.

Checks:
1. Hotels class has 'Location' property of type 'OPoint'.
2. Hotels class has a SPATIAL index on 'Location'.
3. All Hotels records have correctly standardized 'City' names (Title Case).
4. All Hotels records have 'Location' populated matching 'Latitude'/'Longitude'.
"""

import json
import tempfile
import os
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def calculate_distance(lat1, lon1, lat2, lon2):
    """Euclidean distance for quick check (sufficient for this scale/check)."""
    return math.sqrt((lat1 - lat2)**2 + (lon1 - lon2)**2)

def verify_spatial_migration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result artifact
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Export failed: {result['error']}"}

    score = 0
    feedback_parts = []
    
    schema = result.get('schema', {})
    data = result.get('data', [])
    
    # ---------------------------------------------------------
    # CHECK 1: Schema Verification (Property & Index) - 40 pts
    # ---------------------------------------------------------
    classes = schema.get('classes', [])
    hotels_class = next((c for c in classes if c['name'] == 'Hotels'), None)
    
    if not hotels_class:
        return {"passed": False, "score": 0, "feedback": "Hotels class not found in database"}

    # Check Property
    properties = {p['name']: p for p in hotels_class.get('properties', [])}
    location_prop = properties.get('Location')
    
    prop_ok = False
    if location_prop:
        if location_prop.get('type') == 'OPoint':
            score += 20
            prop_ok = True
            feedback_parts.append("Location property created (OPoint)")
        else:
            feedback_parts.append(f"Location property exists but type is {location_prop.get('type')} (expected OPoint)")
    else:
        feedback_parts.append("Location property missing")

    # Check Index
    indexes = hotels_class.get('indexes', [])
    spatial_index = next((idx for idx in indexes if idx.get('type') == 'SPATIAL' and 'Location' in idx.get('fields', [])), None)
    
    if not spatial_index:
        # Fallback check: sometimes fields are stored differently or name implies it
        spatial_index = next((idx for idx in indexes if idx.get('type') == 'SPATIAL' and ('Hotels.Location' in idx.get('name', ''))), None)

    if spatial_index:
        score += 20
        feedback_parts.append("SPATIAL index found")
    else:
        feedback_parts.append("SPATIAL index missing on Location")

    # ---------------------------------------------------------
    # CHECK 2: Data Hygiene (City Names) - 20 pts
    # ---------------------------------------------------------
    # We expect standard Title Case.
    # Specifically check the ones we corrupted: rome->Rome, BERLIN->Berlin, paris->Paris
    bad_cities = []
    for row in data:
        city = row.get('City', '')
        if not city: 
            continue
        # Simple check: is the first letter upper and rest lower? (Simplified for single word cities)
        # Or better, just check specifically for the errors we introduced
        if city in ['rome', 'BERLIN', 'paris', 'ROME', 'berlin', 'PARIS']:
            bad_cities.append(city)
    
    if not bad_cities and len(data) > 0:
        score += 20
        feedback_parts.append("City names standardized")
    else:
        feedback_parts.append(f"City names still inconsistent (found: {', '.join(list(set(bad_cities))[:3])}...)")

    # ---------------------------------------------------------
    # CHECK 3: Data Migration (Coordinates) - 40 pts
    # ---------------------------------------------------------
    migrated_count = 0
    correct_count = 0
    total_rows = len(data)
    
    for row in data:
        lat = row.get('Latitude')
        lon = row.get('Longitude')
        loc = row.get('Location')
        
        if lat is None or lon is None:
            continue
            
        # Location should be a dictionary/map in JSON with 'coordinates': [lon, lat]
        # OrientDB OPoint JSON format: {"@type": "d", "@class": "OPoint", "coordinates": [lon, lat]}
        # Or sometimes just the coordinates list if simplified
        
        if not loc:
            continue
            
        migrated_count += 1
        
        coords = None
        if isinstance(loc, dict):
            coords = loc.get('coordinates')
        elif isinstance(loc, list):
            # unlikely for OPoint but possible in some return formats
            coords = loc 
            
        if coords and len(coords) == 2:
            # coords[0] is Longitude, coords[1] is Latitude
            d_lon = abs(coords[0] - lon)
            d_lat = abs(coords[1] - lat)
            
            # Tolerance 0.001
            if d_lon < 0.001 and d_lat < 0.001:
                correct_count += 1
    
    if total_rows > 0:
        # Partial credit logic
        if migrated_count == total_rows:
            if correct_count == total_rows:
                score += 40
                feedback_parts.append("All location data migrated correctly")
            else:
                score += 20
                feedback_parts.append(f"Locations created but values mismatch ({correct_count}/{total_rows} correct)")
        elif migrated_count > 0:
            score += 10
            feedback_parts.append(f"Partial migration ({migrated_count}/{total_rows})")
        else:
            feedback_parts.append("No Location data found in records")
    else:
        feedback_parts.append("No data records found to verify")

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }