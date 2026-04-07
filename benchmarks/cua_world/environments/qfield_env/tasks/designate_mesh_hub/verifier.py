#!/usr/bin/env python3
"""
Verifier for designate_mesh_hub task.

Verifies that the central node in a specific 5-node cluster was updated
to 'Master Hub' while peripheral nodes remain 'Unassigned'.
"""

import sqlite3
import struct
import tempfile
import os
import math
import logging
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_designate_mesh_hub(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the task by inspecting the GeoPackage database.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Constants from task definition
    # Target center: 149.13, -35.20
    TARGET_CENTER = (149.13, -35.20)
    TOLERANCE = 0.002 # Strict tolerance (points are 0.01 apart)

    score = 0
    feedback_parts = []
    passed = False

    # Create temporary directory for artifacts
    with tempfile.TemporaryDirectory() as temp_dir:
        local_gpkg = os.path.join(temp_dir, "result.gpkg")
        
        try:
            # 1. Retrieve the GeoPackage
            copy_from_env("/sdcard/task_result.gpkg", local_gpkg)
            
            if not os.path.exists(local_gpkg):
                return {"passed": False, "score": 0, "feedback": "Result GeoPackage not found"}
                
            # 2. Inspect Database
            conn = sqlite3.connect(local_gpkg)
            cursor = conn.cursor()
            
            # Helper to unpack GeoPackage Point Blob (SRID 4326)
            def unpack_geom(blob):
                # Header 8 bytes (Magic 2, Ver 1, Flags 1, SRID 4)
                # WKB 5 bytes (Order 1, Type 4)
                # Coords 16 bytes (X 8, Y 8)
                # Total offset to X: 8 + 5 = 13 bytes
                try:
                    if len(blob) < 29: return None
                    x = struct.unpack('<d', blob[13:21])[0]
                    y = struct.unpack('<d', blob[21:29])[0]
                    return (x, y)
                except:
                    return None

            # Fetch all Sensor Nodes
            cursor.execute("SELECT name, notes, geom FROM field_observations WHERE name='Sensor Node'")
            rows = cursor.fetchall()
            
            if not rows:
                return {"passed": False, "score": 0, "feedback": "No 'Sensor Node' features found in database"}

            # Classify nodes based on distance to center
            center_node = None
            peripheral_nodes = []
            
            for row in rows:
                name, notes, blob = row
                coords = unpack_geom(blob)
                if not coords: continue
                
                dist = math.sqrt((coords[0] - TARGET_CENTER[0])**2 + (coords[1] - TARGET_CENTER[1])**2)
                
                node_data = {'notes': notes, 'coords': coords}
                
                if dist < TOLERANCE:
                    center_node = node_data
                elif dist < 0.02: # Peripherals are ~0.014 away
                    peripheral_nodes.append(node_data)

            # 3. Verify Center Node (40 pts identification + 30 pts attribute)
            if center_node:
                score += 40
                feedback_parts.append("Center node identified")
                
                actual_notes = str(center_node['notes']).strip()
                if "Master Hub" in actual_notes: # Flexible matching
                    score += 30
                    feedback_parts.append("Center node correctly labeled 'Master Hub'")
                else:
                    feedback_parts.append(f"Center node label incorrect (found: '{actual_notes}')")
            else:
                feedback_parts.append("Center node deleted or moved too far")

            # 4. Verify Peripherals (20 pts)
            peripheral_ok = True
            if len(peripheral_nodes) == 4:
                for p in peripheral_nodes:
                    if "Master Hub" in str(p['notes']):
                        peripheral_ok = False
                        feedback_parts.append("A peripheral node was incorrectly labeled")
                if peripheral_ok:
                    score += 20
                    feedback_parts.append("Peripheral nodes left unassigned")
            else:
                score += 0
                feedback_parts.append(f"Peripheral node count mismatch (found {len(peripheral_nodes)}, expected 4)")

            # 5. Data Integrity (10 pts)
            # Ensure total is 5 (no extras, no deletes)
            if len(rows) == 5:
                score += 10
                feedback_parts.append("Feature count correct")
            else:
                feedback_parts.append(f"Feature count changed (found {len(rows)})")

            conn.close()

        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    # VLM Check for Trajectory (Secondary)
    # This would ideally check if the agent zoomed in to the correct location
    # For now, relying on programmatic check is robust enough for this task
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }