#!/usr/bin/env python3
"""
Verifier for Generate Mock Data task
"""

import sys
import os
import logging
import tempfile
import shutil
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_mock_data_generator(traj, env_info, task_info):
    """
    Verify mock data generator task completion.
    
    Checks:
    1. File created with substantial content
    2. Multiple entity types (users, products, orders)
    3. Multiple functions with clear organization
    4. Referential integrity (IDs maintained)
    5. Calculation logic (order totals)
    6. Random data generation mechanism
    7. Bonus: Edge case handling
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='mock_data_verify_')
    
    try:
        output_dir = "/tmp/mock_data_task"
        
        # Try to find the generated file
        possible_files = [
            "mockDataGenerator.ts",
            "mockDataGenerator.js",
            "generator.ts",
            "generator.js",
            "mockData.ts",
            "mockData.js",
            "dataGenerator.ts",
            "dataGenerator.js"
        ]
        
        found_file = None
        found_filename = None
        
        for filename in possible_files:
            file_path = os.path.join(output_dir, filename)
            local_path = os.path.join(temp_dir, filename)
            
            try:
                copy_from_env(file_path, local_path)
                if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
                    found_file = local_path
                    found_filename = filename
                    logger.info(f"Found generator file: {filename}")
                    break
            except Exception as e:
                logger.debug(f"File not found: {filename} - {e}")
                continue
        
        # If no specific file found, try to find any .ts or .js file
        if not found_file:
            workspace_listing_path = os.path.join(output_dir, "workspace_listing.txt")
            local_listing = os.path.join(temp_dir, "workspace_listing.txt")
            
            try:
                copy_from_env(workspace_listing_path, local_listing)
                
                if os.path.exists(local_listing):
                    with open(local_listing, 'r') as f:
                        listing = f.read()
                    
                    # Find .ts or .js files in listing
                    for line in listing.split('\n'):
                        if line.endswith('.ts') or line.endswith('.js'):
                            if 'config' not in line.lower() and 'package' not in line.lower():
                                filename = line.split()[-1]
                                file_path = f"/home/ga/workspace/ecommerce-mocks/{filename}"
                                local_path = os.path.join(temp_dir, filename)
                                
                                try:
                                    copy_from_env(file_path, local_path)
                                    if os.path.exists(local_path) and os.path.getsize(local_path) > 100:
                                        found_file = local_path
                                        found_filename = filename
                                        logger.info(f"Found file from listing: {filename}")
                                        break
                                except:
                                    continue
            except Exception as e:
                logger.warning(f"Could not read workspace listing: {e}")
        
        if not found_file:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ No generator file found in workspace (expected mockDataGenerator.ts or .js)"
            }
        
        # Read file content
        content = read_file_content(found_file)
        
        if not content:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ File {found_filename} is empty"
            }
        
        score = 0
        max_score = 100
        feedback_parts = []
        
        # Criterion 1: File exists with substantial content (10 points)
        if len(content) >= 500:
            score += 10
            feedback_parts.append(f"✅ File created with substantial code ({len(content)} characters)")
        elif len(content) >= 200:
            score += 5
            feedback_parts.append(f"⚠️ File has limited content ({len(content)} characters)")
        else:
            feedback_parts.append(f"❌ File is too short ({len(content)} characters, expected 500+)")
        
        # Criterion 2: Entity type generation (25 points)
        entity_checks = {
            'user': ['user', 'customer', 'account'],
            'product': ['product', 'item', 'sku'],
            'order': ['order', 'purchase', 'transaction']
        }
        
        entities_found = []
        for entity_type, patterns in entity_checks.items():
            if any(re.search(rf'\b{pattern}\b', content, re.IGNORECASE) for pattern in patterns):
                entities_found.append(entity_type)
        
        if len(entities_found) >= 3:
            score += 25
            feedback_parts.append(f"✅ All entity types found: {', '.join(entities_found)}")
        elif len(entities_found) >= 2:
            score += 15
            feedback_parts.append(f"⚠️ Found {len(entities_found)} entity types: {', '.join(entities_found)} (missing some)")
        elif len(entities_found) >= 1:
            score += 8
            feedback_parts.append(f"⚠️ Found only {len(entities_found)} entity type: {', '.join(entities_found)}")
        else:
            feedback_parts.append("❌ No clear entity types found (user, product, order)")
        
        # Criterion 3: Function organization (15 points)
        function_patterns = [
            r'function\s+\w+',
            r'const\s+\w+\s*=\s*\(',
            r'export\s+function',
            r'export\s+const\s+\w+\s*=',
            r'function\s+generate',
            r'const\s+generate\w+\s*='
        ]
        
        functions_found = 0
        for pattern in function_patterns:
            functions_found += len(re.findall(pattern, content, re.IGNORECASE))
        
        # Deduplicate by looking at unique function names
        function_names = set()
        for match in re.finditer(r'(?:function\s+|const\s+)(\w+)', content):
            function_names.add(match.group(1))
        
        unique_functions = len(function_names)
        
        if unique_functions >= 5:
            score += 15
            feedback_parts.append(f"✅ Well-organized with {unique_functions} functions")
        elif unique_functions >= 3:
            score += 10
            feedback_parts.append(f"✅ Contains {unique_functions} functions")
        elif unique_functions >= 2:
            score += 5
            feedback_parts.append(f"⚠️ Limited function organization ({unique_functions} functions)")
        else:
            feedback_parts.append(f"❌ Insufficient function organization ({unique_functions} function(s))")
        
        # Criterion 4: Referential integrity (15 points)
        relationship_patterns = [
            r'\bid\b',
            r'userId',
            r'productId',
            r'customerId',
            r'orderId',
            r'user\.id',
            r'product\.id',
            r'\.id\b'
        ]
        
        relationships_found = 0
        for pattern in relationship_patterns:
            if re.search(pattern, content, re.IGNORECASE):
                relationships_found += 1
        
        if relationships_found >= 3:
            score += 15
            feedback_parts.append("✅ Maintains referential integrity with IDs")
        elif relationships_found >= 2:
            score += 10
            feedback_parts.append("⚠️ Some relationship handling present")
        elif relationships_found >= 1:
            score += 5
            feedback_parts.append("⚠️ Limited relationship handling")
        else:
            feedback_parts.append("❌ Missing referential integrity (no ID references)")
        
        # Criterion 5: Calculation logic (15 points)
        calculation_patterns = [
            r'\btotal\b',
            r'\bsubtotal\b',
            r'\btax\b',
            r'\bshipping\b',
            r'\bdiscount\b',
            r'price\s*[\+\-\*]',
            r'[\+\-\*]\s*price',
            r'reduce\s*\(',
            r'sum\s*\('
        ]
        
        calculations_found = 0
        for pattern in calculation_patterns:
            if re.search(pattern, content, re.IGNORECASE):
                calculations_found += 1
        
        if calculations_found >= 4:
            score += 15
            feedback_parts.append("✅ Comprehensive calculation logic (totals, subtotal, tax, shipping)")
        elif calculations_found >= 2:
            score += 10
            feedback_parts.append("⚠️ Some calculation logic present")
        elif calculations_found >= 1:
            score += 5
            feedback_parts.append("⚠️ Limited calculation logic")
        else:
            feedback_parts.append("❌ Missing calculation logic")
        
        # Criterion 6: Random data generation (10 points)
        random_patterns = [
            r'Math\.random',
            r'faker',
            r'\brandom\b',
            r'seed',
            r'Math\.floor.*random',
            r'random.*select',
            r'random.*choice'
        ]
        
        has_randomization = any(re.search(pattern, content, re.IGNORECASE) for pattern in random_patterns)
        
        if has_randomization:
            score += 10
            feedback_parts.append("✅ Implements random data generation")
        else:
            feedback_parts.append("⚠️ No clear randomization mechanism")
        
        # Criterion 7: Edge cases (10 points bonus)
        edge_case_patterns = [
            r'international',
            r'currency',
            r'bulk',
            r'promo',
            r'discount',
            r'\bcountry\b',
            r'locale',
            r'address.*country',
            r'quantity.*>.*\d',
            r'items\.length'
        ]
        
        edge_cases_found = 0
        for pattern in edge_case_patterns:
            if re.search(pattern, content, re.IGNORECASE):
                edge_cases_found += 1
        
        if edge_cases_found >= 3:
            score += 10
            feedback_parts.append("✅ Bonus: Handles edge cases (international, bulk, variety)")
        elif edge_cases_found >= 1:
            score += 5
            feedback_parts.append("⚠️ Some edge case handling")
        
        # Normalize score to 0-100
        score = min(100, max(0, score))
        passed = score >= 70
        
        # Build feedback message
        feedback_header = f"\n{'='*60}\nMock Data Generator Verification\n{'='*60}\n"
        feedback_body = "\n".join(feedback_parts)
        feedback_footer = f"\n{'='*60}\nFINAL SCORE: {score:.0f}/100\n"
        
        if passed:
            feedback_footer += "✅ PASS: Functional mock data generator created\n"
        else:
            feedback_footer += "❌ FAIL: Insufficient implementation (need 70+ to pass)\n"
        
        feedback = feedback_header + feedback_body + feedback_footer
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
