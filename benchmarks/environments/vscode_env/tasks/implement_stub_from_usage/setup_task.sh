#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Implement Stub From Usage Task ==="

WORKSPACE_DIR="/home/ga/workspace/config_manager"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"
sudo -u ga mkdir -p "$WORKSPACE_DIR/sample_configs"

# Create utils.py with stub function
cat > "$WORKSPACE_DIR/utils.py" << 'EOF'
"""Configuration utilities"""

def validate_and_normalize_config(config_dict, strict_mode=False):
    """
    TODO: Implement this function
    Should validate and normalize configuration dictionaries
    
    Hints from usage:
    - Should convert camelCase to snake_case
    - Should add default values for missing keys
    - Should handle strict vs lenient validation modes
    """
    raise NotImplementedError("Function not implemented yet")


def other_utility_function():
    """Example of other functions in this module"""
    return "This function is already implemented"
EOF

# Create loader.py - shows basic usage and strict mode
cat > "$WORKSPACE_DIR/loader.py" << 'EOF'
from utils import validate_and_normalize_config
import json

def load_user_config(filepath):
    """Load and validate user configuration"""
    with open(filepath, 'r') as f:
        raw_config = json.load(f)
    
    # Called with default strict_mode
    validated = validate_and_normalize_config(raw_config)
    
    # Expects a dict back with normalized keys
    return validated

def load_system_config(filepath):
    """Load system configuration with strict validation"""
    with open(filepath, 'r') as f:
        raw_config = json.load(f)
    
    # Called with strict_mode=True - should raise on invalid data
    validated = validate_and_normalize_config(raw_config, strict_mode=True)
    return validated
EOF

# Create validator.py - shows handling of None values and batch processing
cat > "$WORKSPACE_DIR/validator.py" << 'EOF'
from utils import validate_and_normalize_config

def check_config_compatibility(config):
    """Check if config is compatible with current system"""
    # Called with dict, expects it won't raise on None values in lenient mode
    normalized = validate_and_normalize_config(config, strict_mode=False)
    
    # Expects 'version' key to exist after normalization
    return normalized.get('version', '1.0')

def validate_batch_configs(config_list):
    """Validate multiple configs"""
    results = []
    for cfg in config_list:
        try:
            # Should handle empty dicts gracefully
            valid = validate_and_normalize_config(cfg or {})
            results.append({'status': 'ok', 'config': valid})
        except ValueError as e:
            results.append({'status': 'error', 'message': str(e)})
    return results
EOF

# Create preprocessor.py - shows expectation of specific keys after normalization
cat > "$WORKSPACE_DIR/preprocessor.py" << 'EOF'
from utils import validate_and_normalize_config

def preprocess_api_config(api_response):
    """Preprocess configuration from API"""
    # API might return None for optional config
    if api_response.get('config') is None:
        return {}
    
    # Expects function to handle missing keys by adding defaults
    processed = validate_and_normalize_config(
        api_response['config'],
        strict_mode=False
    )
    
    # After normalization, expects these keys to exist
    assert 'timeout' in processed
    assert 'retry_limit' in processed
    assert 'version' in processed
    
    return processed
EOF

# Create test file with explicit expectations
cat > "$WORKSPACE_DIR/tests/test_config.py" << 'EOF'
import pytest
import sys
sys.path.insert(0, '/home/ga/workspace/config_manager')
from utils import validate_and_normalize_config

def test_valid_config():
    """Test with valid configuration"""
    config = {'timeout': 30, 'retryLimit': 3}
    result = validate_and_normalize_config(config)
    
    # Expects snake_case normalization
    assert 'retry_limit' in result
    assert result['retry_limit'] == 3

def test_empty_config():
    """Empty config should get defaults"""
    result = validate_and_normalize_config({})
    assert 'version' in result
    assert 'timeout' in result
    assert result['timeout'] == 30

def test_strict_mode_invalid():
    """Strict mode should raise on invalid types"""
    with pytest.raises(ValueError):
        validate_and_normalize_config({'timeout': 'not_a_number'}, strict_mode=True)

def test_lenient_mode_invalid():
    """Lenient mode should handle invalid types gracefully"""
    result = validate_and_normalize_config({'timeout': 'not_a_number'}, strict_mode=False)
    # Should use default value
    assert result['timeout'] == 30
EOF

# Create sample configuration files
cat > "$WORKSPACE_DIR/sample_configs/valid_config.json" << 'EOF'
{
  "timeout": 60,
  "retryLimit": 5,
  "version": "2.0"
}
EOF

cat > "$WORKSPACE_DIR/sample_configs/invalid_config.json" << 'EOF'
{
  "timeout": "invalid",
  "retryLimit": "also_invalid"
}
EOF

cat > "$WORKSPACE_DIR/sample_configs/edge_case_config.json" << 'EOF'
{
  "timeout": null,
  "extra_unknown_key": "should_be_ignored"
}
EOF

# Set proper ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the workspace
echo "Opening VSCode with config_manager workspace..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open the key files in tabs
echo "Opening key files..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/utils.py'" &
sleep 1
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/loader.py'" &
sleep 1
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/validator.py'" &
sleep 1

# Give VSCode time to load files
sleep 2

echo "=== Implement Stub From Usage Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Examine the stub function in utils.py"
echo "  2. Read loader.py, validator.py, preprocessor.py to see usage patterns"
echo "  3. Check tests/test_config.py for expected behavior"
echo "  4. Infer requirements: signature, return type, strict vs lenient modes"
echo "  5. Implement validate_and_normalize_config() in utils.py"
echo "  6. Requirements:"
echo "     - Convert camelCase keys to snake_case"
echo "     - Add defaults: version='1.0', timeout=30, retry_limit=3"
echo "     - Strict mode: raise ValueError on invalid types"
echo "     - Lenient mode: use defaults for invalid values"
echo "  7. Save utils.py (Ctrl+S)"