#!/usr/bin/env python3
"""
Verifier for create_booking_system task.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_booking_system(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Verify Sequences (15 pts)
    # ----------------------------------------------------------------
    seqs = {s['name']: s['value'] for s in result.get('sequences', [])}
    
    if 'booking_seq' in seqs and 'invoice_seq' in seqs:
        score += 10
        feedback.append("Sequences created.")
        
        # Check values - should have advanced by at least 5 if used correctly
        # booking_seq starts 1000 -> should be >= 1005
        # invoice_seq starts 5000 -> should be >= 5005
        b_val = seqs['booking_seq']
        i_val = seqs['invoice_seq']
        
        if b_val >= 1005 and i_val >= 5005:
            score += 5
            feedback.append("Sequences used correctly.")
        else:
            feedback.append(f"Sequences exist but values look unchanged (booking={b_val}, invoice={i_val}).")
    else:
        feedback.append(f"Missing sequences. Found: {list(seqs.keys())}")

    # 2. Verify Schema (20 pts)
    # ----------------------------------------------------------------
    schema = result.get('schema', {})
    classes = {c['name']: c for c in schema.get('classes', [])}
    
    # Bookings Class
    if 'Bookings' in classes:
        score += 5
        bookings_cls = classes['Bookings']
        props = {p['name']: p['type'] for p in bookings_cls.get('properties', [])}
        
        required_props = {
            'BookingRef': ['INTEGER', 'LONG'],
            'InvoiceNum': ['INTEGER', 'LONG'],
            'CheckIn': ['DATE', 'DATETIME'],
            'CheckOut': ['DATE', 'DATETIME'],
            'Status': ['STRING'],
            'TotalPrice': ['DOUBLE', 'FLOAT', 'DECIMAL']
        }
        
        props_ok = True
        for name, allowed_types in required_props.items():
            if name not in props:
                props_ok = False
                break
            if props[name] not in allowed_types:
                props_ok = False
                break
        
        if props_ok:
            score += 5
            feedback.append("Bookings class properties correct.")
        else:
            feedback.append("Bookings class missing properties or wrong types.")
    else:
        feedback.append("Bookings class not found.")

    # Edge Classes
    if 'HasBooking' in classes and 'BookedAt' in classes:
        score += 10
        feedback.append("Edge classes created.")
    else:
        feedback.append("Edge classes missing.")

    # 3. Verify Data Records (30 pts)
    # ----------------------------------------------------------------
    bookings = result.get('bookings', [])
    if len(bookings) == 5:
        score += 10
        feedback.append("5 Booking records found.")
        
        # Check specific data integrity
        # Expected: BookingRef 1000-1004, InvoiceNum 5000-5004
        refs = sorted([b.get('BookingRef') for b in bookings if b.get('BookingRef') is not None])
        invoices = sorted([b.get('InvoiceNum') for b in bookings if b.get('InvoiceNum') is not None])
        
        # Allow for slight variations if they burned a sequence number, but generally look for range
        if len(refs) == 5 and refs[0] >= 1000 and refs[-1] < 1100:
             score += 10
             feedback.append("BookingRefs generated correctly.")
        else:
             feedback.append(f"BookingRefs invalid: {refs}")
             
        if len(invoices) == 5 and invoices[0] >= 5000 and invoices[-1] < 5100:
             score += 10
             feedback.append("InvoiceNums generated correctly.")
        else:
             feedback.append(f"InvoiceNums invalid: {invoices}")
    else:
        feedback.append(f"Expected 5 bookings, found {len(bookings)}.")

    # 4. Verify Graph Connections (25 pts)
    # ----------------------------------------------------------------
    edges = result.get('edges', {})
    has_booking = edges.get('has_booking', [])
    booked_at = edges.get('booked_at', [])
    
    # Check Profile links
    expected_guests = [
        "john.smith@example.com", "maria.garcia@example.com", 
        "david.jones@example.com", "sophie.martin@example.com", 
        "luca.rossi@example.com"
    ]
    linked_guests = [e.get('GuestEmail') for e in has_booking]
    
    # Check Hotel links
    expected_hotels = [
        "Hotel Artemide", "Hotel Adlon Kempinski", "The Savoy", 
        "Hotel de Crillon", "The Plaza Hotel"
    ]
    linked_hotels = [e.get('HotelName') for e in booked_at]
    
    # Matching logic
    guests_match = sum(1 for g in expected_guests if g in linked_guests)
    hotels_match = sum(1 for h in expected_hotels if h in linked_hotels)
    
    if guests_match >= 5:
        score += 12
    elif guests_match > 0:
        score += int(12 * (guests_match / 5))
        
    if hotels_match >= 5:
        score += 13
    elif hotels_match > 0:
        score += int(13 * (hotels_match / 5))
        
    feedback.append(f"Graph links: {guests_match}/5 guests, {hotels_match}/5 hotels linked.")

    # 5. Verify Report File (10 pts)
    # ----------------------------------------------------------------
    file_info = result.get('file_info', {})
    if file_info.get('exists') and file_info.get('created_during_task'):
        if file_info.get('size', 0) > 100: # reasonable JSON size
            score += 10
            feedback.append("Report file created successfully.")
        else:
            score += 5
            feedback.append("Report file exists but is very small.")
    else:
        feedback.append("Report file missing or not created during task.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }