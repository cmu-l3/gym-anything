#!/usr/bin/env python3
"""
Verifier for Internationalization (i18n) task.

Criteria:
1. Properties files created: en, es, fr (30 pts)
2. Sufficient key count (>=15) in each file (10 pts)
3. Consistency: Keys match across files (10 pts)
4. Translation content: es/fr values differ from en (5 pts)
5. Code Modification: Java files use ResourceBundle (15 pts)
6. Hardcoded Strings: Removed from System.out.println (15 pts)
7. Compilation: Project compiles successfully (15 pts)
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_properties(content):
    """Parse Java properties file content into a dict."""
    props = {}
    if not content:
        return props
    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith('#') or line.startswith('!'):
            continue
        # Split on first = or :
        parts = re.split(r'[=:]', line, 1)
        if len(parts) == 2:
            key = parts[0].strip()
            val = parts[1].strip()
            props[key] = val
    return props

def verify_internationalize_app(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_keys = metadata.get('min_key_count', 15)

    # Load result
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
    
    # Extract data
    props_files = result.get('properties_files', {})
    java_files = result.get('java_files', {})
    compiles = result.get('compilation_success', False)
    task_start = result.get('task_start', 0)

    # --- Criterion 1: Properties files existence (30 pts) ---
    required_langs = ['en', 'es', 'fr']
    found_langs = []
    prop_contents = {} # lang -> dict of keys

    for lang in required_langs:
        # Match messages_en.properties, messages_en_US.properties, etc.
        # But task specifically asked for messages_en.properties
        fname = f"messages_{lang}.properties"
        if fname in props_files:
            found_langs.append(lang)
            content = props_files[fname].get('content', '')
            prop_contents[lang] = parse_properties(content)
            
            # Anti-gaming: Check timestamp
            mtime = props_files[fname].get('mtime', 0)
            if mtime > task_start:
                score += 10
                feedback_parts.append(f"Created {fname}")
            else:
                score += 5 # Created but timestamp weird?
                feedback_parts.append(f"Found {fname} (timestamp check warning)")
        else:
            feedback_parts.append(f"Missing {fname}")

    # --- Criterion 2: Key Count (10 pts) ---
    sufficient_keys = True
    for lang in found_langs:
        count = len(prop_contents[lang])
        if count < min_keys:
            sufficient_keys = False
            feedback_parts.append(f"{lang} has only {count} keys (need {min_keys})")
    
    if found_langs and sufficient_keys:
        score += 10
        feedback_parts.append(f"All bundles have sufficient keys (>={min_keys})")
    elif found_langs:
        score += 5
        feedback_parts.append("Some bundles have too few keys")

    # --- Criterion 3: Consistency (10 pts) ---
    # Check if keys in ES match keys in EN
    if 'en' in prop_contents and 'es' in prop_contents:
        en_keys = set(prop_contents['en'].keys())
        es_keys = set(prop_contents['es'].keys())
        overlap = en_keys.intersection(es_keys)
        if len(overlap) / max(len(en_keys), 1) > 0.9:
            score += 10
            feedback_parts.append("Key consistency good between EN and ES")
        else:
            score += 2
            feedback_parts.append("Low key consistency between EN and ES")
    
    # --- Criterion 4: Translation Content (5 pts) ---
    # Check that ES values are not just copies of EN
    if 'en' in prop_contents and 'es' in prop_contents:
        diff_count = 0
        common_keys = set(prop_contents['en'].keys()).intersection(prop_contents['es'].keys())
        for k in common_keys:
            if prop_contents['en'][k] != prop_contents['es'][k]:
                diff_count += 1
        
        if diff_count > len(common_keys) * 0.5:
            score += 5
            feedback_parts.append("Translations appear genuine")
        else:
            feedback_parts.append("Spanish translations look copied from English")

    # --- Criterion 5: ResourceBundle Usage (15 pts) ---
    # Scan Java files for ResourceBundle import or usage
    rb_usage_found = False
    for fname, data in java_files.items():
        content = data.get('content', '')
        if 'ResourceBundle' in content or 'getBundle' in content:
            rb_usage_found = True
            break
    
    if rb_usage_found:
        score += 15
        feedback_parts.append("ResourceBundle usage detected in code")
    else:
        feedback_parts.append("No ResourceBundle usage detected in Java files")

    # --- Criterion 6: Hardcoded Strings Removal (15 pts) ---
    # Heuristic: Check for System.out.println("...") 
    # Valid: System.out.println(messages.getString("key"))
    # Invalid: System.out.println("Welcome")
    hardcoded_count = 0
    for fname, data in java_files.items():
        content = data.get('content', '')
        # Regex for System.out.print(ln)?\s*\(\s*"
        # Matches literal strings starting args
        matches = re.findall(r'System\.out\.print(?:ln)?\s*\(\s*"[A-Za-z]', content)
        hardcoded_count += len(matches)

    if hardcoded_count == 0:
        score += 15
        feedback_parts.append("No hardcoded strings detected in print statements")
    elif hardcoded_count < 5:
        score += 10
        feedback_parts.append(f"Few hardcoded strings remain ({hardcoded_count})")
    else:
        feedback_parts.append(f"Many hardcoded strings remain ({hardcoded_count})")

    # --- Criterion 7: Compilation (15 pts) ---
    if compiles:
        score += 15
        feedback_parts.append("Project compiles successfully")
    else:
        feedback_parts.append("Project compilation failed")

    return {
        "passed": score >= 60 and compiles,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }