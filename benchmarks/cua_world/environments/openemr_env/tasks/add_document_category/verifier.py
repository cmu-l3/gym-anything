#!/usr/bin/env python3
"""
Verifier for Add Document Category task in OpenEMR

Verifies that a new document category named "Prior Authorizations" was created
in the OpenEMR document management system.

Uses copy_from_env to read pre-exported verification data from the container.
The export_result.sh script queries the database and saves results to JSON.

Scoring (100 points total):
- Category exists matching "Prior Authorization": 40 points
- Category was newly created (ID > initial max): 25 points
- Category name is correct: 20 points
- Category has proper parent structure: 10 points
- VLM workflow confirmation: 5 points

Pass threshold: 65 points with "Category Exists" criterion met
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_document_category(traj, env_info, task_info):
    """
    Verify that the expected document category was added to OpenEMR.
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    # Get expected values from task_info metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_category_name', 'Prior Authorizations')
    expected_keywords = metadata.get('expected_name_keywords', ['prior', 'authorization'])
    
    # Scoring weights from metadata (with defaults)
    score_category_exists = metadata.get('score_category_exists', 40)
    score_newly_created = metadata.get('score_newly_created', 25)
    score_correct_name = metadata.get('score_correct_name', 20)
    score_proper_structure = metadata.get('score_proper_structure', 10)
    score_vlm_workflow = metadata.get('score_vlm_workflow', 5)
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/add_document_category_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "category_exists": False,
            "newly_created": False,
            "correct_name": False,
            "proper_structure": False,
            "vlm_workflow": False
        }
        
        # Extract data from exported result
        initial_count = result.get('initial_category_count', 0)
        current_count = result.get('current_category_count', 0)
        initial_max_id = result.get('initial_max_category_id', 0)
        category_found = result.get('category_found', False)
        category = result.get('category', {})
        newly_created = result.get('newly_created', False)
        parent_valid = result.get('parent_valid', False)
        
        logger.info(f"Result data: initial_count={initial_count}, current_count={current_count}")
        logger.info(f"Category found: {category_found}, category: {category}")
        logger.info(f"Newly created: {newly_created}, initial_max_id: {initial_max_id}")
        
        # CRITERION 1: Category exists (40 points)
        if category_found:
            score += score_category_exists
            subscores["category_exists"] = True
            feedback_parts.append(f"✅ Document category found matching 'Prior Authorization'")
        else:
            feedback_parts.append(f"❌ No document category matching 'Prior Authorization' found")
            
            # Check if any new categories were added at all
            if current_count > initial_count:
                new_count = current_count - initial_count
                feedback_parts.append(f"Note: {new_count} new category(ies) added, but not matching expected name")
            else:
                feedback_parts.append("No new categories were added to the database")
            
            # Early return since category not found
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }
        
        # CRITERION 2: Newly created during task (25 points)
        # This is critical for anti-gaming - must detect if category was created during task
        category_id_str = category.get('id', '0')
        try:
            category_id = int(category_id_str) if category_id_str else 0
        except ValueError:
            category_id = 0
        
        if newly_created or (category_id > initial_max_id):
            score += score_newly_created
            subscores["newly_created"] = True
            feedback_parts.append(f"✅ Category was newly created during task (ID={category_id} > {initial_max_id})")
        else:
            feedback_parts.append(f"⚠️ Category may have existed before task (ID={category_id}, initial_max={initial_max_id})")
            # Partial credit if category count increased
            if current_count > initial_count:
                score += score_newly_created // 2
                feedback_parts.append(f"  Partial credit: category count increased ({initial_count} → {current_count})")
        
        # CRITERION 3: Correct name (20 points)
        category_name = category.get('name', '').strip()
        name_lower = category_name.lower()
        
        # Check if name contains required keywords
        keywords_found = all(kw.lower() in name_lower for kw in expected_keywords)
        
        if keywords_found:
            score += score_correct_name
            subscores["correct_name"] = True
            feedback_parts.append(f"✅ Category name '{category_name}' contains required keywords")
        else:
            # Partial credit for having some keywords
            keywords_present = [kw for kw in expected_keywords if kw.lower() in name_lower]
            if keywords_present:
                partial_score = (len(keywords_present) / len(expected_keywords)) * score_correct_name
                score += int(partial_score)
                feedback_parts.append(f"⚠️ Category name '{category_name}' partially matches (found: {keywords_present})")
            else:
                feedback_parts.append(f"❌ Category name '{category_name}' does not match expected '{expected_name}'")
        
        # CRITERION 4: Proper structure/parent (10 points)
        category_parent = category.get('parent', '')
        try:
            parent_id = int(category_parent) if category_parent else -1
        except ValueError:
            parent_id = -1
        
        if parent_valid and parent_id >= 0:
            score += score_proper_structure
            subscores["proper_structure"] = True
            feedback_parts.append(f"✅ Category has valid parent (parent_id={parent_id})")
        else:
            feedback_parts.append(f"⚠️ Category parent structure may be invalid (parent={category_parent})")
        
        # CRITERION 5: VLM workflow confirmation (5 points)
        # Check trajectory screenshots to confirm agent navigated through admin interface
        vlm_confirmed = False
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm and traj:
            try:
                # Sample frames from trajectory
                frames = traj.get('frames', [])
                if frames and len(frames) >= 3:
                    # Get a few samples from the trajectory
                    sample_indices = [
                        len(frames) // 4,
                        len(frames) // 2,
                        3 * len(frames) // 4,
                        -1  # Last frame
                    ]
                    sample_frames = [frames[min(i, len(frames)-1)] for i in sample_indices if i < len(frames)]
                    
                    if sample_frames:
                        vlm_prompt = """You are verifying if a computer agent successfully navigated to the document categories administration in OpenEMR.

Look at these screenshots from the agent's session and determine:
1. Did the agent access the OpenEMR Administration menu?
2. Did the agent navigate to Document Categories management?
3. Did the agent appear to add or create a new category?
4. Is there evidence of a "Prior Authorization" category being added?

Respond in JSON format:
{
    "accessed_admin": true/false,
    "navigated_to_categories": true/false,
    "added_category": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""
                        vlm_result = query_vlm(
                            prompt=vlm_prompt,
                            images=sample_frames[-2:] if len(sample_frames) >= 2 else sample_frames
                        )
                        
                        if vlm_result.get('success'):
                            parsed = vlm_result.get('parsed', {})
                            if parsed.get('added_category') or parsed.get('navigated_to_categories'):
                                vlm_confirmed = True
                                score += score_vlm_workflow
                                subscores["vlm_workflow"] = True
                                feedback_parts.append(f"✅ VLM confirmed admin navigation workflow")
                            else:
                                feedback_parts.append(f"⚠️ VLM could not confirm navigation to categories admin")
                        else:
                            feedback_parts.append(f"⚠️ VLM verification failed: {vlm_result.get('error', 'Unknown')}")
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")
                feedback_parts.append(f"⚠️ VLM verification skipped due to error")
        else:
            feedback_parts.append("⚠️ VLM verification not available")
        
        # Determine pass/fail
        # Must have category_exists to pass, and score >= 65
        key_criteria_met = subscores["category_exists"]
        passed = score >= 65 and key_criteria_met
        
        # Build final feedback
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "category_name": category_name,
                "category_id": category_id,
                "initial_count": initial_count,
                "current_count": current_count,
                "newly_created": newly_created
            }
        }
        
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Result file not found - export may have failed"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to parse result JSON: {e}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }


# Additional helper for standalone testing
if __name__ == "__main__":
    # Test with mock data
    mock_result = {
        "initial_category_count": 10,
        "current_category_count": 11,
        "initial_max_category_id": 15,
        "category_found": True,
        "category": {
            "id": "16",
            "name": "Prior Authorizations",
            "parent": "1"
        },
        "newly_created": True,
        "parent_valid": True,
        "screenshot_exists": True
    }
    
    # Mock env_info with copy_from_env that reads from local file
    import tempfile
    import json
    
    temp_file = tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False)
    json.dump(mock_result, temp_file)
    temp_file.close()
    
    def mock_copy(src, dst):
        import shutil
        shutil.copy(temp_file.name, dst)
    
    mock_env_info = {
        'copy_from_env': mock_copy
    }
    mock_task_info = {
        'metadata': {
            'expected_category_name': 'Prior Authorizations',
            'expected_name_keywords': ['prior', 'authorization']
        }
    }
    
    result = verify_add_document_category({}, mock_env_info, mock_task_info)
    print(json.dumps(result, indent=2))
    
    os.unlink(temp_file.name)