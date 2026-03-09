#!/usr/bin/env python3
"""
Verifier for chinook_reporting_db task.

Scoring Breakdown (100 points total):
- Database file exists and created during task: 5 pts
- DBeaver connection 'ChinookReports' exists: 10 pts
- 'artist_summary' table valid (schema + rows + values): 25 pts
- 'genre_revenue' table valid (schema + rows + values): 25 pts
- 'monthly_sales' table valid (schema + rows + values): 25 pts
- SQL script saved: 10 pts

Pass threshold: 60 points
"""

import json
import logging
import os
import tempfile
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_reporting_db(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    gt = result.get("ground_truth", {})
    
    # 1. DB File Check (5 pts)
    if result.get("db_exists") and result.get("db_created_during_task"):
        score += 5
        feedback.append("Database file created successfully.")
    else:
        feedback.append("Database file missing or pre-existing.")

    # 2. Connection Check (10 pts)
    if result.get("connection_found"):
        score += 10
        feedback.append("DBeaver connection found.")
    else:
        feedback.append("DBeaver connection 'ChinookReports' not found.")

    # 3. artist_summary Check (25 pts)
    # Schema check
    artist_res = result.get("tables", {}).get("artist_summary", {})
    required_cols_artist = ["ArtistId", "ArtistName", "AlbumCount", "TrackCount", "TotalDurationMinutes", "AvgTrackDurationSeconds"]
    
    if artist_res.get("exists"):
        # Check columns (case-insensitive partial match for robustness)
        cols_present = artist_res.get("columns", "").lower()
        if all(c.lower() in cols_present for c in required_cols_artist):
            score += 5
        else:
            feedback.append("artist_summary missing required columns.")

        # Check Row Count (Should match ground truth artist count ~275)
        gt_artists = gt.get("artist_count", 275)
        if artist_res.get("rows") == gt_artists:
            score += 10
        else:
            feedback.append(f"artist_summary row count mismatch: {artist_res.get('rows')} vs {gt_artists}")

        # Spot Check Values (Iron Maiden)
        gt_im_stats = gt.get("iron_maiden_stats", "0|0|0").split("|")
        gt_im_albums = int(gt_im_stats[0])
        gt_im_tracks = int(gt_im_stats[1])
        # Allow slight tolerance on float calc
        
        if abs(artist_res.get("im_albums", 0) - gt_im_albums) <= 1:
            score += 5
        if abs(artist_res.get("im_tracks", 0) - gt_im_tracks) <= 2:
            score += 5
    else:
        feedback.append("artist_summary table not found.")

    # 4. genre_revenue Check (25 pts)
    genre_res = result.get("tables", {}).get("genre_revenue", {})
    required_cols_genre = ["GenreId", "GenreName", "TrackCount", "TotalRevenue", "AvgTrackPrice", "UniqueCustomers"]
    
    if genre_res.get("exists"):
        cols_present = genre_res.get("columns", "").lower()
        if all(c.lower() in cols_present for c in required_cols_genre):
            score += 5
        
        # Row count should be > 0 and < 30
        rows = genre_res.get("rows", 0)
        if 20 <= rows <= 30:
            score += 5
        
        # Spot check Top Genre Revenue
        gt_genre_stats = gt.get("top_genre_stats", "Rock|0").split("|")
        gt_genre_name = gt_genre_stats[0]
        gt_genre_rev = float(gt_genre_stats[1])
        
        res_genre_name = genre_res.get("top_name", "")
        res_genre_rev = float(genre_res.get("top_revenue", 0))
        
        if gt_genre_name.lower() in res_genre_name.lower():
            score += 5
        else:
            feedback.append(f"Top genre mismatch: {res_genre_name} vs {gt_genre_name}")

        if gt_genre_rev > 0 and abs(res_genre_rev - gt_genre_rev) / gt_genre_rev < 0.05:
            score += 10
        else:
            feedback.append(f"Genre revenue mismatch: {res_genre_rev} vs {gt_genre_rev}")
    else:
        feedback.append("genre_revenue table not found.")

    # 5. monthly_sales Check (25 pts)
    monthly_res = result.get("tables", {}).get("monthly_sales", {})
    required_cols_monthly = ["YearMonth", "InvoiceCount", "TotalRevenue", "UniqueCustomers", "AvgInvoiceTotal"]
    
    if monthly_res.get("exists"):
        cols_present = monthly_res.get("columns", "").lower()
        if all(c.lower() in cols_present for c in required_cols_monthly):
            score += 5
            
        # Row count (months)
        gt_months = gt.get("month_count", 0)
        # Allow +/- 1 month
        if abs(monthly_res.get("rows", 0) - gt_months) <= 1:
            score += 5
            
        # Total Revenue Check (sum of months should equal total invoices)
        gt_total_rev = float(gt.get("total_revenue", 0))
        res_total_rev = float(monthly_res.get("total_revenue", 0))
        
        if gt_total_rev > 0 and abs(res_total_rev - gt_total_rev) / gt_total_rev < 0.05:
            score += 15
        else:
            feedback.append(f"Total revenue check failed: {res_total_rev} vs {gt_total_rev}")
    else:
        feedback.append("monthly_sales table not found.")

    # 6. Script Check (10 pts)
    if result.get("script_exists"):
        score += 10
        feedback.append("SQL script found.")
    else:
        feedback.append("SQL script not saved.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }