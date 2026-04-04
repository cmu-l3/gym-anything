#!/usr/bin/env python3
"""
Verifier for setup_code_spell_checker@1 task

Checks:
1. Code Spell Checker extension installed
2. Custom dictionary configured in workspace settings
3. Typos fixed in README.md
4. Typos fixed in auth_provider.py docstrings
"""

import sys
import os
import json
import logging
import tempfile
import shutil
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_spell_checker_setup(traj, env_info, task_info):
    """
    Verify that spell checker was configured and typos were fixed.
    
    Scoring:
    - Extension installed: 2 points
    - Custom dictionary configured: 3 points
    - README typos fixed: 3 points
    - Python typos fixed: 2 points
    Total: 10 points, pass threshold: 7 points (70%)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Use temporary directory for copied files
    temp_dir = tempfile.mkdtemp(prefix='spell_verify_')
    
    try:
        results_dir = "/tmp/spell_checker_results"
        
        # Prepare local paths
        local_settings = os.path.join(temp_dir, "settings.json")
        local_readme = os.path.join(temp_dir, "README.md")
        local_python = os.path.join(temp_dir, "auth_provider.py")
        local_extensions = os.path.join(temp_dir, "extensions.txt")
        
        # Copy files from container
        try:
            copy_from_env(f"{results_dir}/settings.json", local_settings)
            copy_from_env(f"{results_dir}/README.md", local_readme)
            copy_from_env(f"{results_dir}/auth_provider.py", local_python)
            copy_from_env(f"{results_dir}/extensions.txt", local_extensions)
        except Exception as e:
            logger.error(f"Failed to copy result files: {e}")
            return {"passed": False, "score": 0, "feedback": f"Failed to copy result files: {str(e)}"}
        
        score = 0.0
        max_score = 10.0
        feedback = []
        info = {}
        
        # ===== CRITERION 1: Extension Installed (2 points) =====
        extension_installed = False
        if os.path.exists(local_extensions) and os.path.getsize(local_extensions) > 0:
            with open(local_extensions, 'r') as f:
                extensions_content = f.read().lower()
                if 'code-spell-checker' in extensions_content or 'streetsidesoftware' in extensions_content:
                    extension_installed = True
                    score += 2.0
                    feedback.append("✅ Code Spell Checker extension installed")
                    info['extension_installed'] = True
                else:
                    feedback.append("❌ Code Spell Checker extension not installed")
                    info['extension_installed'] = False
        else:
            feedback.append("❌ Extensions list not found")
            info['extension_installed'] = False
        
        # ===== CRITERION 2: Custom Dictionary (3 points) =====
        required_terms = ['AuthN', 'AuthZ', 'CRMSync', 'SalesforceAPI', 
                         'MetricsAgg', 'TimeSeries', 'RefreshToken', 'JWTValidator']
        custom_words_found = []
        
        if os.path.exists(local_settings) and os.path.getsize(local_settings) > 2:
            try:
                with open(local_settings, 'r') as f:
                    settings = json.load(f)
                
                # Check for cSpell.words configuration
                if 'cSpell.words' in settings and isinstance(settings['cSpell.words'], list):
                    custom_words_found = settings['cSpell.words']
                    terms_present = sum(1 for term in required_terms if term in custom_words_found)
                    
                    if terms_present >= 6:  # At least 6 of 8 required terms
                        score += 3.0
                        feedback.append(f"✅ Custom dictionary: {terms_present}/8 terms present")
                        info['dictionary_terms'] = terms_present
                    elif terms_present >= 4:
                        score += 2.0
                        feedback.append(f"◐ Custom dictionary: {terms_present}/8 terms present")
                        info['dictionary_terms'] = terms_present
                    elif terms_present >= 2:
                        score += 1.0
                        feedback.append(f"◑ Custom dictionary: only {terms_present}/8 terms present")
                        info['dictionary_terms'] = terms_present
                    else:
                        feedback.append(f"❌ Custom dictionary: insufficient terms ({terms_present}/8)")
                        info['dictionary_terms'] = terms_present
                else:
                    feedback.append("❌ cSpell.words not configured in settings")
                    info['dictionary_terms'] = 0
            except json.JSONDecodeError as e:
                feedback.append(f"❌ Invalid JSON in settings.json: {str(e)[:50]}")
                info['dictionary_terms'] = 0
        else:
            feedback.append("❌ Workspace settings.json not found or empty")
            info['dictionary_terms'] = 0
        
        # ===== CRITERION 3: README Typos Fixed (3 points) =====
        readme_typos_fixed = 0
        original_typos_readme = [
            'syncronizing', 'automaticaly', 'managment', 'suports',
            'configurate', 'libary', 'initalize', 'miliseconds',
            'maximun', 'licnese'
        ]
        
        if os.path.exists(local_readme) and os.path.getsize(local_readme) > 10:
            with open(local_readme, 'r') as f:
                readme_content = f.read().lower()
            
            # Count how many typos are gone (fixed)
            for typo in original_typos_readme:
                if typo not in readme_content:
                    readme_typos_fixed += 1
            
            # Award points based on typos fixed
            if readme_typos_fixed >= 8:
                score += 3.0
                feedback.append(f"✅ README typos fixed: {readme_typos_fixed}/10")
                info['readme_typos_fixed'] = readme_typos_fixed
            elif readme_typos_fixed >= 6:
                score += 2.0
                feedback.append(f"◐ README typos fixed: {readme_typos_fixed}/10")
                info['readme_typos_fixed'] = readme_typos_fixed
            elif readme_typos_fixed >= 4:
                score += 1.0
                feedback.append(f"◑ README typos fixed: {readme_typos_fixed}/10")
                info['readme_typos_fixed'] = readme_typos_fixed
            else:
                feedback.append(f"❌ README: only {readme_typos_fixed}/10 typos fixed")
                info['readme_typos_fixed'] = readme_typos_fixed
        else:
            feedback.append("❌ README.md not found or empty")
            info['readme_typos_fixed'] = 0
        
        # ===== CRITERION 4: Python Typos Fixed (2 points) =====
        python_typos_fixed = 0
        original_typos_python = [
            'authentification', 'syncronize', 'suports',
            'managment', 'defualt', 'proccess'
        ]
        
        if os.path.exists(local_python) and os.path.getsize(local_python) > 10:
            with open(local_python, 'r') as f:
                python_content = f.read().lower()
            
            # Count how many typos are gone
            for typo in original_typos_python:
                if typo not in python_content:
                    python_typos_fixed += 1
            
            if python_typos_fixed >= 5:
                score += 2.0
                feedback.append(f"✅ Python typos fixed: {python_typos_fixed}/6")
                info['python_typos_fixed'] = python_typos_fixed
            elif python_typos_fixed >= 3:
                score += 1.0
                feedback.append(f"◐ Python typos fixed: {python_typos_fixed}/6")
                info['python_typos_fixed'] = python_typos_fixed
            else:
                feedback.append(f"❌ Python: only {python_typos_fixed}/6 typos fixed")
                info['python_typos_fixed'] = python_typos_fixed
        else:
            feedback.append("❌ auth_provider.py not found or empty")
            info['python_typos_fixed'] = 0
        
        # Calculate final score
        score_percentage = int((score / max_score) * 100)
        passed = score >= 7.0  # 70% threshold
        
        feedback_str = " | ".join(feedback)
        summary = f"Score: {score:.1f}/{max_score} ({score_percentage}%)"
        
        logger.info(f"Verification complete. Score: {score}/{max_score}, Passed: {passed}")
        logger.info(f"Details: {info}")
        
        return {
            "passed": passed,
            "score": score_percentage,
            "feedback": f"{summary} | {feedback_str}"
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Clean up temporary directory
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
