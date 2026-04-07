#!/usr/bin/env python3
"""
Verifier for Anchor Watch Swing Circle Task.
Verifies geometric accuracy of placed buoys and calculation logic.
"""

import json
import os
import math
import tarfile
import tempfile
import shutil
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_anchor_watch_swing_circle_setup(traj, env_info, task_info):
    """
    Verify the anchor watch scenario creation.
    
    Metrics:
    1. Calculation: Check if report contains correct radius (~646m).
    2. Scenario: Check if files exist.
    3. Geometry: Check if Ownship is at anchor pos.
    4. Geometry: Check if 8 buoys are at correct distance/bearing.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    gt = metadata.get('ground_truth', {})
    expected_radius = gt.get('swing_radius_m', 646.4)
    tolerance = gt.get('tolerance_m', 20)
    
    score = 0
    feedback = []
    
    # Setup temp dir for extraction
    temp_dir = tempfile.mkdtemp()
    tar_path = os.path.join(temp_dir, "task_result.tar.gz")
    
    try:
        # Copy and extract results
        copy_from_env("/tmp/task_result.tar.gz", tar_path)
        with tarfile.open(tar_path, "r:gz") as tar:
            tar.extractall(path=temp_dir)
            
        # Load metadata
        with open(os.path.join(temp_dir, "export_meta.json"), 'r') as f:
            meta = json.load(f)
            
        # --- Criterion 1: Calculation Report (20 pts) ---
        orders_path = os.path.join(temp_dir, "anchor_orders.txt")
        if meta.get("orders_exists") and os.path.exists(orders_path):
            with open(orders_path, 'r') as f:
                content = f.read()
                # Find numbers in the text
                numbers = [float(s) for s in re.findall(r'-?\d+\.?\d*', content)]
                # Check if any number is close to expected radius
                found_val = False
                for num in numbers:
                    if abs(num - expected_radius) <= 5.0: # Tight tolerance for calculation
                        found_val = True
                        break
                
                if found_val:
                    score += 20
                    feedback.append(f"Calculation correct (found value near {expected_radius}m)")
                else:
                    feedback.append(f"Calculation incorrect. Expected ~{expected_radius}m, found {numbers}")
        else:
            feedback.append("Orders file missing")

        # --- Criterion 2: Scenario Structure (10 pts) ---
        if meta.get("scenario_exists") and meta.get("ownship_ini_exists") and meta.get("othership_ini_exists"):
            score += 10
            feedback.append("Scenario files present")
        else:
            feedback.append("Scenario files incomplete")
            # If basic files missing, abort further checks
            return {"passed": False, "score": score, "feedback": "; ".join(feedback)}

        # --- Helper: Simple Haversine ---
        def dist_m(lat1, lon1, lat2, lon2):
            R = 6371000 # Earth radius in meters
            phi1, phi2 = math.radians(lat1), math.radians(lat2)
            dphi = math.radians(lat2 - lat1)
            dlambda = math.radians(lon2 - lon1)
            a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dlambda/2)**2
            c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
            return R * c

        def get_bearing(lat1, lon1, lat2, lon2):
            y = math.sin(math.radians(lon2-lon1)) * math.cos(math.radians(lat2))
            x = math.cos(math.radians(lat1))*math.sin(math.radians(lat2)) - \
                math.sin(math.radians(lat1))*math.cos(math.radians(lat2))*math.cos(math.radians(lon2-lon1))
            brng = math.degrees(math.atan2(y, x))
            return (brng + 360) % 360

        # --- Parse INI files ---
        # Ownship
        own_lat, own_long = None, None
        with open(os.path.join(temp_dir, "ownship.ini"), 'r') as f:
            content = f.read()
            lat_match = re.search(r'InitialLat=([\d\.\-]+)', content)
            long_match = re.search(r'InitialLong=([\d\.\-]+)', content)
            if lat_match and long_match:
                own_lat = float(lat_match.group(1))
                own_long = float(long_match.group(1))

        # Othership
        buoys = []
        with open(os.path.join(temp_dir, "othership.ini"), 'r') as f:
            lines = f.readlines()
            # Simple parser for indexed keys: InitLat(1)=..., InitLong(1)=...
            temp_buoys = {}
            for line in lines:
                lat_m = re.search(r'InitLat\((\d+)\)=([\d\.\-]+)', line)
                long_m = re.search(r'InitLong\((\d+)\)=([\d\.\-]+)', line)
                
                if lat_m:
                    idx = lat_m.group(1)
                    if idx not in temp_buoys: temp_buoys[idx] = {}
                    temp_buoys[idx]['lat'] = float(lat_m.group(2))
                if long_m:
                    idx = long_m.group(1)
                    if idx not in temp_buoys: temp_buoys[idx] = {}
                    temp_buoys[idx]['long'] = float(long_m.group(2))
            
            for idx, data in temp_buoys.items():
                if 'lat' in data and 'long' in data:
                    buoys.append(data)

        # --- Criterion 3: Ownship Position (10 pts) ---
        target_lat = metadata['vessel_data']['anchor_lat']
        target_long = metadata['vessel_data']['anchor_long']
        
        if own_lat is not None and own_long is not None:
            # Check precision to ~10m
            d = dist_m(own_lat, own_long, target_lat, target_long)
            if d < 10:
                score += 10
                feedback.append("Ownship position correct")
            else:
                feedback.append(f"Ownship pos off by {d:.1f}m")
        else:
            feedback.append("Could not parse Ownship position")

        # --- Criterion 4 & 5: Marker Count and Accuracy (60 pts) ---
        marker_score = 0
        
        # Check count
        if len(buoys) == 8:
            marker_score += 10
            feedback.append("Exactly 8 markers found")
        else:
            feedback.append(f"Found {len(buoys)} markers (expected 8)")
            
        # Check geometry
        if own_lat is not None and len(buoys) > 0:
            correct_dist_count = 0
            bearings_found = []
            
            for b in buoys:
                d = dist_m(own_lat, own_long, b['lat'], b['long'])
                # Check radius
                if abs(d - expected_radius) <= tolerance:
                    correct_dist_count += 1
                
                # Check bearing distribution
                brng = get_bearing(own_lat, own_long, b['lat'], b['long'])
                bearings_found.append(brng)
            
            # Score based on correct distances
            if len(buoys) > 0:
                dist_points = (correct_dist_count / len(buoys)) * 40
                marker_score += dist_points
                feedback.append(f"{correct_dist_count}/{len(buoys)} markers at correct distance")
            
            # Check bearing coverage (looking for roughly 45 degree separation)
            # Simplistic check: sort bearings and check gaps, or just check standard deviation?
            # Let's just check if we have representation in 4 quadrants
            quadrants = set()
            for br in bearings_found:
                quadrants.add(int(br / 90))
            if len(quadrants) == 4:
                marker_score += 10
                feedback.append("Markers distributed across all quadrants")
        
        score += int(marker_score)

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": score, "feedback": f"Verification failed with error: {str(e)}"}
    finally:
        shutil.rmtree(temp_dir)
        
    return {
        "passed": score >= 70,
        "score": min(100, score),
        "feedback": "; ".join(feedback)
    }