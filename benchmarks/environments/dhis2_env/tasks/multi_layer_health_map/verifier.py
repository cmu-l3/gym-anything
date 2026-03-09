#!/usr/bin/env python3
"""
Verifier for multi_layer_health_map task.

Scoring (100 points total):
1. Map saved in DHIS2 (25 pts) [MANDATORY]
2. Map name relevant (contains keywords) (10 pts)
3. Map has >= 2 layers (20 pts)
4. Map has a thematic layer (15 pts)
5. Map data is immunization related (10 pts)
6. Image exported to Downloads (20 pts)

Pass threshold: 60 points
Mandatory: Map saved
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_multi_layer_health_map(traj, env_info, task_info):
    """Verify DHIS2 map creation and export."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result file
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/task_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        try:
            with open(temp_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}
        finally:
            if os.path.exists(temp_path):
                os.unlink(temp_path)

        score = 0
        feedback_parts = []
        
        map_data = result.get('map_analysis', {})
        dl_data = result.get('download_analysis', {})

        # 1. Map Saved (Mandatory)
        if not map_data.get('map_found', False):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "No new map found in DHIS2. You must save the map."
            }
        
        score += 25
        feedback_parts.append("Map saved (+25)")
        
        # 2. Map Name
        map_name = map_data.get('map_name', '').lower()
        keywords = task_info.get('metadata', {}).get('required_map_name_keywords', ['penta', 'immunization'])
        if any(k in map_name for k in keywords):
            score += 10
            feedback_parts.append("Map name correct (+10)")
        else:
            feedback_parts.append(f"Map name '{map_name}' missing keywords")

        # 3. Layer Count
        layer_count = map_data.get('layer_count', 0)
        if layer_count >= 2:
            score += 20
            feedback_parts.append(f"Map has {layer_count} layers (+20)")
        else:
            feedback_parts.append(f"Map has only {layer_count} layer(s) (need 2+)")

        # 4. Thematic Layer
        if map_data.get('has_thematic', False):
            score += 15
            feedback_parts.append("Thematic layer found (+15)")
        else:
            feedback_parts.append("No thematic layer found")

        # 5. Data Relevance
        if map_data.get('has_imm_data', False):
            score += 10
            feedback_parts.append("Immunization data used (+10)")
        else:
            feedback_parts.append("Could not confirm immunization data in map")

        # 6. Download
        if dl_data.get('download_found', False):
            score += 20
            feedback_parts.append(f"Image exported: {dl_data.get('filename')} (+20)")
        else:
            feedback_parts.append("No image download found")

        passed = score >= 60
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}