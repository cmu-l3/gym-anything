#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Add Type Hints Task ==="

WORKSPACE_DIR="/home/ga/workspace/type_hints_project"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the untyped Python file
cat > "$WORKSPACE_DIR/data_processor.py" << 'EOF'
# data_processor.py - Legacy Python code needing type hints
#
# TASK: Add comprehensive type hints to all functions
# 
# TODO:
# 1. Add imports: from typing import List, Dict, Optional, Any
# 2. Add type hints to ALL parameters in ALL functions
# 3. Add return type annotations (-> Type) to ALL functions
# 4. Use Optional[T] for parameters/returns that can be None
# 5. Use List[T], Dict[K,V] for collections (not bare list/dict)
#
# Example:
#   def example(items, threshold):
#       return [x for x in items if x > threshold]
#
# Should become:
#   def example(items: List[float], threshold: float) -> List[float]:
#       return [x for x in items if x > threshold]

def calculate_average(numbers):
    """Calculate the average of a list of numbers."""
    if not numbers:
        return None
    return sum(numbers) / len(numbers)

def format_user_data(user_id, username, email, age, is_active):
    """Format user data into a dictionary."""
    return {
        'id': user_id,
        'username': username,
        'email': email,
        'age': age,
        'active': is_active
    }

def filter_by_threshold(items, threshold):
    """Filter items that exceed the threshold."""
    result = []
    for item in items:
        if item > threshold:
            result.append(item)
    return result

def merge_configs(base_config, override_config):
    """Merge two configuration dictionaries."""
    if override_config is None:
        return base_config
    merged = base_config.copy()
    merged.update(override_config)
    return merged

def process_records(records, max_results):
    """Process records and return up to max_results items."""
    if max_results is None:
        return records
    return records[:max_results]
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the file
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/data_processor.py'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Add Type Hints Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open data_processor.py (should already be open)"
echo "  2. Add typing imports at top: from typing import List, Dict, Optional, Any"
echo "  3. Add type hints to all function parameters and return types"
echo "  4. Use Optional[T] for values that can be None"
echo "  5. Use List[T], Dict[K,V] for collections"
echo "  6. Save the file (Ctrl+S)"