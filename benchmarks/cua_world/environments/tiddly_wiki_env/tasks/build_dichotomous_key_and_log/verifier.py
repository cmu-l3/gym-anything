#!/usr/bin/env python3
"""Verifier for build_dichotomous_key_and_log task."""

import json
import tempfile
import os
import re

def verify_dichotomous_key(traj, env_info, task_info):
    """
    Verify the creation of 5 Species tiddlers, 4 KeyNode tiddlers, and 3 Observation tiddlers.
    Scoring matches the task.json rationale perfectly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_species = metadata.get('species', [])
    expected_nodes = metadata.get('nodes', [])
    expected_obs = metadata.get('observations', [])

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/dichotomous_key_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    tiddlers = result.get('tiddlers', {})
    score = 0
    feedback_parts = []
    
    # Track criteria groups
    species_present_score = 0
    species_fields_score = 0
    nodes_present_score = 0
    nodes_links_score = 0
    obs_score = 0

    # 1. Check Species Tiddlers (15 pts for presence/tags, 25 pts for fields)
    for sp in expected_species:
        title = sp['title']
        tid = tiddlers.get(title)
        
        if tid:
            fields = tid.get('fields', {})
            tags = fields.get('tags', '')
            
            # Presence & Tags (3 pts per species)
            if 'species' in tags.lower():
                species_present_score += 3
            else:
                feedback_parts.append(f"Species '{title}' missing 'Species' tag.")
                
            # Taxonomic Fields (5 pts per species)
            f_sciname = fields.get('scientific-name', '').lower().strip()
            f_fam = fields.get('family', '').lower().strip()
            f_cons = fields.get('conservation-status', '').lower().strip()
            
            expected_sciname = sp['scientific-name'].lower().strip()
            expected_fam = sp['family'].lower().strip()
            expected_cons = sp['conservation-status'].lower().strip()
            
            field_matches = 0
            if f_sciname == expected_sciname: field_matches += 1
            if f_fam == expected_fam: field_matches += 1
            if f_cons == expected_cons: field_matches += 1
            
            if field_matches == 3:
                species_fields_score += 5
            else:
                species_fields_score += (field_matches * 1.66) # Partial credit
                feedback_parts.append(f"Species '{title}' fields incomplete ({field_matches}/3 correct).")
        else:
            feedback_parts.append(f"Missing species tiddler: {title}")

    # 2. Check Key Nodes (12 pts for presence/tags, 28 pts for routing logic)
    for node in expected_nodes:
        title = node['title']
        tid = tiddlers.get(title)
        
        if tid:
            fields = tid.get('fields', {})
            tags = fields.get('tags', '')
            body = tid.get('body', '')
            
            # Presence & Tags (3 pts per node)
            if 'keynode' in tags.lower():
                nodes_present_score += 3
            else:
                feedback_parts.append(f"Node '{title}' missing 'KeyNode' tag.")
                
            # Routing Logic (7 pts per node)
            expected_links = node['links']
            links_found = 0
            for link in expected_links:
                # Using lower case for case-insensitive link matching check, but allowing original casing
                if link.lower() in body.lower():
                    links_found += 1
                    
            if links_found == len(expected_links):
                nodes_links_score += 7
            else:
                nodes_links_score += (links_found * 3.5) # Partial credit
                feedback_parts.append(f"Node '{title}' missing expected routing links.")
        else:
            feedback_parts.append(f"Missing key node tiddler: {title}")

    # 3. Check Observation Logs (20 pts total, ~6.66 pts per obs)
    for obs in expected_obs:
        title = obs['title']
        tid = tiddlers.get(title)
        
        if tid:
            fields = tid.get('fields', {})
            tags = fields.get('tags', '')
            
            pts = 0.0
            if 'observation' in tags.lower():
                pts += 1.66
            
            # Dates and fields
            if fields.get('date', '').strip() == obs['date']: pts += 1.25
            if fields.get('identified-species', '').lower().strip() == obs['identified-species'].lower(): pts += 1.25
            
            # Handle lat/lon gracefully (allow float casting)
            try:
                f_lat = float(fields.get('latitude', 0))
                if abs(f_lat - float(obs['latitude'])) < 0.001: pts += 1.25
            except:
                pass
                
            try:
                f_lon = float(fields.get('longitude', 0))
                if abs(f_lon - float(obs['longitude'])) < 0.001: pts += 1.25
            except:
                pass
                
            obs_score += min(6.66, pts)
        else:
            feedback_parts.append(f"Missing observation tiddler: {title}")

    # Total Score Calculation
    score = sum([
        species_present_score,
        species_fields_score,
        nodes_present_score,
        nodes_links_score,
        obs_score
    ])
    
    score = int(round(score))
    
    # Feedback Assembly
    if score >= 100:
        feedback_parts = ["Perfect score! All species, nodes, and observations created correctly."]
    elif len(feedback_parts) == 0:
        feedback_parts.append(f"Score: {score}/100")
        
    # Check if GUI was used
    gui_saves = result.get('gui_saves', 0)
    if gui_saves == 0:
        feedback_parts.append("Note: No GUI save events detected (direct file manipulation?).")

    # Pass threshold: 75
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts[:10]), # limit feedback length
        "subscores": {
            "species_present": round(species_present_score, 1),
            "species_fields": round(species_fields_score, 1),
            "nodes_present": round(nodes_present_score, 1),
            "nodes_links": round(nodes_links_score, 1),
            "observations": round(obs_score, 1)
        }
    }