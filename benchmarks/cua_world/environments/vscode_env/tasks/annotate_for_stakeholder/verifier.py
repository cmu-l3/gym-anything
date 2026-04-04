#!/usr/bin/env python3
"""
Verifier for Annotate for Stakeholder task
"""

import sys
import os
import logging
import tempfile
import ast
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_task(traj, env_info, task_info):
    """
    Verify that stakeholder-focused code annotation was completed.
    
    Checks:
    1. File exists and is readable
    2. Python syntax is valid (no broken code)
    3. At least 4 meaningful comments added (>10 chars, not docstrings)
    4. Comments explain 2+ key business rules (enterprise 20%, annual 15%, $99 min)
    5. Function logic unchanged (key elements still present)
    6. Comments use business-friendly language
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    container_path = "/home/ga/workspace/pricing_service/src/pricing.py"
    temp_file = tempfile.NamedTemporaryFile(mode='w+', suffix='.py', delete=False)
    
    try:
        # Copy the modified file
        try:
            copy_from_env(container_path, temp_file.name)
        except Exception as e:
            logger.error(f"Failed to copy pricing.py: {e}")
            return {"passed": False, "score": 0, "feedback": f"Could not access pricing.py: {e}"}
        
        # Read content
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return {"passed": False, "score": 0, "feedback": "File not found or empty"}
        
        try:
            with open(temp_file.name, 'r', encoding='utf-8') as f:
                content = f.read()
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not read file: {e}"}
        
        criteria_passed = 0
        max_criteria = 5
        feedback_parts = []
        
        # Criterion 1: Validate Python syntax
        try:
            ast.parse(content)
            criteria_passed += 1
            feedback_parts.append("✅ Python syntax valid")
        except SyntaxError as e:
            feedback_parts.append(f"❌ Syntax error introduced: {e}")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
        # Extract function body
        func_start = content.find('def calculate_subscription_price')
        if func_start == -1:
            return {"passed": False, "score": 0, "feedback": "calculate_subscription_price function not found"}
        
        # Find end of function
        func_end = content.find('\ndef ', func_start + 10)
        if func_end == -1:
            func_end = content.find('\nclass ', func_start + 10)
        if func_end == -1:
            func_end = len(content)
        
        function_body = content[func_start:func_end]
        
        # Criterion 2: Count meaningful inline comments (exclude trivial ones and docstrings)
        comment_lines = []
        in_docstring = False
        
        for line in function_body.split('\n'):
            stripped = line.strip()
            
            # Skip docstring lines
            if '"""' in stripped or "'''" in stripped:
                in_docstring = not in_docstring
                continue
            if in_docstring:
                continue
            
            # Check for comments
            if stripped.startswith('#'):
                comment_text = stripped[1:].strip()
                # Must be meaningful (>10 chars, not just punctuation)
                if len(comment_text) > 10 and any(c.isalpha() for c in comment_text):
                    # Exclude trivial comments
                    trivial_patterns = [
                        r'^apply discount',
                        r'^discount$',
                        r'^calculate',
                        r'^return'
                    ]
                    is_trivial = any(re.match(pat, comment_text.lower()) for pat in trivial_patterns)
                    if not is_trivial:
                        comment_lines.append(comment_text.lower())
        
        if len(comment_lines) >= 4:
            criteria_passed += 1
            feedback_parts.append(f"✅ Found {len(comment_lines)} meaningful comments")
        else:
            feedback_parts.append(f"❌ Insufficient comments: found {len(comment_lines)}, need ≥4 meaningful ones")
        
        # Criterion 3: Check for key business rule mentions
        all_comments = ' '.join(comment_lines)
        
        # Check for enterprise discount (20%)
        enterprise_mentioned = any(term in all_comments for term in [
            'enterprise', '20%', '20 percent', 'twenty percent', '0.20', 'volume discount'
        ])
        
        # Check for annual discount (15%)
        annual_mentioned = any(term in all_comments for term in [
            'annual', 'yearly', '15%', '15 percent', 'fifteen percent', '0.15', 'billing cycle'
        ])
        
        # Check for minimum price ($99)
        minimum_mentioned = any(term in all_comments for term in [
            'minimum', 'floor', '$99', '99', 'never below', 'at least', 'never go below', 'never charge less'
        ])
        
        rules_explained = sum([enterprise_mentioned, annual_mentioned, minimum_mentioned])
        
        if rules_explained >= 2:
            criteria_passed += 1
            rules_found = []
            if enterprise_mentioned:
                rules_found.append("Enterprise 20%")
            if annual_mentioned:
                rules_found.append("Annual 15%")
            if minimum_mentioned:
                rules_found.append("$99 min")
            feedback_parts.append(f"✅ Explained {rules_explained}/3 key rules: {', '.join(rules_found)}")
        else:
            feedback_parts.append(f"❌ Comments don't explain key rules. Found {rules_explained}/3")
        
        # Criterion 4: Verify critical logic still exists (unchanged)
        required_elements = [
            'CustomerTier.ENTERPRISE',
            'ENTERPRISE_DISCOUNT',
            'ANNUAL_DISCOUNT',
            'MINIMUM_PRICE',
            'max(price, MINIMUM_PRICE)'
        ]
        
        all_present = all(element in content for element in required_elements)
        
        if all_present:
            criteria_passed += 1
            feedback_parts.append("✅ Function logic preserved")
        else:
            missing = [e for e in required_elements if e not in content]
            feedback_parts.append(f"❌ Logic modified: {', '.join(missing)} missing")
        
        # Criterion 5: Check for business-friendly language (not too technical)
        # Look for business terms vs technical jargon
        business_terms = ['customer', 'subscription', 'discount', 'price', 'pricing', 
                          'billing', 'annual', 'monthly', 'enterprise']
        technical_jargon = ['decimal precision', 'multiplicative', 'enum', 'type hint', 
                           'float', 'instantiate', 'parameter']
        
        business_term_count = sum(1 for term in business_terms if term in all_comments)
        jargon_count = sum(1 for term in technical_jargon if term in all_comments)
        
        # Should have more business terms than jargon
        if business_term_count >= 2 and jargon_count == 0:
            criteria_passed += 1
            feedback_parts.append("✅ Comments use business-friendly language")
        elif business_term_count >= 1:
            # Partial credit - has some business terms
            criteria_passed += 0.5
            feedback_parts.append("⚠️ Comments somewhat business-focused")
        else:
            feedback_parts.append("❌ Comments lack business-friendly language")
        
        # Calculate score
        score = int((criteria_passed / max_criteria) * 100)
        passed = score >= 70  # Pass threshold
        
        # Bonus: If all 3 rules explained, bump score
        if rules_explained == 3 and len(comment_lines) >= 5:
            score = min(100, score + 10)
            passed = True
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
