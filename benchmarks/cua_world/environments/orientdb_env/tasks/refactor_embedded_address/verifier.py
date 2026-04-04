#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_embedded_address(traj, env_info, task_info):
    """
    Verify the refactoring of Hotels address data into an embedded Location object.
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Location class creation (10 pts)
    if result.get("location_class_exists"):
        score += 10
        feedback_parts.append("Location class created")
        
        # Check properties of Location (Street, City, Country)
        loc_props = result.get("location_properties", [])
        required_loc_props = {"Street", "City", "Country"}
        if required_loc_props.issubset(set(loc_props)):
            # implicit points included in data check, but good to note
            pass
        else:
            feedback_parts.append(f"Location class missing properties: {required_loc_props - set(loc_props)}")
            
        # Check it is NOT a Vertex (should ideally be a Document)
        supers = result.get("location_superclasses", [])
        if "V" in supers or "E" in supers:
            feedback_parts.append("Warning: Location extends V or E (should be plain Document)")
            # We don't penalize heavily if it works, but it's not ideal.
    else:
        feedback_parts.append("Location class NOT found")

    # 2. Verify Hotels.Address property (15 pts)
    hotels_props = result.get("hotels_properties", [])
    if "Address" in hotels_props:
        addr_type = result.get("hotels_address_type")
        linked_class = result.get("hotels_address_linked_class")
        
        if addr_type == "EMBEDDED" and linked_class == "Location":
            score += 15
            feedback_parts.append("Hotels.Address property correctly configured (EMBEDDED Location)")
        elif addr_type == "EMBEDDED":
            score += 10
            feedback_parts.append(f"Hotels.Address is EMBEDDED but linked class is {linked_class} (expected Location)")
        else:
            score += 5
            feedback_parts.append(f"Hotels.Address exists but type is {addr_type} (expected EMBEDDED)")
    else:
        feedback_parts.append("Hotels.Address property NOT found")

    # 3. Verify Data Migration (40 pts)
    data = result.get("data_sample", {})
    address_data = data.get("Address")
    
    data_correct = False
    if isinstance(address_data, dict):
        # Check content
        city = address_data.get("City")
        street = address_data.get("Street")
        country = address_data.get("Country")
        
        # Expected values for Hotel Artemide
        if city == "Rome" and country == "Italy" and "Via Nazionale" in str(street):
            score += 40
            data_correct = True
            feedback_parts.append("Data migration verified successfully")
        else:
            score += 10
            feedback_parts.append(f"Address object exists but data does not match expectation: {address_data}")
    else:
        feedback_parts.append("Address data is empty or not an object")

    # 4. Verify Cleanup (Drop old properties) (25 pts)
    # Only award if migration was successful (don't reward deleting data if not moved!)
    if data_correct:
        old_props_present = []
        for p in ["Street", "City", "Country"]:
            if p in hotels_props:
                old_props_present.append(p)
        
        if not old_props_present:
            score += 25
            feedback_parts.append("Old properties correctly removed")
        else:
            feedback_parts.append(f"Old properties still present: {old_props_present}")
    else:
        feedback_parts.append("Cleanup points skipped (migration not successful)")

    # 5. Verify Preservation of other fields (10 pts)
    # Name, Latitude, Longitude should still be there
    preserved = []
    for p in ["Name", "Latitude", "Longitude"]:
        if p in hotels_props:
            preserved.append(p)
            
    if len(preserved) == 3:
        score += 10
        feedback_parts.append("Other properties preserved")
    else:
        feedback_parts.append(f"Some original properties missing: found {preserved}")

    return {
        "passed": score >= 75 and data_correct,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }