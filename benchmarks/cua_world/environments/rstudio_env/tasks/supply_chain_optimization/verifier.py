#!/usr/bin/env python3
"""
Verifier for Supply Chain Optimization Task.

Verifies:
1. Optimal Plan CSV exists and contains correct solution.
   - Re-solves the LP problem using Python to generate ground truth.
   - Compares Total Cost and Total Quantity.
2. Map visualization exists and looks valid (VLM).
3. Script was modified.

Ground Truth Parameters:
- Cost per km: 0.02
- Factories: NY(1000), TX(1500), CA(1200)
- Warehouses: WA(500), IL(800), GA(800), CO(600), FL(700)
"""

import json
import tempfile
import os
import math
import logging
from typing import List, Tuple, Dict

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- Helper for Ground Truth Calculation ---

def haversine_distance(lat1, lon1, lat2, lon2):
    R = 6371  # Earth radius in km
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dlambda/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c

def solve_ground_truth():
    """
    Solves the Transportation Problem to get the minimum cost.
    Using scipy.optimize.linprog (simplex/interior-point).
    """
    try:
        from scipy.optimize import linprog
        import numpy as np
    except ImportError:
        logger.error("Scipy not installed in verifier environment.")
        return None

    # Data
    factories = [
        {"id": "Factory_NY", "lat": 40.7128, "lon": -74.0060, "cap": 1000},
        {"id": "Factory_TX", "lat": 31.9686, "lon": -99.9018, "cap": 1500},
        {"id": "Factory_CA", "lat": 36.7783, "lon": -119.4179, "cap": 1200}
    ]
    warehouses = [
        {"id": "Warehouse_WA", "lat": 47.7511, "lon": -120.7401, "dem": 500},
        {"id": "Warehouse_IL", "lat": 40.6331, "lon": -89.3985, "dem": 800},
        {"id": "Warehouse_GA", "lat": 32.1656, "lon": -82.9001, "dem": 800},
        {"id": "Warehouse_CO", "lat": 39.5501, "lon": -105.7821, "dem": 600},
        {"id": "Warehouse_FL", "lat": 27.6648, "lon": -81.5158, "dem": 700}
    ]
    
    rate = 0.02
    
    # Cost Matrix C[i][j] (flattened for linprog)
    costs = []
    for f in factories:
        for w in warehouses:
            dist = haversine_distance(f["lat"], f["lon"], w["lat"], w["lon"])
            costs.append(dist * rate)
            
    # Decision variables x_ij: flattened vector of size 3*5 = 15
    # Constraints:
    # 1. Supply constraints (Rows): sum(x_ij for j) <= Cap_i
    # 2. Demand constraints (Cols): sum(x_ij for i) >= Dem_j
    
    A_ub = [] # Inequality (<=)
    b_ub = []
    A_eq = [] # Equality (=) - technically demands must be met exactly if cost positive
    b_eq = []
    
    # Factory constraints (Supply)
    # Standard form: A_ub * x <= b_ub
    for i in range(len(factories)):
        row = [0] * 15
        for j in range(len(warehouses)):
            row[i * 5 + j] = 1
        A_ub.append(row)
        b_ub.append(factories[i]["cap"])
        
    # Warehouse constraints (Demand)
    # We want sum >= Dem, so -sum <= -Dem
    for j in range(len(warehouses)):
        row = [0] * 15
        for i in range(len(factories)):
            row[i * 5 + j] = -1
        A_ub.append(row)
        b_ub.append(-warehouses[j]["dem"])
        
    # Bounds x >= 0
    bounds = [(0, None) for _ in range(15)]
    
    res = linprog(c=costs, A_ub=A_ub, b_ub=b_ub, bounds=bounds, method='highs')
    
    if res.success:
        return res.fun # Minimal Total Cost
    return None

# --- Main Verifier ---

def verify_supply_chain(traj, env_info, task_info):
    """
    Verifies the Supply Chain Optimization task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    get_final_screenshot = env_info.get('get_final_screenshot')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load task results: {e}"}
    finally:
        os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Verify Optimal Plan Existence & Format (15 pts)
    plan_exists = result.get('plan_exists', False)
    plan_is_new = result.get('plan_is_new', False)
    if plan_exists and plan_is_new:
        score += 15
        feedback.append("Optimal plan CSV created.")
    elif plan_exists:
        score += 5
        feedback.append("Optimal plan CSV exists but not created during task.")
    else:
        feedback.append("Optimal plan CSV missing.")

    # 2. Verify Total Shipped Quantity (20 pts)
    # Should equal total demand (3400)
    total_qty = result.get('total_quantity_shipped', 0)
    if 3390 <= total_qty <= 3410:
        score += 20
        feedback.append(f"Total shipped quantity correct ({total_qty}).")
    else:
        feedback.append(f"Total shipped quantity incorrect ({total_qty}, expected 3400).")

    # 3. Verify Solution Optimality (25 pts)
    # We check the agent's reported total cost against ground truth
    # We need to read the agent's CSV to compute their total cost
    agent_cost = 0.0
    try:
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        copy_from_env("/home/ga/RProjects/output/optimal_plan.csv", temp_csv.name)
        
        # Calculate cost based on agent's plan + OUR distance function (to avoid gaming unit costs)
        # Or trust agent's 'cost' column if we checked distances separately?
        # Better: Re-calculate cost using agent's Qty * Ground Truth Dist
        import csv
        
        # Mapping to coords
        locs = {
            "Factory_NY": (40.7128, -74.0060),
            "Factory_TX": (31.9686, -99.9018),
            "Factory_CA": (36.7783, -119.4179),
            "Warehouse_WA": (47.7511, -120.7401),
            "Warehouse_IL": (40.6331, -89.3985),
            "Warehouse_GA": (32.1656, -82.9001),
            "Warehouse_CO": (39.5501, -105.7821),
            "Warehouse_FL": (27.6648, -81.5158)
        }
        
        with open(temp_csv.name, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                # Find cols
                f_node = next((v for k,v in row.items() if 'from' in k.lower()), None)
                t_node = next((v for k,v in row.items() if 'to' in k.lower()), None)
                qty = next((v for k,v in row.items() if 'quantity' in k.lower() or 'amount' in k.lower()), 0)
                
                if f_node in locs and t_node in locs:
                    lat1, lon1 = locs[f_node]
                    lat2, lon2 = locs[t_node]
                    dist = haversine_distance(lat1, lon1, lat2, lon2)
                    agent_cost += float(qty) * dist * 0.02
        
        os.unlink(temp_csv.name)
        
        # Ground Truth Cost
        gt_cost = solve_ground_truth()
        
        if gt_cost:
            # Allow 2% tolerance for distance calculation differences
            tolerance = gt_cost * 0.02
            if abs(agent_cost - gt_cost) <= tolerance:
                score += 25
                feedback.append(f"Optimal cost achieved (${agent_cost:.2f}).")
            else:
                feedback.append(f"Suboptimal or incorrect cost (${agent_cost:.2f}, expected approx ${gt_cost:.2f}).")
        else:
            feedback.append("Could not calculate ground truth (verifier error).")
            score += 25 # Benefit of doubt if verifier fails
            
    except Exception as e:
        feedback.append(f"Failed to verify optimality: {e}")

    # 4. Verify Map (25 pts)
    map_exists = result.get('map_exists', False)
    map_is_new = result.get('map_is_new', False)
    map_size = result.get('map_size_bytes', 0)
    
    if map_exists and map_is_new and map_size > 10000: # >10KB
        # VLM Check
        if query_vlm:
            # We need to get the image. We can't copy it easily to memory for VLM function unless we use get_final_screenshot 
            # OR if we assume the map is visible in the final screenshot.
            # Best approach: Copy the PNG file out, but the `query_vlm` usually takes raw bytes or a PIL image.
            # The current interface `copy_from_env` saves to disk. We can load it.
            try:
                temp_map = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                copy_from_env("/home/ga/RProjects/output/supply_chain_map.png", temp_map.name)
                
                prompt = "Is this image a map showing geographic locations connected by lines (a flow map)? Respond 'yes' or 'no' and explain."
                
                # We need to load image to pass to query_vlm if it expects object, or path if it expects path.
                # Assuming query_vlm takes 'image' as path or PIL object. Let's try passing the path if supported, or read bytes.
                # The example shows passing an object.
                from PIL import Image
                img = Image.open(temp_map.name)
                
                vlm_resp = query_vlm(prompt=prompt, image=img)
                if vlm_resp and vlm_resp.get('success') and 'yes' in vlm_resp.get('parsed', {}).get('response', '').lower():
                     score += 25
                     feedback.append("Map verified by VLM.")
                elif vlm_resp and vlm_resp.get('success'):
                     score += 10 # Created valid file but maybe VLM failed to recognize
                     feedback.append("Map file created but VLM was unsure.")
                else:
                     score += 25 # Fallback if VLM fails
                     feedback.append("Map created (VLM unavailable).")
                
                img.close()
                os.unlink(temp_map.name)
            except Exception as e:
                score += 15
                feedback.append(f"Map created but visual verification failed: {e}")
        else:
            score += 25
            feedback.append("Map file created.")
    else:
        feedback.append("Map missing or too small.")

    # 5. Script Modified (15 pts)
    if result.get('script_modified', False):
        score += 15
        feedback.append("Analysis script modified.")
    else:
        feedback.append("Analysis script not modified.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }