#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Profile Slow Endpoint Task ==="

WORKSPACE_DIR="/home/ga/workspace"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create directory structure
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/utils"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

echo "Creating Python source files..."

# Create src/__init__.py
cat > "$WORKSPACE_DIR/src/__init__.py" << 'EOF'
# Order processing application
EOF

# Create src/utils/__init__.py
cat > "$WORKSPACE_DIR/src/utils/__init__.py" << 'EOF'
# Utility modules
EOF

# Create src/api.py
cat > "$WORKSPACE_DIR/src/api.py" << 'EOF'
from flask import Flask, request, jsonify
from order_processor import process_order

app = Flask(__name__)

@app.route('/api/process-orders', methods=['POST'])
def process_orders():
    """Process orders endpoint - currently slow!"""
    data = request.get_json()
    result = process_order(data)
    return jsonify(result)

if __name__ == '__main__':
    app.run(debug=True)
EOF

# Create src/order_processor.py
cat > "$WORKSPACE_DIR/src/order_processor.py" << 'EOF'
from utils.validation import validate_order
from utils.calculations import calculate_totals
from utils.external_api import enrich_customer_data

def process_order(order_data):
    """Process an order through the pipeline"""
    # Validate input
    validated = validate_order(order_data)
    
    # Enrich with customer data
    enriched = enrich_customer_data(validated)
    
    # Calculate totals
    totals = calculate_totals(enriched)
    
    return totals
EOF

# Create src/utils/validation.py
cat > "$WORKSPACE_DIR/src/utils/validation.py" << 'EOF'
def validate_order(order_data):
    """Validate order data"""
    if 'order_id' not in order_data:
        raise ValueError("Missing order_id")
    if 'customer_id' not in order_data:
        raise ValueError("Missing customer_id")
    order_data['validated'] = True
    return order_data
EOF

# Create src/utils/calculations.py
cat > "$WORKSPACE_DIR/src/utils/calculations.py" << 'EOF'
def calculate_totals(order_data):
    """Calculate order totals with tax"""
    items = order_data.get('items', [])
    subtotal = sum(item['quantity'] * item['price'] for item in items)
    tax = subtotal * 0.08
    total = subtotal + tax
    
    order_data['subtotal'] = subtotal
    order_data['tax'] = tax
    order_data['total'] = total
    return order_data
EOF

# Create src/utils/external_api.py (THE BOTTLENECK)
cat > "$WORKSPACE_DIR/src/utils/external_api.py" << 'EOF'
import time

def enrich_customer_data(order_data):
    """Fetch additional customer information from external service"""
    customer_id = order_data.get('customer_id')
    
    # Simulating a slow external API call with no caching
    time.sleep(2.5)
    
    # Mock enriched data
    order_data['customer_tier'] = 'gold'
    order_data['customer_name'] = f'Customer {customer_id}'
    order_data['enriched'] = True
    return order_data
EOF

# Create tests/test_performance.py
cat > "$WORKSPACE_DIR/tests/test_performance.py" << 'EOF'
#!/usr/bin/env python3
"""
Performance profiling script for order processing endpoint
"""
import sys
import os

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

import cProfile
import pstats
import io
from order_processor import process_order

def profile_order_processing():
    """Profile the order processing function"""
    print("=" * 60)
    print("Starting performance profiling...")
    print("=" * 60)
    
    test_order = {
        'order_id': 'ORD-12345',
        'customer_id': 'CUST-789',
        'items': [
            {'product': 'Widget', 'quantity': 2, 'price': 29.99},
            {'product': 'Gadget', 'quantity': 1, 'price': 49.99}
        ]
    }
    
    profiler = cProfile.Profile()
    profiler.enable()
    
    # Run the slow function
    print("Processing order (this will take a few seconds)...")
    result = process_order(test_order)
    
    profiler.disable()
    
    # Save profiling results to file
    print("\nWriting profiling results to profile_results.txt...")
    with open('profile_results.txt', 'w') as f:
        f.write("=" * 60 + "\n")
        f.write("PERFORMANCE PROFILING RESULTS\n")
        f.write("=" * 60 + "\n\n")
        stats = pstats.Stats(profiler, stream=f)
        stats.sort_stats('cumulative')
        stats.print_stats()
    
    print("✓ Profiling complete!")
    print(f"✓ Order processed: {result['order_id']}")
    print(f"✓ Total: ${result['total']:.2f}")
    print("\nResults saved to: profile_results.txt")
    print("\nNext steps:")
    print("  1. Open profile_results.txt and analyze the results")
    print("  2. Identify the slowest function")
    print("  3. Document your findings in PERFORMANCE.md")
    print("=" * 60)

if __name__ == '__main__':
    profile_order_processing()
EOF

# Create empty PERFORMANCE.md
cat > "$WORKSPACE_DIR/PERFORMANCE.md" << 'EOF'
EOF

# Create requirements.txt (Flask is not strictly needed for profiling but makes it realistic)
cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
Flask==2.3.0
EOF

# Set all ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Make test script executable
sudo chmod +x "$WORKSPACE_DIR/tests/test_performance.py"

echo "Opening VSCode..."
# Open VSCode with workspace
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Profile Slow Endpoint Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open terminal (Ctrl+\`)"
echo "  2. Run: python tests/test_performance.py"
echo "  3. Analyze profile_results.txt"
echo "  4. Document findings in PERFORMANCE.md"
echo "  5. Add TODO comment to src/utils/external_api.py"
echo ""
echo "Workspace: $WORKSPACE_DIR"