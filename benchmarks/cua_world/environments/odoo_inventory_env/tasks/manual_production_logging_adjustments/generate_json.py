import json

metadata = {
    "result_file": "/tmp/manual_production_result.json",
    "expected_lots": {
      "PP-1001": {"expected_qty": 3000, "product_name": "Raw Polymer Pellets"},
      "PP-1002": {"expected_qty": 950, "product_name": "Raw Polymer Pellets"},
      "DYE-BLU-77": {"expected_qty": 85, "product_name": "Blue Industrial Dye"},
      "DYE-RED-42": {"expected_qty": 35, "product_name": "Red Industrial Dye"}
    },
    "new_lot": {
      "name": "PB-BLU-4099",
      "expected_qty": 45,
      "product_name": "Polymer Block - Premium Blue"
    },
    "anti_gaming_lot": {
      "name": "DYE-YEL-19",
      "expected_qty": 30,
      "product_name": "Yellow Industrial Dye"
    },
    "pass_threshold": 80
}

pi_items = []

pi_items.append({
    "key": "result_file",
    "metadata_value": str(metadata["result_file"]),
    "verified_value": str(metadata["result_file"]),
    "source": "export_result.sh RESULT_FILE variable",
    "status": "verified"
})

pi_items.append({
    "key": "expected_lots",
    "metadata_value": str(metadata["expected_lots"]),
    "verified_value": str(metadata["expected_lots"]),
    "source": "Calculated by subtracting task description amounts (2000, 250, 15, 5) from initial stock defined in setup_task.sh (5000, 1200, 100, 40).",
    "status": "verified"
})

pi_items.append({
    "key": "new_lot",
    "metadata_value": str(metadata["new_lot"]),
    "verified_value": str(metadata["new_lot"]),
    "source": "Matched with task description instructions for new lot PB-BLU-4099 and quantity 45.",
    "status": "verified"
})

pi_items.append({
    "key": "anti_gaming_lot",
    "metadata_value": str(metadata["anti_gaming_lot"]),
    "verified_value": str(metadata["anti_gaming_lot"]),
    "source": "Matched with task description and setup_task.sh initial stock for DYE-YEL-19 (30 liters).",
    "status": "verified"
})

pi_items.append({
    "key": "pass_threshold",
    "metadata_value": str(metadata["pass_threshold"]),
    "verified_value": str(metadata["pass_threshold"]),
    "source": "verifier.py pass threshold logic requires at least 80 points.",
    "status": "verified"
})

output = {
    "task_id": "manual_production_logging_adjustments@1",
    "dataset": None,
    "case_id": None,
    "data_is_synthetic": True,
    "pi_items": pi_items,
    "privileged_info_summary": "The task relies on synthetically generated Odoo inventory data initialized via setup_task.sh. I have verified that the expected final lot quantities (Raw Polymer Pellets PP-1001: 3000, PP-1002: 950; Blue Industrial Dye DYE-BLU-77: 85; Red Industrial Dye DYE-RED-42: 35) are mathematically accurate by subtracting the consumed/spilled amounts in the task description from the initial stock amounts in the setup script. Additionally, the new lot (PB-BLU-4099: 45) and anti-gaming lot (DYE-YEL-19: 30) expectations match the prompt constraints and verification logic.",
    "pi_confidence": "high"
}

with open('/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/odoo_inventory_env/tasks/manual_production_logging_adjustments/validated_pi.json', 'w') as f:
    json.dump(output, f, indent=4)
