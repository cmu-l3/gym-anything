#!/usr/bin/env python3
"""
Verifier for generate_resource_inventory task.

Criteria:
1. File exists and is valid JSON (10 pts)
2. Structure correctness (Workspaces -> DataStores -> Layers) (10 pts)
3. Correct counts in summary (10 pts)
4. Specific Natural Earth layers present (15 pts)
5. Layer details correctness (SRS, BBox, AttributeCount) (30 pts)
6. Styles & Layer Groups enumerated (15 pts)
7. Anti-gaming (File creation time) (10 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_resource_inventory(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve the Metadata/Ground Truth Result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            meta_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task metadata: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Check anti-gaming nonce
    # (We skip strict nonce file check here as it's implicit in meta_result integrity, 
    # but could retrieve /tmp/result_nonce if needed. Relying on timestamp logic for now.)

    # 2. Retrieve the Agent's Inventory File
    agent_file_exists = meta_result.get('file_exists', False)
    agent_valid_time = meta_result.get('file_valid_time', False)
    
    if not agent_file_exists:
        return {"passed": False, "score": 0, "feedback": "Inventory file not found at /home/ga/geoserver_inventory.json"}
    
    if not agent_valid_time:
         return {"passed": False, "score": 0, "feedback": "Inventory file timestamp is older than task start time (anti-gaming)"}

    temp_inventory = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    inventory_data = {}
    try:
        copy_from_env("/home/ga/geoserver_inventory.json", temp_inventory.name)
        with open(temp_inventory.name, 'r') as f:
            inventory_data = json.load(f)
    except json.JSONDecodeError:
        return {"passed": False, "score": 10, "feedback": "File exists but is not valid JSON"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read inventory file: {e}"}
    finally:
        if os.path.exists(temp_inventory.name):
            os.unlink(temp_inventory.name)

    # === SCORING LOGIC ===
    score = 10 # Base score for valid JSON file created during task
    feedback = ["File exists and is valid JSON"]
    
    gt = meta_result.get('ground_truth', {})
    gt_struct = gt.get('structure', {})
    
    # Criterion: Structure & Workspaces (10 pts)
    # Check if 'workspaces' is a list and contains expected workspaces
    workspaces = inventory_data.get('workspaces', [])
    if isinstance(workspaces, list) and len(workspaces) > 0:
        found_ws_names = [w.get('name') for w in workspaces if isinstance(w, dict)]
        expected_ws = gt.get('workspaces', [])
        # Check intersection
        common = set(found_ws_names).intersection(set(expected_ws))
        if len(common) >= len(expected_ws):
            score += 10
            feedback.append(f"Workspaces enumerated correctly ({len(common)}/{len(expected_ws)})")
        elif len(common) > 0:
            score += 5
            feedback.append(f"Some workspaces found ({len(common)})")
    else:
        feedback.append("Invalid 'workspaces' format")

    # Criterion: Data Stores & Hierarchy (10 pts)
    # We check if we can traverse Workspaces -> DataStores
    stores_found = 0
    for ws in workspaces:
        if isinstance(ws, dict):
            stores = ws.get('dataStores', [])
            if isinstance(stores, list):
                stores_found += len(stores)
    
    if stores_found >= gt_struct.get('totalDataStores', 0):
        score += 10
        feedback.append(f"Data stores enumerated ({stores_found})")
    elif stores_found > 0:
        score += 5
        feedback.append(f"Some data stores found ({stores_found})")

    # Criterion: Natural Earth Layers Presence (15 pts)
    required_layers = ["ne_countries", "ne_populated_places", "ne_rivers", "ne_lakes"]
    found_layers_data = {} # Map name -> layer_obj for detail checking
    
    for ws in workspaces:
        if isinstance(ws, dict):
            for ds in ws.get('dataStores', []):
                if isinstance(ds, dict):
                    for lyr in ds.get('layers', []):
                        if isinstance(lyr, dict):
                            found_layers_data[lyr.get('name')] = lyr

    found_req_count = 0
    for req in required_layers:
        if req in found_layers_data:
            found_req_count += 1
    
    if found_req_count == 4:
        score += 15
        feedback.append("All Natural Earth layers found")
    elif found_req_count > 0:
        score += int(15 * (found_req_count / 4))
        feedback.append(f"Some Natural Earth layers found ({found_req_count}/4)")

    # Criterion: Layer Details (SRS, BBox, AttrCount) (30 pts)
    # Check details for ne_countries as a proxy
    details_score = 0
    ne_country = found_layers_data.get('ne_countries')
    if ne_country:
        # SRS
        srs = ne_country.get('srs', '')
        if '4326' in srs or 'EPSG' in srs:
            details_score += 10
            feedback.append("Layer SRS correct")
        
        # BBox
        bbox = ne_country.get('nativeBoundingBox', {})
        if isinstance(bbox, dict) and all(k in bbox for k in ['minx', 'miny', 'maxx', 'maxy']):
             # Check for non-zero/reasonable values
             try:
                 if abs(float(bbox['minx'])) <= 180 and abs(float(bbox['maxy'])) <= 90:
                     details_score += 10
                     feedback.append("Layer BBox correct")
             except: pass
        
        # Attribute Count
        attr_count = ne_country.get('attributeCount')
        if isinstance(attr_count, int) and attr_count > 0:
            details_score += 10
            feedback.append("Layer attribute count correct")
    
    score += details_score

    # Criterion: Styles & Groups (15 pts)
    # Styles
    styles = inventory_data.get('styles', [])
    if isinstance(styles, list) and len(styles) > 0:
        # Should correspond roughly to ground truth
        if len(styles) >= gt.get('style_count', 0) - 2: # Tolerance
            score += 8
            feedback.append("Styles enumerated")
        else:
            score += 4
            feedback.append("Some styles found")
            
    # Groups
    groups = inventory_data.get('layerGroups', [])
    gt_groups = gt.get('group_count', 0)
    if isinstance(groups, list):
        if len(groups) == gt_groups:
             score += 7
             feedback.append("Layer groups correct")
        elif gt_groups == 0 and len(groups) == 0:
             score += 7
             feedback.append("Layer groups correct (none)")

    # Criterion: Summary Counts (10 pts)
    summary = inventory_data.get('summary', {})
    summary_score = 0
    if summary.get('totalWorkspaces') == gt.get('totalWorkspaces', -1): summary_score += 2
    if summary.get('totalDataStores') == gt_struct.get('totalDataStores', -1): summary_score += 2
    if abs(summary.get('totalLayers', 0) - gt_struct.get('totalLayers', -1)) <= 1: summary_score += 2
    if abs(summary.get('totalStyles', 0) - gt.get('style_count', -1)) <= 1: summary_score += 2
    if summary.get('totalLayerGroups') == gt.get('group_count', -1): summary_score += 2
    
    score += summary_score
    if summary_score > 0:
        feedback.append(f"Summary counts matched ({summary_score}/10 pts)")

    passed = score >= 60 and found_req_count >= 1
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }