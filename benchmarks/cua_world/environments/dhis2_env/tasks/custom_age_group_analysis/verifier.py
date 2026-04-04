#!/usr/bin/env python3
"""
Verifier for custom_age_group_analysis task.

Scoring Criteria (100 points total):
1. Category Option Groups Created (40 pts total)
   - 'Under 5 Years' group exists and contains valid options (20 pts)
   - 'Over 5 Years' group exists (20 pts)
2. Category Option Group Set Created (35 pts total)
   - 'Broad Age Analysis' group set exists (20 pts)
   - Data Dimension is enabled (CRITICAL) (15 pts)
3. Visualization Created (25 pts total)
   - Visualization exists and uses the created dimension (25 pts)

Pass Threshold: 60 points
"""

import json
import tempfile
import os
import logging
import re

logger = logging.getLogger(__name__)

def verify_custom_age_group_analysis(traj, env_info, task_info):
    """Verify DHIS2 metadata configuration for age group analysis."""
    
    # 1. Retrieve result file from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/custom_age_group_analysis_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        try:
            with open(temp_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}
        finally:
            os.unlink(temp_path)

        score = 0
        feedback_parts = []
        
        # 2. Analyze Category Option Groups
        cogs = result.get('categoryOptionGroups', [])
        
        # Find "Under 5" group
        u5_group = None
        for g in cogs:
            if 'under 5' in g.get('name', '').lower() or '< 5' in g.get('name', '').lower():
                u5_group = g
                break
        
        # Find "Over 5" group
        o5_group = None
        for g in cogs:
            if 'over 5' in g.get('name', '').lower() or '5 and over' in g.get('name', '').lower() or '> 5' in g.get('name', '').lower():
                o5_group = g
                break

        # Check U5 Group
        if u5_group:
            opts = u5_group.get('categoryOptions', [])
            # Verify it has options like "0-11m" or "1-4y"
            has_valid_opts = any(re.search(r'0-11|1-4|<1|< 1', opt.get('name', '')) for opt in opts)
            
            if has_valid_opts:
                score += 20
                feedback_parts.append("'Under 5' group created with correct options (+20)")
            elif len(opts) > 0:
                score += 15
                feedback_parts.append("'Under 5' group created but options logic unclear (+15)")
            else:
                score += 10
                feedback_parts.append("'Under 5' group created but empty (+10)")
        else:
            feedback_parts.append("'Under 5' group not found")

        # Check O5 Group
        if o5_group:
            score += 20
            feedback_parts.append("'Over 5' group created (+20)")
        else:
            feedback_parts.append("'Over 5' group not found")

        # 3. Analyze Category Option Group Sets
        cog_sets = result.get('categoryOptionGroupSets', [])
        target_set = None
        
        for s in cog_sets:
            if 'broad age' in s.get('name', '').lower():
                target_set = s
                break
        
        target_set_id = None
        if target_set:
            score += 20
            target_set_id = target_set.get('id')
            feedback_parts.append("'Broad Age Analysis' group set created (+20)")
            
            # Check Data Dimension flag
            if target_set.get('dataDimension', False):
                score += 15
                feedback_parts.append("Data Dimension enabled (+15)")
            else:
                feedback_parts.append("Data Dimension NOT enabled - won't appear in visualizer")
        else:
            feedback_parts.append("'Broad Age Analysis' group set not found")

        # 4. Analyze Visualization
        # Check if any new visualization uses the group set ID as a dimension
        visualizations = result.get('visualizations', [])
        viz_valid = False
        
        if target_set_id:
            for viz in visualizations:
                # Collect all dimensions used
                dims = []
                dims.extend(viz.get('columnDimensions', []))
                dims.extend(viz.get('rowDimensions', []))
                dims.extend(viz.get('filterDimensions', []))
                
                # Check if our group set ID is in the dimensions list
                # Dimensions are usually list of strings (IDs) or objects with 'id'
                for d in dims:
                    d_id = d if isinstance(d, str) else d.get('id', '')
                    # Group Sets as dimensions are often referenced by their ID
                    # or sometimes as "categoryOptionGroupSet:ID"
                    if target_set_id in d_id:
                        viz_valid = True
                        break
                if viz_valid:
                    break
        
        if viz_valid:
            score += 25
            feedback_parts.append("Visualization created using the custom dimension (+25)")
        elif len(visualizations) > 0 and target_set_id:
            feedback_parts.append("Visualization created but custom dimension not found in it")
        elif len(visualizations) > 0:
             feedback_parts.append("Visualization created but could not verify dimension (Group Set missing)")
        else:
            feedback_parts.append("No new visualization found")

        return {
            "passed": score >= 60,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.exception("Unexpected error in verifier")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}