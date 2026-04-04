#!/usr/bin/env python3
"""
Verifier for graph_history_tracking task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_graph_history_tracking(traj, env_info, task_info):
    """
    Verify schema creation and versioned updates for 3 hotels.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result data
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Verify Schema (20 pts)
    schema = data.get('schema', {})
    classes = schema.get('classes', [])
    class_names = [c.get('name') for c in classes]
    
    has_history_class = 'HotelHistory' in class_names
    has_edge_class = 'HasHistory' in class_names
    
    if has_history_class:
        score += 10
        feedback.append("Class 'HotelHistory' exists.")
        
        # Check properties of HotelHistory
        hh_class = next((c for c in classes if c['name'] == 'HotelHistory'), {})
        props = [p['name'] for p in hh_class.get('properties', [])]
        required_props = ['OriginalName', 'OriginalStars', 'OriginalPhone', 'MutationReason']
        missing_props = [p for p in required_props if p not in props]
        if not missing_props:
            score += 5
            feedback.append("All properties found on HotelHistory.")
        else:
            feedback.append(f"Missing properties on HotelHistory: {missing_props}")
    else:
        feedback.append("Class 'HotelHistory' NOT found.")

    if has_edge_class:
        score += 5
        feedback.append("Edge class 'HasHistory' exists.")
    else:
        feedback.append("Edge class 'HasHistory' NOT found.")

    # Parse Data
    hotels_result = data.get('hotels', {}).get('result', [])
    history_result = data.get('history', {}).get('result', [])
    
    # Helper to find hotel by name (handling rename for Adlon)
    def get_hotel(name_candidates):
        for h in hotels_result:
            if h.get('Name') in name_candidates:
                return h
        return None

    # Helper to get history record linked to a hotel
    def get_linked_history(hotel_record):
        if not hotel_record: return None
        edges = hotel_record.get('HistoryEdges', [])
        if not edges: return None
        # Edges might be list of RIDs. We need to find the history record with that RID (incoming)
        # But wait, OrientDB SQL `out('HasHistory')` returns the vertices if connected, or RIDs.
        # The export script used `out('HasHistory')` which typically returns the RIDs of the target vertices.
        # We match these RIDs against @rid in history_result.
        
        linked_rids = edges
        if isinstance(linked_rids, str): linked_rids = [linked_rids] # single edge case
        
        for hist in history_result:
            if hist.get('@rid') in linked_rids:
                return hist
        return None

    # 2. Verify Update 1: Hotel Artemide (25 pts)
    # Target: Name='Hotel Artemide', Stars=5 (was 4). History: Stars=4, Reason='Annual Review'
    artemide = get_hotel(['Hotel Artemide'])
    if artemide:
        if artemide.get('Stars') == 5:
            score += 10
            feedback.append("Artemide: Live stars updated to 5.")
        else:
            feedback.append(f"Artemide: Live stars is {artemide.get('Stars')}, expected 5.")
            
        hist = get_linked_history(artemide)
        if hist:
            score += 5 # Linked
            valid_hist = (
                hist.get('OriginalName') == 'Hotel Artemide' and
                hist.get('OriginalStars') == 4 and
                hist.get('MutationReason') == 'Annual Review'
            )
            if valid_hist:
                score += 10
                feedback.append("Artemide: History record correct.")
            else:
                feedback.append(f"Artemide: History data mismatch. Got: {hist}")
        else:
            feedback.append("Artemide: No history record linked.")
    else:
        feedback.append("Artemide: Hotel record not found.")

    # 3. Verify Update 2: The Savoy (25 pts)
    # Target: Phone='+44-20-9999-8888'. History: Phone='+44-20-7836-4343', Reason='Correction'
    savoy = get_hotel(['The Savoy'])
    if savoy:
        if savoy.get('Phone') == '+44-20-9999-8888':
            score += 10
            feedback.append("Savoy: Live phone updated.")
        else:
            feedback.append(f"Savoy: Live phone mismatch. Got {savoy.get('Phone')}")
            
        hist = get_linked_history(savoy)
        if hist:
            score += 5
            valid_hist = (
                hist.get('OriginalName') == 'The Savoy' and
                hist.get('OriginalPhone') == '+44-20-7836-4343' and
                hist.get('MutationReason') == 'Correction'
            )
            if valid_hist:
                score += 10
                feedback.append("Savoy: History record correct.")
            else:
                feedback.append("Savoy: History data mismatch.")
        else:
            feedback.append("Savoy: No history record linked.")
    else:
        feedback.append("Savoy: Hotel record not found.")

    # 4. Verify Update 3: Adlon Kempinski (25 pts)
    # Target: Name='Adlon Kempinski Berlin'. History: Name='Hotel Adlon Kempinski', Reason='Rebranding'
    adlon = get_hotel(['Adlon Kempinski Berlin', 'Hotel Adlon Kempinski'])
    if adlon:
        if adlon.get('Name') == 'Adlon Kempinski Berlin':
            score += 10
            feedback.append("Adlon: Live name updated.")
        else:
            feedback.append(f"Adlon: Live name not updated. Got '{adlon.get('Name')}'")
            
        hist = get_linked_history(adlon)
        if hist:
            score += 5
            valid_hist = (
                hist.get('OriginalName') == 'Hotel Adlon Kempinski' and
                hist.get('MutationReason') == 'Rebranding'
            )
            if valid_hist:
                score += 10
                feedback.append("Adlon: History record correct.")
            else:
                feedback.append("Adlon: History data mismatch.")
        else:
            feedback.append("Adlon: No history record linked.")
    else:
        feedback.append("Adlon: Hotel record not found.")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }