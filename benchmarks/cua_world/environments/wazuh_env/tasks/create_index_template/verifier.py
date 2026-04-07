#!/usr/bin/env python3
"""
Verifier for create_index_template task.
Verifies that the OpenSearch index template was created with correct settings via API query.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_index_template(traj, env_info, task_info):
    """
    Verify the index template creation.
    
    Criteria:
    1. Template exists in Indexer (API check) - Critical
    2. Index patterns match
    3. Priority matches
    4. Settings match (shards, replicas, refresh_interval)
    5. Mappings match (custom fields)
    6. Agent saved the verification JSON to file
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('template_name', 'wazuh-custom-alerts')
    expected_patterns = set(metadata.get('expected_index_patterns', ["wazuh-alerts-custom-*"]))
    expected_priority = metadata.get('expected_priority', 50)
    expected_settings = metadata.get('expected_settings', {})
    expected_mappings = metadata.get('expected_mappings', {})

    # Copy result file
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
    feedback_parts = []
    
    # --- 1. Verify Template Existence (Critical) ---
    template_exists = result.get('template_exists_in_api', False)
    actual_config = result.get('actual_template_config', {})
    
    if not template_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Template '{expected_name}' not found in Wazuh Indexer."
        }
    
    score += 15
    feedback_parts.append("Template created")

    # Parse the actual config structure from OpenSearch _index_template API
    # Structure: {"index_templates": [{"name": "...", "index_template": { ... }}]}
    template_data = {}
    try:
        templates_list = actual_config.get('index_templates', [])
        for t in templates_list:
            if t.get('name') == expected_name:
                template_data = t.get('index_template', {})
                break
    except Exception as e:
        logger.error(f"Error parsing template config: {e}")

    if not template_data:
        return {
            "passed": False, 
            "score": 15, 
            "feedback": "Template exists but configuration could not be parsed."
        }

    # --- 2. Verify Index Patterns ---
    actual_patterns = set(template_data.get('index_patterns', []))
    if expected_patterns.issubset(actual_patterns):
        score += 10
        feedback_parts.append("Index patterns correct")
    else:
        feedback_parts.append(f"Index patterns mismatch: {actual_patterns}")

    # --- 3. Verify Priority ---
    actual_priority = template_data.get('priority')
    if actual_priority == expected_priority:
        score += 5
        feedback_parts.append("Priority correct")
    else:
        feedback_parts.append(f"Priority mismatch: {actual_priority}")

    # --- 4. Verify Settings ---
    # Settings are inside "template": { "settings": { "index": { ... } } }
    # Note: OpenSearch API might flatten or nest settings differently depending on version
    # usually it's template -> settings -> index -> number_of_shards
    
    actual_settings = template_data.get('template', {}).get('settings', {})
    # Flatten settings for easier lookup if needed, or handle nesting
    # API usually returns: {"index": {"number_of_shards": "1", ...}}
    
    index_settings = actual_settings.get('index', {})
    
    # Check Shards
    shards = index_settings.get('number_of_shards')
    if str(shards) == str(expected_settings.get('index.number_of_shards')):
        score += 10
        feedback_parts.append("Shards correct")
    else:
        feedback_parts.append(f"Shards mismatch: {shards}")

    # Check Replicas
    replicas = index_settings.get('number_of_replicas')
    if str(replicas) == str(expected_settings.get('index.number_of_replicas')):
        score += 10
        feedback_parts.append("Replicas correct")
    else:
        feedback_parts.append(f"Replicas mismatch: {replicas}")

    # Check Refresh Interval
    refresh = index_settings.get('refresh_interval')
    if str(refresh) == str(expected_settings.get('index.refresh_interval')):
        score += 10
        feedback_parts.append("Refresh interval correct")
    else:
        feedback_parts.append(f"Refresh interval mismatch: {refresh}")

    # --- 5. Verify Mappings ---
    # Mappings are inside "template": { "mappings": { "properties": { ... } } }
    actual_mappings = template_data.get('template', {}).get('mappings', {}).get('properties', {})
    
    mapping_score = 0
    mapping_items = 0
    for field, field_type in expected_mappings.items():
        mapping_items += 1
        # Handle nested fields (dot notation in expected vs nested dicts in actual)
        # expected: "threat.enrichment.source"
        # actual could be nested dicts OR dot notation depending on API response format.
        # OpenSearch usually returns nested dicts for "properties"
        
        # Helper to traverse nested dict
        parts = field.split('.')
        current = actual_mappings
        found = True
        for part in parts:
            if part in current:
                # If it's the leaf, it has 'type', else it has 'properties'
                if 'properties' in current[part]:
                    current = current[part]['properties']
                else:
                    current = current[part]
            else:
                found = False
                break
        
        if found and current.get('type') == field_type:
            mapping_score += 10
        else:
            feedback_parts.append(f"Mapping missing/wrong: {field}")

    score += mapping_score
    if mapping_score == 30: # All 3 correct
        feedback_parts.append("Mappings correct")

    # --- 6. Verify Output File ---
    if result.get('agent_file_exists') and result.get('agent_file_created_during_task'):
        score += 10
        feedback_parts.append("Output file saved")
        
        # Optional: check if file content looks like the template
        file_content = result.get('agent_file_content', {})
        if isinstance(file_content, dict) and 'index_templates' in file_content:
             # Just a basic sanity check that they dumped the right thing
             pass
    else:
        feedback_parts.append("Output file missing or old")

    passed = score >= 70 and template_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }