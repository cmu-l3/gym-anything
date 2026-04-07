#!/usr/bin/env python3
"""Verifier for create_custom_viewtemplate task."""

import json
import tempfile
import os
import re

def verify_viewtemplate(traj, env_info, task_info):
    """Verify that the ViewTemplate was created correctly with conditional logic and field transclusions."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_fields = metadata.get('required_fields', ['author', 'journal', 'year', 'doi'])

    # Extract JSON results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/viewtemplate_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Criterion 1: Seed Tiddlers Unmodified (20 pts - Anti-gaming)
    if result.get('seeds_unmodified'):
        score += 20
        feedback_parts.append("Seed Paper tiddlers remain unmodified (enforces templating usage)")
    else:
        feedback_parts.append("FAIL: Seed Paper tiddlers were modified. Hardcoding metadata directly into tiddlers is not allowed.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: ViewTemplate Exists (20 pts)
    if result.get('template_found'):
        score += 20
        feedback_parts.append(f"ViewTemplate found: '{result.get('template_title')}'")
    else:
        feedback_parts.append("FAIL: No tiddler found with the tag '$:/tags/ViewTemplate'")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    template_text = result.get('template_text', '')

    # Criterion 3: Conditional Logic restricts template to 'Paper' tagged tiddlers (30 pts)
    # Checks for common list/reveal widget syntax like [all[current]tag[Paper]] or <$list filter="[tag[Paper]]">
    has_logic = result.get('has_conditional_logic')
    strict_logic_pattern = re.search(r'tag\[Paper\]|tag<Paper>|field:tags\[.*Paper.*\]', template_text, re.IGNORECASE)
    
    if has_logic and strict_logic_pattern:
        score += 30
        feedback_parts.append("Conditional logic targeting the 'Paper' tag verified")
    elif has_logic:
        score += 15
        feedback_parts.append("Partial conditional logic detected (may not correctly restrict to 'Paper')")
    else:
        feedback_parts.append("FAIL: Missing conditional logic. The template will bleed onto every page in the wiki without a filter restricting it to 'Paper' tiddlers.")

    # Criterion 4: Field Transclusion logic (30 pts)
    # Checks for {{!!field}} or <$transclude field="field"/>
    transcluded_fields = 0
    missing_fields = []
    
    for field in required_fields:
        # Regex to catch: {{!!author}}, <$view field="author"/>, <$transclude field="author"/>
        pattern = f"(!!{field}|field=[\"']{field}[\"'])"
        if re.search(pattern, template_text, re.IGNORECASE):
            transcluded_fields += 1
        else:
            missing_fields.append(field)

    if transcluded_fields == len(required_fields):
        score += 30
        feedback_parts.append("All required fields successfully transcluded")
    elif transcluded_fields > 0:
        score += int(30 * (transcluded_fields / len(required_fields)))
        feedback_parts.append(f"Fields transcluded partially ({transcluded_fields}/{len(required_fields)}). Missing: {', '.join(missing_fields)}")
    else:
        feedback_parts.append("FAIL: No fields were dynamically transcluded (missing syntax like {{!!author}})")

    # Final pass logic
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }