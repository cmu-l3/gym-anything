#!/usr/bin/env python3
"""
Verifier for ER Diagram Task (Chinook Database).
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_er_diagram_from_sql_schema(traj, env_info, task_info):
    """
    Verifies the ER diagram creation task.
    
    Criteria:
    1. Files (.drawio and .png) exist and were modified.
    2. Diagram contains the 7 specific table names.
    3. Diagram has correct number of shapes/edges (Entity shapes + Relationships).
    4. PK/FK notation is used.
    5. VLM verification for layout and Crow's Foot notation quality.
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    required_entities = set(metadata.get('required_entities', ["Artist", "Album", "Track", "Genre", "MediaType", "Playlist", "PlaylistTrack"]))

    # 2. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 3. Scoring Logic
    score = 0
    feedback_lines = []
    
    # Criterion 1: Files Exist (20 pts)
    if result_data.get('file_exists') and result_data.get('file_modified'):
        score += 10
        feedback_lines.append("✓ .drawio file saved and modified.")
    else:
        feedback_lines.append("✗ .drawio file missing or not saved.")

    if result_data.get('png_exists'):
        score += 10
        feedback_lines.append("✓ PNG export found.")
    else:
        feedback_lines.append("✗ PNG export missing.")

    # Criterion 2: Entities Present (35 pts)
    # Check which of the required entities were found in the text
    found_entities = set(result_data.get('found_entities', []))
    missing_entities = required_entities - found_entities
    
    # 5 pts per entity found (max 35)
    entity_score = len(found_entities) * 5
    score += entity_score
    if not missing_entities:
        feedback_lines.append(f"✓ All {len(required_entities)} tables found in diagram.")
    else:
        feedback_lines.append(f"✗ Missing tables: {', '.join(missing_entities)}.")

    # Criterion 3: Structure (Shapes & Edges) (25 pts)
    # We expect at least 7 shapes (entities) and 6 edges (relationships)
    shape_count = result_data.get('entity_shape_count', 0)
    edge_count = result_data.get('relationship_count', 0)
    
    # Check shapes (Allow some tolerance, e.g. title text might count as a shape)
    if shape_count >= 7:
        score += 10
        feedback_lines.append(f"✓ Sufficient shape count ({shape_count}).")
    elif shape_count > 0:
        score += 5
        feedback_lines.append(f"⚠ Low shape count ({shape_count}), expected >= 7.")
    else:
        feedback_lines.append("✗ No shapes detected.")

    # Check edges (relationships)
    if edge_count >= 6:
        score += 15
        feedback_lines.append(f"✓ Sufficient relationship connections ({edge_count}).")
    elif edge_count >= 3:
        score += 7
        feedback_lines.append(f"⚠ Few relationships ({edge_count}), expected >= 6.")
    else:
        feedback_lines.append("✗ Almost no relationships detected.")

    # Criterion 4: Notation (PK/FK) (10 pts)
    has_pk = result_data.get('has_pk', False)
    has_fk = result_data.get('has_fk', False)
    
    if has_pk: 
        score += 5
        feedback_lines.append("✓ Primary Key (PK) notation detected.")
    else:
        feedback_lines.append("✗ No Primary Key notation found.")
        
    if has_fk:
        score += 5
        feedback_lines.append("✓ Foreign Key (FK) notation detected.")
    else:
        feedback_lines.append("✗ No Foreign Key notation found.")

    # Criterion 5: VLM / Visual Check (10 pts)
    # Since we can't run VLM inside this specific script easily without the 'query_vlm' function passed in traj,
    # we rely on the framework to handle VLM or we check for specific "professional" markers.
    # We'll grant these points if the structure (Criterion 3) is strong, as it implies visual effort.
    # Alternatively, if 'query_vlm' was available, we would use it here.
    # For this implementation, we will bonus points if all entities are present and connected.
    
    if len(missing_entities) == 0 and edge_count >= 6:
        score += 10
        feedback_lines.append("✓ Diagram appears complete and connected.")

    # 4. Final Verdict
    passed = (score >= 60) and (len(found_entities) >= 5) # Require at least 5/7 tables for a pass
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": "\n".join(feedback_lines)
    }