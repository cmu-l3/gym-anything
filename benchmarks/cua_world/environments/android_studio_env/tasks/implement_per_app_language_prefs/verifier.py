#!/usr/bin/env python3
"""
Verifier for implement_per_app_language_prefs task.

Checks:
1. locales_config.xml exists and contains correct locales (20 pts)
2. AndroidManifest.xml references localeConfig (20 pts)
3. MainActivity.kt calls AppCompatDelegate.setApplicationLocales (40 pts)
4. MainActivity.kt uses correct language tags (10 pts)
5. Project builds successfully (10 pts)
"""

import json
import logging
import os
import re
import tempfile
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _read_json_from_env(copy_from_env, container_path: str) -> dict:
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(container_path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception as exc:
        logger.debug("Could not read JSON %s: %s", container_path, exc)
        return {}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

def verify_implement_per_app_language_prefs(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    result = _read_json_from_env(copy_from_env, "/tmp/task_result.json")
    
    score = 0
    feedback_parts = []
    
    # 1. Check Locale Config File (20 pts)
    config_exists = result.get("config_exists", False)
    config_content = result.get("config_content", "")
    
    if config_exists:
        try:
            # Simple check for required locales in content string to avoid namespace XML parsing headaches
            locales_found = []
            for loc in ["en", "fr", "es"]:
                if f'name="{loc}"' in config_content or f'name=\'{loc}\'' in config_content or f'>{loc}<' in config_content:
                    locales_found.append(loc)
            
            if len(locales_found) == 3:
                score += 20
                feedback_parts.append("locales_config.xml valid (20/20)")
            else:
                score += 10
                feedback_parts.append(f"locales_config.xml missing some locales, found: {locales_found} (10/20)")
        except Exception:
            score += 5
            feedback_parts.append("locales_config.xml exists but parsing failed (5/20)")
    else:
        feedback_parts.append("locales_config.xml not created (0/20)")

    # 2. Check Manifest Registration (20 pts)
    manifest_content = result.get("manifest_content", "")
    if 'android:localeConfig="@xml/locales_config"' in manifest_content or 'android:localeConfig="@xml/locales_config"' in manifest_content:
        score += 20
        feedback_parts.append("Manifest configured correctly (20/20)")
    else:
        feedback_parts.append("Manifest missing android:localeConfig attribute (0/20)")

    # 3. Check MainActivity Logic (40 pts)
    code = result.get("main_activity_content", "")
    
    # Check for setApplicationLocales
    if "AppCompatDelegate.setApplicationLocales" in code:
        score += 40
        feedback_parts.append("Locale switching logic implemented (40/40)")
    elif "setApplicationLocales" in code:
         score += 30 # Partial credit if AppCompatDelegate explicit reference missing but method calls exist
         feedback_parts.append("Locale switching logic found (30/40)")
    else:
        feedback_parts.append("AppCompatDelegate.setApplicationLocales not found (0/40)")

    # 4. Check Language Tags (10 pts)
    # Looking for "fr", "es", "en" usage in the code
    tags_found = 0
    if '"en"' in code or '"en-US"' in code: tags_found += 1
    if '"fr"' in code or '"fr-FR"' in code: tags_found += 1
    if '"es"' in code or '"es-ES"' in code: tags_found += 1
    
    if tags_found >= 3:
        score += 10
        feedback_parts.append("All language tags found in code (10/10)")
    elif tags_found > 0:
        score += 5
        feedback_parts.append("Some language tags found (5/10)")
    else:
        feedback_parts.append("Language tags not found in code (0/10)")

    # 5. Build Success (10 pts)
    if result.get("build_success", False):
        score += 10
        feedback_parts.append("Project builds successfully (10/10)")
    else:
        feedback_parts.append("Build failed (0/10)")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }