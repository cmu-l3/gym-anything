#!/usr/bin/env python3
"""
Verifier for import_csv_data task.

Criteria:
1. Airports class exists (10 pts)
2. Properties defined correctly (15 pts)
3. Record count matches CSV (20 records) (15 pts)
4. Data accuracy (Spot check specific fields) (15 pts)
5. IsInCountry edge class exists (10 pts)
6. Edges link Airports to Countries (20 pts)
7. UNIQUE Index exists on IataCode (15 pts)
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_csv_data(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Class Existence
    if result["classes_exist"].get("Airports"):
        score += 10
        feedback_parts.append("Airports class exists.")
    else:
        feedback_parts.append("Airports class MISSING.")

    # 2. Check Properties
    # Expected: IataCode(STRING), Name(STRING), City(STRING), Country(STRING), Latitude(DOUBLE), Longitude(DOUBLE), Altitude(INTEGER)
    props = {p["name"]: p["type"] for p in result.get("airports_properties", [])}
    expected_props = {
        "IataCode": "STRING",
        "Name": "STRING",
        "City": "STRING",
        "Country": "STRING",
        "Latitude": "DOUBLE",
        "Longitude": "DOUBLE",
        "Altitude": "INTEGER"
    }
    
    props_score = 0
    for name, type_ in expected_props.items():
        if name in props:
            if props[name] == type_:
                props_score += 2.15 # Approx to reach 15 total
            else:
                props_score += 1 # Wrong type but exists
    
    # Cap property score at 15
    props_score = min(15, int(round(props_score)))
    score += props_score
    if props_score == 15:
        feedback_parts.append("Properties correct.")
    else:
        feedback_parts.append(f"Properties partial match ({props_score}/15).")

    # 3. Check Record Count
    count = result["counts"].get("airports", 0)
    if count == 20:
        score += 15
        feedback_parts.append("Record count correct (20).")
    elif count > 0:
        score += 5
        feedback_parts.append(f"Record count incorrect ({count}/20).")
    else:
        feedback_parts.append("No records imported.")

    # 4. Check Data Accuracy
    # Samples contains FCO and JFK
    samples = result.get("samples", [])
    accuracy_score = 0
    
    fco = next((s for s in samples if s.get("IataCode") == "FCO"), None)
    if fco:
        # Check Rome coordinates approx
        lat = fco.get("Latitude", 0)
        if 41.0 < lat < 42.0 and fco.get("City") == "Rome":
            accuracy_score += 7.5

    jfk = next((s for s in samples if s.get("IataCode") == "JFK"), None)
    if jfk:
        # Check NY altitude
        alt = jfk.get("Altitude", -999)
        if 0 < alt < 100 and jfk.get("City") == "New York":
            accuracy_score += 7.5
            
    score += int(accuracy_score)
    if accuracy_score == 15:
        feedback_parts.append("Data accuracy verified.")
    else:
        feedback_parts.append("Data accuracy checks failed.")

    # 5. Check Edge Class
    if result["classes_exist"].get("IsInCountry"):
        score += 10
        feedback_parts.append("IsInCountry edge class exists.")
    else:
        feedback_parts.append("IsInCountry edge class MISSING.")

    # 6. Check Edge Connectivity
    # Check total edges and specific link
    edge_count = result["counts"].get("edges", 0)
    fco_links = result.get("fco_connected_countries", [])
    
    edge_score = 0
    if edge_count >= 18: # Allow slight margin but expect 20
        edge_score += 10
    
    if "Italy" in fco_links:
        edge_score += 10
        
    score += edge_score
    feedback_parts.append(f"Edges score: {edge_score}/20 (Count: {edge_count}, FCO->Italy: {'Yes' if 'Italy' in fco_links else 'No'}).")

    # 7. Check Index
    indexes = result.get("airports_indexes", [])
    index_ok = False
    for idx in indexes:
        # Check for unique index on IataCode
        fields = idx.get("fields", [])
        type_ = idx.get("type", "").upper()
        if "IataCode" in fields and "UNIQUE" in type_:
            index_ok = True
            break
    
    if index_ok:
        score += 15
        feedback_parts.append("UNIQUE Index on IataCode verified.")
    else:
        feedback_parts.append("Missing UNIQUE index on IataCode.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }