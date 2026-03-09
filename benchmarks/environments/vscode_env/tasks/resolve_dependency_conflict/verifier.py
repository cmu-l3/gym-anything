#!/usr/bin/env python3
"""
Verifier for Dependency Conflict Resolution task
"""

import sys
import os
import logging
import tempfile
import json
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_dependency_resolution(traj, env_info, task_info):
    """
    Verify that dependency conflict has been resolved successfully.
    
    Checks:
    1. Configuration Modified: package.json has been edited (20 points)
    2. Valid JSON Syntax: Modified file parses correctly (20 points)
    3. Installation Succeeds: npm install completes without errors (30 points)
    4. No Conflict Errors: No ERESOLVE or peer dependency errors (25 points)
    5. Application Runnable: App can start without module errors (5 bonus points)
    
    Pass threshold: 75%
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='dep_conflict_verify_')
    
    try:
        # Copy necessary files from /tmp
        original_path = os.path.join(temp_dir, 'original_package.json')
        current_path = os.path.join(temp_dir, 'package.json')
        install_log_path = os.path.join(temp_dir, 'install_log.txt')
        start_log_path = os.path.join(temp_dir, 'start_log.txt')
        
        files_copied = {}
        
        # Copy files with error handling
        try:
            copy_from_env("/tmp/original_package.json", original_path)
            files_copied['original'] = True
        except Exception as e:
            logger.warning(f"Failed to copy original_package.json: {e}")
            files_copied['original'] = False
        
        try:
            copy_from_env("/tmp/package.json", current_path)
            files_copied['current'] = True
        except Exception as e:
            logger.warning(f"Failed to copy package.json: {e}")
            files_copied['current'] = False
            return {"passed": False, "score": 0, "feedback": "❌ Could not access package.json"}
        
        try:
            copy_from_env("/tmp/install_log.txt", install_log_path)
            files_copied['install_log'] = True
        except Exception as e:
            logger.warning(f"Failed to copy install_log.txt: {e}")
            files_copied['install_log'] = False
        
        try:
            copy_from_env("/tmp/start_log.txt", start_log_path)
            files_copied['start_log'] = True
        except Exception as e:
            logger.warning(f"Failed to copy start_log.txt: {e}")
            files_copied['start_log'] = False
        
        # Initialize results
        results = {
            'modified': False,
            'valid_syntax': False,
            'install_success': False,
            'no_conflicts': False,
            'app_starts': False
        }
        feedback_parts = []
        
        # Read file contents
        try:
            with open(current_path, 'r') as f:
                current_content = f.read()
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"❌ Could not read package.json: {e}"}
        
        # Check if modified (Criterion 1: 20 points)
        if files_copied.get('original'):
            try:
                with open(original_path, 'r') as f:
                    original_content = f.read()
                
                if original_content.strip() != current_content.strip():
                    results['modified'] = True
                    feedback_parts.append("✅ package.json was modified")
                else:
                    feedback_parts.append("❌ package.json was not changed")
            except Exception as e:
                feedback_parts.append(f"⚠️ Could not compare with original: {e}")
        else:
            # Assume modified if we can't compare
            results['modified'] = True
            feedback_parts.append("⚠️ Assuming modified (no original backup)")
        
        # Validate JSON syntax (Criterion 2: 20 points)
        package_data = None
        try:
            package_data = json.loads(current_content)
            results['valid_syntax'] = True
            feedback_parts.append("✅ Valid JSON syntax")
        except json.JSONDecodeError as e:
            feedback_parts.append(f"❌ Invalid JSON syntax: {e}")
            # If JSON is invalid, we can't proceed
            score = 20 if results['modified'] else 0
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
        
        # Check if the conflict was actually resolved (check versions)
        conflict_resolved_by_version = False
        if package_data:
            dependencies = package_data.get('dependencies', {})
            react_version = dependencies.get('react', '')
            react_dom_version = dependencies.get('react-dom', '')
            
            # Check if react was updated to 18.x
            if react_version and '18' in react_version:
                conflict_resolved_by_version = True
                feedback_parts.append(f"✅ React updated to compatible version: {react_version}")
            elif react_version:
                feedback_parts.append(f"⚠️ React version: {react_version} (may not resolve conflict)")
        
        # Parse installation log (Criteria 3 & 4: 30 + 25 = 55 points)
        if files_copied.get('install_log') and os.path.exists(install_log_path):
            with open(install_log_path, 'r') as f:
                install_output = f.read()
            
            # Check for conflict errors (Criterion 4: 25 points)
            conflict_patterns = [
                'ERESOLVE',
                'could not resolve',
                'peer dep',
                'conflicting',
                'incompatible',
                'unable to resolve',
                'npm ERR! code ERESOLVE'
            ]
            has_conflicts = any(pattern.lower() in install_output.lower() for pattern in conflict_patterns)
            
            # However, check if --legacy-peer-deps was used (which would suppress the error but not really resolve it)
            using_legacy = 'legacy-peer-deps' in install_output.lower()
            
            if not has_conflicts and not using_legacy:
                results['no_conflicts'] = True
                feedback_parts.append("✅ No dependency conflicts detected")
            elif using_legacy:
                feedback_parts.append("⚠️ Installation used --legacy-peer-deps (workaround, not resolution)")
            else:
                feedback_parts.append("❌ Dependency conflicts still present in install output")
            
            # Check for installation success (Criterion 3: 30 points)
            success_patterns = [
                'added',
                'packages in',
                'up to date',
                'audited.*packages'
            ]
            error_patterns = [
                'npm ERR!',
                'ERESOLVE',
                'Exit code: 1',
                'exit code: 1'
            ]
            
            has_success_indicators = any(pattern.lower() in install_output.lower() or 
                                        any(pattern in install_output for pattern in success_patterns) 
                                        for pattern in success_patterns)
            has_error_indicators = any(pattern.lower() in install_output.lower() for pattern in error_patterns)
            
            # Check exit code
            install_succeeded = False
            if 'exit code: 0' in install_output.lower():
                install_succeeded = True
            elif 'exit code:' in install_output.lower() and 'exit code: 0' not in install_output.lower():
                install_succeeded = False
            elif has_success_indicators and not has_error_indicators:
                install_succeeded = True
            
            if install_succeeded:
                results['install_success'] = True
                feedback_parts.append("✅ Installation completed successfully")
            else:
                feedback_parts.append("❌ Installation did not complete successfully")
                # Show a snippet of the error
                lines = install_output.split('\n')
                error_lines = [l for l in lines if 'ERR' in l or 'error' in l.lower()]
                if error_lines:
                    feedback_parts.append(f"   Error: {error_lines[0][:100]}")
        else:
            feedback_parts.append("⚠️ Installation log not available")
        
        # Optional: Check if app starts (Criterion 5: 5 bonus points)
        if files_copied.get('start_log') and os.path.exists(start_log_path):
            with open(start_log_path, 'r') as f:
                start_output = f.read()
            
            error_patterns = [
                'Cannot find module',
                'MODULE_NOT_FOUND',
                'Error:',
                'npm ERR!',
                'ENOENT',
                'peer dep'
            ]
            success_patterns = [
                'Dependencies loaded successfully',
                'Server running',
                'React version:'
            ]
            
            has_start_errors = any(pattern in start_output for pattern in error_patterns)
            has_start_success = any(pattern in start_output for pattern in success_patterns)
            
            if has_start_success and not has_start_errors:
                results['app_starts'] = True
                feedback_parts.append("✅ BONUS: Application starts without errors")
            elif len(start_output.strip()) == 0:
                feedback_parts.append("⚠️ Application start test inconclusive")
            else:
                feedback_parts.append("ℹ️ Application start had issues (not required for passing)")
        
        # Calculate score
        criteria_scores = {
            'modified': 20,
            'valid_syntax': 20,
            'install_success': 30,
            'no_conflicts': 25,
            'app_starts': 5  # Bonus
        }
        
        score = sum(criteria_scores[k] for k, v in results.items() if v)
        passed = score >= 75
        
        # Build final feedback
        feedback_parts.append(f"\n📊 Score: {score}/100")
        feedback_parts.append(f"   Modified: {'✓' if results['modified'] else '✗'} ({criteria_scores['modified']}pts)")
        feedback_parts.append(f"   Valid JSON: {'✓' if results['valid_syntax'] else '✗'} ({criteria_scores['valid_syntax']}pts)")
        feedback_parts.append(f"   Install Success: {'✓' if results['install_success'] else '✗'} ({criteria_scores['install_success']}pts)")
        feedback_parts.append(f"   No Conflicts: {'✓' if results['no_conflicts'] else '✗'} ({criteria_scores['no_conflicts']}pts)")
        if results['app_starts']:
            feedback_parts.append(f"   App Starts: ✓ (+{criteria_scores['app_starts']}pts bonus)")
        
        feedback = "\n".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"❌ Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
