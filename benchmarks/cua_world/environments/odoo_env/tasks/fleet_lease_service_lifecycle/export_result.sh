#!/bin/bash
# Export script for fleet_lease_service_lifecycle task
# Queries the vehicle, contract, odometer, and service logs

echo "=== Exporting fleet_lease_service_lifecycle result ==="

# Final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Execute Python export script via XML-RPC
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import datetime

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

# Output file path
OUTPUT_FILE = '/tmp/fleet_lease_result.json'

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    with open(OUTPUT_FILE, 'w') as f:
        json.dump({'error': str(e), 'passed': False}, f)
    sys.exit(1)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# Target Data
TARGET_PLATE = "TRK-885-XJ"
TARGET_VIN = "1FT-YRN-2025-XK99"

result = {
    "vehicle_found": False,
    "vehicle": {},
    "contract_found": False,
    "contract": {},
    "odometer_found": False,
    "odometer": {},
    "service_found": False,
    "service": {},
    "timestamp": datetime.datetime.now().isoformat()
}

# 1. Find Vehicle
vehicles = execute('fleet.vehicle', 'search_read', 
    [[['license_plate', '=', TARGET_PLATE]]], 
    {'fields': ['id', 'model_id', 'vin_sn', 'license_plate', 'driver_id']})

if vehicles:
    vehicle = vehicles[0]
    result['vehicle_found'] = True
    result['vehicle'] = {
        'id': vehicle['id'],
        'vin': vehicle['vin_sn'],
        'model': vehicle['model_id'][1] if vehicle['model_id'] else "",
        'plate': vehicle['license_plate']
    }
    
    vehicle_id = vehicle['id']

    # 2. Find Contract
    # Look for active/open contracts for this vehicle
    contracts = execute('fleet.vehicle.log.contract', 'search_read',
        [[['vehicle_id', '=', vehicle_id], ['state', 'in', ['open', 'toclose']]]],
        {'fields': ['insurer_id', 'cost_generated', 'cost_frequency', 'start_date', 'state']})
    
    # Filter for the specific one we want (approximate match on cost if multiple)
    target_contract = None
    for c in contracts:
        if abs(c['cost_generated'] - 650.0) < 1.0:
            target_contract = c
            break
    if not target_contract and contracts:
        target_contract = contracts[0] # Fallback to first active contract

    if target_contract:
        result['contract_found'] = True
        result['contract'] = {
            'vendor': target_contract['insurer_id'][1] if target_contract['insurer_id'] else "",
            'cost': target_contract['cost_generated'],
            'state': target_contract['state']
        }

    # 3. Find Odometer
    odometers = execute('fleet.vehicle.odometer', 'search_read',
        [[['vehicle_id', '=', vehicle_id]]],
        {'fields': ['value', 'date'], 'order': 'date desc, id desc', 'limit': 1})
    
    if odometers:
        result['odometer_found'] = True
        result['odometer'] = {
            'value': odometers[0]['value']
        }

    # 4. Find Service Log
    services = execute('fleet.vehicle.log.services', 'search_read',
        [[['vehicle_id', '=', vehicle_id]]],
        {'fields': ['amount', 'description', 'vendor_id', 'service_type_id']})
    
    # Look for the service with specific amount
    target_service = None
    for s in services:
        if abs(s['amount'] - 125.0) < 1.0:
            target_service = s
            break
            
    if target_service:
        result['service_found'] = True
        result['service'] = {
            'amount': target_service['amount'],
            'description': target_service['description'],
            'vendor': target_service['vendor_id'][1] if target_service['vendor_id'] else ""
        }

# Read task start time to check for anti-gaming (file modification times)
try:
    with open('/tmp/task_start_timestamp', 'r') as f:
        result['task_start_time'] = int(f.read().strip())
except:
    result['task_start_time'] = 0

with open(OUTPUT_FILE, 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

cat /tmp/fleet_lease_result.json
echo "=== Export complete ==="