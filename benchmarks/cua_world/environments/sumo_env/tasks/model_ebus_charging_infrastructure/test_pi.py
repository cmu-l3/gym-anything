import json

metadata = {
    "expected_charger_id": "fast_charger_1",
    "expected_charger_power": "200000",
    "expected_battery_capacity": "50000",
    "expected_battery_charge": "10000",
    "expected_charging_duration": "120"
}

print(json.dumps(metadata, indent=2))
