#!/usr/bin/env python3
"""
Verifier for Wine PCA and Clustering Task.

Scoring Breakdown (100 pts):
1. R Script (10 pts): Exists, modified, contains keywords.
2. PCA Summary (20 pts): Exists, 11 components, scaling verified (eigen sum ~11).
3. Silhouette Analysis (15 pts): Exists, optimal k found.
4. Cluster Results (35 pts): Exists, 6497 rows (critical), contains PC columns.
5. Visualization (20 pts): PNG exists and is substantial (>50KB).

Pass Threshold: 60 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_wine_pca_clustering(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    files = result.get('files', {})
    content = result.get('content', {})

    # 1. R Script Checks (10 pts)
    script = files.get('script', {})
    if script.get('exists') and script.get('is_new'):
        if result.get('script_has_keywords'):
            score += 10
            feedback.append("R script created and contains key functions (10/10)")
        else:
            score += 5
            feedback.append("R script created but missing 'prcomp'/'kmeans' keywords (5/10)")
    else:
        feedback.append("R script not created or modified (0/10)")

    # 2. PCA Summary (20 pts)
    pca = files.get('pca_csv', {})
    if pca.get('exists') and pca.get('is_new'):
        score += 5
        # Check content
        eigen_sum = content.get('pca_eigen_sum', 0)
        # Expected sum is 11 (number of features) if scaled, or very large if not
        if 10.5 <= eigen_sum <= 11.5:
            score += 15
            feedback.append(f"PCA Summary valid (Eigenvalue sum {eigen_sum:.2f} ≈ 11) (15/15)")
        else:
            feedback.append(f"PCA Summary exists but scaling likely missing (Eigenvalue sum {eigen_sum:.2f} != 11) (0/15)")
    else:
        feedback.append("PCA Summary CSV missing (0/20)")

    # 3. Silhouette Analysis (15 pts)
    sil = files.get('sil_csv', {})
    if sil.get('exists') and sil.get('is_new'):
        score += 5
        best_k = content.get('best_k', 0)
        # We expect k=2 for Red vs White, but k=3 is sometimes found depending on seed/implementation
        if best_k in [2, 3]:
            score += 10
            feedback.append(f"Silhouette analysis valid (Optimal k={best_k}) (10/10)")
        else:
            score += 5
            feedback.append(f"Silhouette analysis found unusual k={best_k} (5/10)")
    else:
        feedback.append("Silhouette CSV missing (0/15)")

    # 4. Cluster Results (35 pts)
    res = files.get('res_csv', {})
    if res.get('exists') and res.get('is_new'):
        score += 10
        rows = content.get('cluster_rows', 0)
        if rows == 6497:
            score += 15
            feedback.append("Cluster results row count correct (6497) (15/15)")
        else:
            feedback.append(f"Cluster results row count incorrect ({rows} != 6497) (0/15)")
            
        if content.get('has_pc_cols'):
            score += 10
            feedback.append("Cluster results contain PC columns (10/10)")
        else:
            feedback.append("Cluster results missing PC columns (0/10)")
    else:
        feedback.append("Cluster results CSV missing (0/35)")

    # 5. Visualization (20 pts)
    plot = files.get('plot_png', {})
    if plot.get('exists') and plot.get('is_new'):
        size_kb = plot.get('size', 0) / 1024
        if size_kb > 50:
            score += 20
            feedback.append(f"Analysis plot created and substantial ({size_kb:.1f}KB) (20/20)")
        else:
            score += 5
            feedback.append(f"Analysis plot created but too small ({size_kb:.1f}KB) (5/20)")
    else:
        feedback.append("Analysis plot missing (0/20)")

    # Final tally
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }