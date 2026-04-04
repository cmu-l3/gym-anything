#!/usr/bin/env python3
"""
Verifier for configure_tax_type task in Drupal Commerce.

Checks if a new tax type configuration entity was created with:
1. Correct Label (contains "California")
2. Plugin type "custom"
3. Display inclusive = False
4. Round = True
5. Correct Zone configuration (US, CA)
6. Correct Rate configuration (0.0725)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_tax_type(traj, env_info, task_info):
    """
    Verify the tax type configuration using the exported JSON from Drush.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_label_substr = metadata.get('expected_label_substr', 'California')
    expected_plugin = metadata.get('expected_plugin', 'custom')
    expected_rate = metadata.get('expected_rate_percentage', 0.0725)
    
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
            
        # Basic check: Was a new config created?
        new_config_name = result.get('new_config_name', '')
        config_data = result.get('config_data', {})
        
        if not new_config_name or not config_data:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No new tax type configuration found. Did you save the tax type?"
            }

        # The config data from drush is usually keyed by the config name
        # e.g. {"commerce_tax.commerce_tax_type.my_tax": {...}}
        # We need to extract the inner dictionary
        if new_config_name in config_data:
            data = config_data[new_config_name]
        else:
            # Fallback if structure is flat
            data = config_data

        score = 0
        feedback_parts = []
        
        # 1. Label Check (15 pts)
        label = data.get('label', '')
        if expected_label_substr.lower() in label.lower():
            score += 15
            feedback_parts.append(f"Label correct ('{label}')")
        else:
            feedback_parts.append(f"Label mismatch: expected '{expected_label_substr}', got '{label}'")

        # 2. Plugin Check (10 pts)
        plugin = data.get('plugin', '')
        if plugin == expected_plugin:
            score += 10
            feedback_parts.append("Plugin type correct")
        else:
            feedback_parts.append(f"Wrong plugin type: {plugin}")

        # 3. Configuration Settings
        config = data.get('configuration', {})
        
        # Display inclusive (10 pts)
        display_inclusive = config.get('display_inclusive')
        if display_inclusive is False:
            score += 10
            feedback_parts.append("Display inclusive correct (No)")
        else:
            feedback_parts.append(f"Display inclusive incorrect: {display_inclusive}")
            
        # Rounding (5 pts - bonus check not explicitly in summary but good practice)
        if config.get('round') is True:
            score += 5
            feedback_parts.append("Rounding enabled")

        # 4. Zone & Territory Analysis
        zones = config.get('zones', [])
        found_us_ca = False
        found_rate = False
        rate_val_found = None
        
        for zone in zones:
            # Check territories
            territories = zone.get('territories', [])
            for terr in territories:
                cc = terr.get('country_code', '')
                aa = terr.get('administrative_area', '')
                if cc == 'US' and aa == 'CA':
                    found_us_ca = True
            
            # Check rates
            rates = zone.get('rates', [])
            for rate in rates:
                # Value stored as string percentage usually, verify format
                perc = rate.get('percentage', '0')
                try:
                    perc_val = float(perc)
                    # Check match with tolerance
                    if abs(perc_val - expected_rate) < 0.0001:
                        found_rate = True
                    rate_val_found = perc_val
                except ValueError:
                    pass

        # Territory Score (30 pts)
        if found_us_ca:
            score += 30
            feedback_parts.append("Territory (US-California) correct")
        else:
            feedback_parts.append("Territory US-California NOT found in zones")

        # Rate Score (30 pts)
        if found_rate:
            score += 30
            feedback_parts.append(f"Tax rate {expected_rate} correct")
        elif rate_val_found is not None:
            # Partial credit for getting close or formatting error (e.g. 7.25 vs 0.0725)
            if abs(rate_val_found - (expected_rate * 100)) < 0.001:
                 # Agent entered 7.25 instead of 0.0725
                 score += 10
                 feedback_parts.append(f"Rate value incorrect (entered {rate_val_found}, expected {expected_rate}). Did you enter % as whole number?")
            else:
                 feedback_parts.append(f"Rate value incorrect: {rate_val_found}")
        else:
            feedback_parts.append("No tax rate found")

        return {
            "passed": score >= 70,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification failed with error: {str(e)}"}