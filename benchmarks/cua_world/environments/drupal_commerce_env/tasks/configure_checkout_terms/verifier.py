#!/usr/bin/env python3
"""
Verifier for configure_checkout_terms task.

Scoring Criteria:
1. "Terms and Conditions" page exists and is published (30 pts)
2. Checkout flow "Terms of service" pane is enabled (not disabled) (30 pts)
3. "Terms of service" pane is correctly linked to the created page (40 pts)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_checkout_terms(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []
    
    # Extract data
    node_data = result.get('node_data')
    checkout_config = result.get('checkout_config', {})
    
    # ------------------------------------------------------------------
    # Criterion 1: Page Creation (30 pts)
    # ------------------------------------------------------------------
    created_nid = None
    if node_data and node_data.get('nid'):
        created_nid = str(node_data.get('nid'))
        title = node_data.get('title')
        status = str(node_data.get('status'))
        
        if status == '1':
            score += 30
            feedback.append(f"Success: Page '{title}' (ID: {created_nid}) created and published.")
        else:
            score += 15
            feedback.append(f"Partial: Page '{title}' created but NOT published.")
    else:
        feedback.append("Fail: No 'Terms and Conditions' page found.")
        # If no page created, we can't fully verify linking, but we check pane enablement
    
    # ------------------------------------------------------------------
    # Criterion 2: Pane Enablement (30 pts)
    # ------------------------------------------------------------------
    # Access: config -> commerce_checkout.commerce_checkout_flow.default -> configuration -> panes -> commerce_checkout_terms_of_service
    # Note: Drush JSON output structure can sometimes wrap keys differently, but typically it matches the YAML structure.
    
    # Handle possible nesting variations in Drush output
    config_root = checkout_config.get('commerce_checkout.commerce_checkout_flow.default', checkout_config)
    panes = config_root.get('configuration', {}).get('panes', {})
    terms_pane = panes.get('commerce_checkout_terms_of_service', {})
    
    pane_step = terms_pane.get('step', '_disabled')
    
    if pane_step != '_disabled':
        score += 30
        feedback.append(f"Success: Terms of Service pane enabled in step '{pane_step}'.")
    else:
        feedback.append("Fail: Terms of Service pane is still disabled.")

    # ------------------------------------------------------------------
    # Criterion 3: Configuration Linking (40 pts)
    # ------------------------------------------------------------------
    if pane_step != '_disabled':
        # Check configuration inside the pane
        pane_config = terms_pane.get('configuration', {})
        # The key is usually 'terms_page_link', containing 'nid' or 'node:nid'
        # But in Commerce 2.x config, it stores the raw ID usually? 
        # Actually, standard commerce config schema uses entity_autocomplete which stores just the ID often,
        # but sometimes it might be empty if defaults are used.
        
        linked_page_id = str(pane_config.get('terms_page_link', ''))
        
        if created_nid:
            if linked_page_id == created_nid:
                score += 40
                feedback.append(f"Success: Pane correctly linked to node {created_nid}.")
            elif not linked_page_id:
                feedback.append("Fail: Pane enabled but no page linked.")
            else:
                feedback.append(f"Fail: Pane linked to wrong ID (Expected {created_nid}, Found {linked_page_id}).")
        else:
            feedback.append("Fail: Cannot verify link because no Terms page was found.")
    else:
        feedback.append("Fail: Pane not enabled, so link configuration not verified.")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }