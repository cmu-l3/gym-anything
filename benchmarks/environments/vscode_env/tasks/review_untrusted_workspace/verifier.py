#!/usr/bin/env python3
"""
Verifier for Review Untrusted Workspace task (review_untrusted_workspace@1)
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_security_review(traj, env_info, task_info):
    """
    Verify that workspace security review was completed correctly.
    
    Checks:
    1. SECURITY_REVIEW.md exists and has substantial content (20 points)
    2. Review mentions key files: tasks.json, settings.json, package.json (15 points)
    3. Review identifies suspicious patterns (25 points)
    4. Review includes clear trust decision (20 points)
    5. TRUST_CHECKLIST.md exists and is comprehensive (20 points)
    
    Returns:
        Dict with passed, score, feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    feedback_parts = []
    score = 0.0
    max_score = 100.0
    metadata = {}
    
    # Create temp files for verification
    security_review_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.md')
    trust_checklist_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.md')
    
    try:
        # Copy files from container
        try:
            copy_from_env("/tmp/security_review.md", security_review_temp.name)
        except Exception as e:
            logger.warning(f"Failed to copy security_review.md: {e}")
        
        try:
            copy_from_env("/tmp/trust_checklist.md", trust_checklist_temp.name)
        except Exception as e:
            logger.warning(f"Failed to copy trust_checklist.md: {e}")
        
        # Check 1: Security review document exists and has content (20 points)
        if not os.path.exists(security_review_temp.name) or os.path.getsize(security_review_temp.name) == 0:
            feedback_parts.append("❌ SECURITY_REVIEW.md not found or empty")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        security_review_content = read_file_content(security_review_temp.name)
        content_length = len(security_review_content)
        metadata['security_review_length'] = content_length
        
        if content_length < 200:
            feedback_parts.append(f"⚠️ SECURITY_REVIEW.md exists but seems too short ({content_length} chars)")
            score += 10
        else:
            feedback_parts.append(f"✅ SECURITY_REVIEW.md exists with substantial content ({content_length} chars)")
            score += 20
        
        # Check 2: Review lists files inspected (15 points)
        required_files = ['tasks.json', 'settings.json', 'package.json']
        files_mentioned = 0
        
        for required_file in required_files:
            if required_file.lower() in security_review_content.lower():
                files_mentioned += 1
        
        if files_mentioned >= 3:
            feedback_parts.append(f"✅ All key files mentioned in review ({files_mentioned}/3)")
            score += 15
        elif files_mentioned >= 2:
            feedback_parts.append(f"⚠️ Most key files mentioned ({files_mentioned}/3)")
            score += 10
        else:
            feedback_parts.append(f"❌ Key files not adequately mentioned ({files_mentioned}/3)")
            score += 3
        
        metadata['files_mentioned'] = files_mentioned
        
        # Check 3: Identifies suspicious patterns (25 points)
        # The workspace contains:
        # 1. curl piped to bash in tasks.json
        # 2. postinstall script with curl in package.json
        # 3. Unknown extension in extensions.json
        
        suspicious_patterns = [
            (r'curl.*bash', 'curl | bash'),
            (r'curl.*\bsh\b', 'curl | sh'),
            (r'postinstall', 'postinstall script'),
            (r'wget', 'wget command'),
            (r'malicious', 'malicious'),
            (r'suspicious', 'suspicious'),
            (r'remote.*command', 'remote command execution'),
            (r'network.*request', 'network request'),
            (r'analytics\.example\.com', 'suspicious domain'),
            (r'metrics\.example\.com', 'tracking domain'),
            (r'rsync', 'file sync operation'),
            (r'ssh.*remote', 'remote SSH execution')
        ]
        
        patterns_found = 0
        pattern_names_found = []
        
        for pattern, name in suspicious_patterns:
            if re.search(pattern, security_review_content, re.IGNORECASE):
                patterns_found += 1
                pattern_names_found.append(name)
        
        if patterns_found >= 3:
            feedback_parts.append(f"✅ Identified multiple suspicious patterns ({patterns_found} indicators)")
            score += 25
        elif patterns_found >= 2:
            feedback_parts.append(f"⚠️ Identified some suspicious patterns ({patterns_found} indicators)")
            score += 18
        elif patterns_found >= 1:
            feedback_parts.append(f"⚠️ Identified minimal suspicious patterns ({patterns_found} indicator)")
            score += 10
        else:
            feedback_parts.append("❌ Did not identify suspicious patterns")
        
        metadata['suspicious_patterns_found'] = patterns_found
        metadata['pattern_names'] = pattern_names_found[:5]  # Limit metadata size
        
        # Check 4: Provides trust decision (20 points)
        trust_keywords = [
            'trust', 'trusted', 'untrusted', 'restricted', 
            'safe', 'unsafe', 'risk', 'danger', 'secure',
            'do not trust', 'should not trust', 'recommend against',
            'not safe', 'proceed with caution'
        ]
        
        trust_mentions = 0
        for keyword in trust_keywords:
            if keyword in security_review_content.lower():
                trust_mentions += 1
        
        # Check for actual decision language
        decision_patterns = [
            r'decision:',
            r'should (not )?trust',
            r'(not )?recommend.*trust',
            r'verdict',
            r'conclusion',
            r'(not )?safe to',
            r'proceed with caution',
            r'keep.*restricted'
        ]
        
        has_decision = any(re.search(pattern, security_review_content, re.IGNORECASE) 
                          for pattern in decision_patterns)
        
        if has_decision and trust_mentions >= 2:
            feedback_parts.append("✅ Trust decision clearly documented")
            score += 20
        elif has_decision or trust_mentions >= 1:
            feedback_parts.append("⚠️ Trust decision mentioned but could be clearer")
            score += 12
        else:
            feedback_parts.append("❌ Trust decision not clearly documented")
        
        metadata['has_trust_decision'] = has_decision
        metadata['trust_mentions'] = trust_mentions
        
        # Check 5: Trust checklist exists and is comprehensive (20 points)
        if not os.path.exists(trust_checklist_temp.name) or os.path.getsize(trust_checklist_temp.name) == 0:
            feedback_parts.append("❌ TRUST_CHECKLIST.md not found or empty")
        else:
            checklist_content = read_file_content(trust_checklist_temp.name)
            checklist_length = len(checklist_content)
            metadata['checklist_length'] = checklist_length
            
            if checklist_length < 100:
                feedback_parts.append(f"⚠️ TRUST_CHECKLIST.md exists but seems too short ({checklist_length} chars)")
                score += 5
            else:
                # Count categories/patterns in checklist
                checklist_patterns = [
                    'command execution',
                    'command injection',
                    'shell',
                    'network',
                    'file system',
                    'file operation',
                    'auto-run',
                    'autorun',
                    'extension',
                    'script',
                    'curl',
                    'wget',
                    'chmod',
                    'rm ',
                    'ssh',
                    'rsync',
                    'postinstall',
                    'preinstall',
                    'base64',
                    'encode',
                    'obfuscate'
                ]
                
                categories_covered = 0
                for pattern in checklist_patterns:
                    if pattern in checklist_content.lower():
                        categories_covered += 1
                
                # Count sections/headers (indicates organization)
                section_markers = checklist_content.count('#') + checklist_content.count('-') // 3
                
                if categories_covered >= 5 or section_markers >= 5:
                    feedback_parts.append(f"✅ Comprehensive checklist ({categories_covered} security topics)")
                    score += 20
                elif categories_covered >= 3 or section_markers >= 3:
                    feedback_parts.append(f"⚠️ Basic checklist ({categories_covered} security topics)")
                    score += 12
                else:
                    feedback_parts.append(f"⚠️ Incomplete checklist ({categories_covered} security topics)")
                    score += 7
                
                metadata['checklist_categories'] = categories_covered
        
        # Normalize score
        normalized_score = score / max_score
        success = normalized_score >= 0.70
        
        feedback = " | ".join(feedback_parts)
        feedback += f"\n\nFinal Score: {score:.1f}/{max_score} ({normalized_score*100:.1f}%)"
        
        if success:
            feedback += "\n\n🎉 Task completed successfully! Workspace security review performed correctly."
        else:
            feedback += "\n\n❌ Task incomplete. Review needs more detail or missing required components."
        
        return {
            "passed": success,
            "score": int(normalized_score * 100),
            "feedback": feedback,
            "metadata": metadata
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Cleanup temp files
        if os.path.exists(security_review_temp.name):
            os.unlink(security_review_temp.name)
        if os.path.exists(trust_checklist_temp.name):
            os.unlink(trust_checklist_temp.name)
