#!/usr/bin/env python3
"""
Verifier for build_faceted_exoplanet_catalog task.

Verifies the creation of a faceted search dashboard in TiddlyWiki using:
1. Two `<$select>` widgets targeting a hidden state tiddler.
2. A `<$list>` widget with a dynamic filter transcluding the state tiddler fields.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_exoplanet_dashboard(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('target_tiddler', 'Exoplanet Explorer')
    state_tiddler = metadata.get('state_tiddler', '$:/state/ExoplanetFilter')

    # Copy result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Criterion 1: Tiddler Exists and was created during task (10 pts)
    tiddler_exists = result.get('tiddler_exists', False)
    content = result.get('tiddler_content', '')
    
    if not tiddler_exists:
        feedback_parts.append(f"FAIL: Tiddler '{expected_title}' not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    
    score += 10
    feedback_parts.append(f"Tiddler '{expected_title}' exists")

    content_lower = content.lower()

    # Criterion 2: Target State Tiddler used (15 pts)
    # Check if the state tiddler is referenced at least twice (for the two selects/filters)
    state_ref_count = content_lower.count(state_tiddler.lower())
    if state_ref_count >= 2:
        score += 15
        feedback_parts.append(f"State tiddler '{state_tiddler}' properly referenced")
    elif state_ref_count == 1:
        score += 5
        feedback_parts.append(f"State tiddler '{state_tiddler}' referenced, but maybe not for both fields")
    else:
        feedback_parts.append(f"FAIL: State tiddler '{state_tiddler}' missing")

    # Criterion 3: Discovery Dropdown Configuration (15 pts)
    has_selects = '<$select' in content_lower
    has_discovery_field = 'field="discovery-method"' in content_lower or "field='discovery-method'" in content_lower
    has_transit_opt = 'transit' in content_lower and '<option' in content_lower

    if has_selects and has_discovery_field and has_transit_opt:
        score += 15
        feedback_parts.append("Discovery Method dropdown configured correctly")
    elif has_selects and has_discovery_field:
        score += 10
        feedback_parts.append("Discovery Method dropdown found but missing options")
    else:
        feedback_parts.append("FAIL: Discovery Method dropdown misconfigured")

    # Criterion 4: Planet Type Dropdown Configuration (15 pts)
    has_planet_field = 'field="planet-type"' in content_lower or "field='planet-type'" in content_lower
    has_terrestrial_opt = 'terrestrial' in content_lower and '<option' in content_lower

    if has_selects and has_planet_field and has_terrestrial_opt:
        score += 15
        feedback_parts.append("Planet Type dropdown configured correctly")
    elif has_selects and has_planet_field:
        score += 10
        feedback_parts.append("Planet Type dropdown found but missing options")
    else:
        feedback_parts.append("FAIL: Planet Type dropdown misconfigured")

    # Criterion 5: Exact Filter Syntax with Transclusions (25 pts)
    has_list_widget = '<$list' in content_lower
    
    # Regex to check for correct TiddlyWiki filter transclusion syntax:
    # Look for: discovery-method{$:/state/ExoplanetFilter!!discovery-method}
    # Allow optional spaces.
    discovery_transclusion = bool(re.search(
        r'discovery-method\s*\{\s*\$:/state/ExoplanetFilter!!discovery-method\s*\}', 
        content, re.IGNORECASE
    ))
    
    planet_transclusion = bool(re.search(
        r'planet-type\s*\{\s*\$:/state/ExoplanetFilter!!planet-type\s*\}', 
        content, re.IGNORECASE
    ))

    has_exoplanet_tag = '[tag[Exoplanet]]' in content or 'tag[Exoplanet]' in content

    if has_list_widget and discovery_transclusion and planet_transclusion and has_exoplanet_tag:
        score += 25
        feedback_parts.append("Dynamic filter correctly uses transclusion for both fields")
    elif has_list_widget and (discovery_transclusion or planet_transclusion):
        score += 15
        feedback_parts.append("Dynamic filter partially configured (misses one transclusion)")
    elif has_list_widget:
        score += 5
        feedback_parts.append("List widget present but filter transclusions are incorrect/missing")
    else:
        feedback_parts.append("FAIL: `<$list>` widget with dynamic filter not found")

    # Criterion 6: Result Links (10 pts)
    has_link = '<$link' in content_lower or '<$link/>' in content_lower or '<$link to=' in content_lower
    if has_link:
        score += 10
        feedback_parts.append("List output styled as links")
    else:
        feedback_parts.append("Warning: `<$link>` widget not found in output")

    # Criterion 7: GUI Interaction (10 pts)
    gui_save = result.get('gui_save_detected', False)
    if gui_save:
        score += 10
        feedback_parts.append("GUI save verified via server log")
    else:
        feedback_parts.append("Warning: No GUI save detected in server log")

    # Final Evaluation
    key_criteria_met = tiddler_exists and has_selects and has_list_widget and (discovery_transclusion or planet_transclusion)
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }