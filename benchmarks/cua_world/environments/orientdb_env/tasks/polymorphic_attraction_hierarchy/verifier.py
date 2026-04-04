#!/usr/bin/env python3
"""
Verifier for polymorphic_attraction_hierarchy task.

Checks:
1. Schema: 'Museums' class exists and extends 'Attractions'.
2. Properties: Museums has correct properties, Attractions has 'Category'.
3. Data: 5 specific museums exist with correct data.
4. Polymorphism: Museums are retrievable via Attractions query.
5. Output: Report file exists and contains data.
"""

import json
import base64
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_polymorphic_attraction_hierarchy(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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
    
    # === Helper to decode base64 ===
    def decode_json(b64_str):
        try:
            if not b64_str: return {}
            return json.loads(base64.b64decode(b64_str).decode('utf-8'))
        except:
            return {}

    schema_data = decode_json(result.get('schema_b64', ''))
    records_data = decode_json(result.get('data_check', {}).get('records_b64', ''))
    
    # === CRITERION 1: Class Inheritance (15 pts) ===
    museums_class = next((c for c in schema_data.get('classes', []) if c['name'] == 'Museums'), None)
    
    if museums_class:
        super_class = museums_class.get('superClass', '')
        if super_class == 'Attractions':
            score += 15
            feedback.append("Museums class correctly extends Attractions.")
        else:
            score += 5
            feedback.append(f"Museums class exists but extends '{super_class}' instead of Attractions.")
    else:
        feedback.append("Museums class NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)} # Critical fail

    # === CRITERION 2: Properties (10 pts) ===
    # Check Museums properties
    m_props = {p['name']: p['type'] for p in museums_class.get('properties', [])}
    required_props = ['Collection', 'FreeEntry', 'AnnualVisitors']
    missing_props = [p for p in required_props if p not in m_props]
    
    if not missing_props:
        score += 10
        feedback.append("All Museum properties defined.")
    else:
        feedback.append(f"Missing Museum properties: {missing_props}.")

    # === CRITERION 3: Category Property on Parent (15 pts) ===
    attractions_class = next((c for c in schema_data.get('classes', []) if c['name'] == 'Attractions'), None)
    a_props = {p['name']: p['type'] for p in attractions_class.get('properties', [])} if attractions_class else {}
    
    if 'Category' in a_props:
        score += 15
        feedback.append("Category property found on parent Attractions class.")
    elif 'Category' in m_props:
        score += 5
        feedback.append("Category property found on Museums but SHOULD be on parent Attractions.")
    else:
        feedback.append("Category property missing from Attractions.")

    # === CRITERION 4: Data Count & Content (30 pts) ===
    # Expected museums
    expected_names = [
        "Louvre Museum", "British Museum", "Metropolitan Museum of Art", 
        "Uffizi Gallery", "Rijksmuseum"
    ]
    
    actual_records = records_data.get('result', [])
    found_names = [r.get('Name') for r in actual_records]
    
    matches = 0
    for name in expected_names:
        if name in found_names:
            matches += 1
            
    if matches == 5:
        score += 20
        feedback.append("All 5 museum records found.")
    else:
        score += (matches * 3)
        feedback.append(f"Found {matches}/5 museum records.")
        
    # Check Data Accuracy (AnnualVisitors & FreeEntry) for a sample
    # Louvre: ~9.6M, Free: False
    # British: ~5.8M, Free: True
    data_accurate = False
    for r in actual_records:
        if r.get('Name') == 'British Museum':
            if str(r.get('FreeEntry')).lower() == 'true':
                score += 5
                data_accurate = True
        if r.get('Name') == 'Louvre Museum':
            vis = r.get('AnnualVisitors', 0)
            if 9000000 < vis < 10000000:
                score += 5
                
    if data_accurate:
        feedback.append("Data accuracy verified.")

    # === CRITERION 5: Category Value Set (10 pts) ===
    # Check if 'Category' is set to 'museum' (case insensitive)
    category_set_count = sum(1 for r in actual_records if str(r.get('Category', '')).lower() == 'museum')
    
    if category_set_count >= 5:
        score += 10
        feedback.append("Category set to 'museum' for all records.")
    elif category_set_count > 0:
        score += 5
        feedback.append(f"Category set for {category_set_count} records.")
    else:
        feedback.append("Category property not populated correctly.")

    # === CRITERION 6: Output File (10 pts) ===
    file_check = result.get('file_check', {})
    if file_check.get('exists'):
        content = base64.b64decode(file_check.get('content_b64', '')).decode('utf-8', errors='ignore')
        if "Louvre" in content and "British" in content:
            score += 10
            feedback.append("Output file contains correct query results.")
        else:
            score += 5
            feedback.append("Output file exists but may be missing some data.")
    else:
        feedback.append("Output file not found.")

    # === CRITERION 7: Polymorphism (10 pts) ===
    poly_count = result.get('data_check', {}).get('polymorphic_count', 0)
    if poly_count >= 5:
        score += 10
        feedback.append("Polymorphic query verified.")
    
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }