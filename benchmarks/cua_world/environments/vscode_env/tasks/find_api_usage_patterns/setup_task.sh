#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Find API Usage Patterns Task ==="

WORKSPACE_DIR="/home/ga/workspace/validator_project"
sudo -u ga mkdir -p "$WORKSPACE_DIR"/{framework,services,models,tests}

# Create framework validator with minimal documentation
cat > "$WORKSPACE_DIR/framework/__init__.py" << 'EOF'
"""Internal validation framework"""
EOF

cat > "$WORKSPACE_DIR/framework/validators.py" << 'EOF'
"""Internal validation framework"""

class ValidationResult:
    """Result object returned by validation"""
    def __init__(self, is_valid, data=None, errors=None):
        self.is_valid = is_valid
        self.data = data
        self.errors = errors or []

class DataValidator:
    """Validator for structured data against schemas"""
    
    @staticmethod
    def validate_with_schema(data, schema):
        """Validates data against schema. Returns ValidationResult."""
        # Implementation validates data structure against schema definition
        # Returns ValidationResult with is_valid flag and optional errors
        if not isinstance(schema, dict) or 'fields' not in schema:
            return ValidationResult(False, None, ["Invalid schema format"])
        
        errors = []
        validated_data = {}
        
        for field_name, field_spec in schema.get('fields', {}).items():
            if field_spec.get('required') and field_name not in data:
                errors.append(f"Missing required field: {field_name}")
            elif field_name in data:
                validated_data[field_name] = data[field_name]
        
        is_valid = len(errors) == 0
        return ValidationResult(is_valid, validated_data if is_valid else None, errors)
EOF

# Create schema definitions
cat > "$WORKSPACE_DIR/models/__init__.py" << 'EOF'
"""Data models and schemas"""
EOF

cat > "$WORKSPACE_DIR/models/schemas.py" << 'EOF'
"""Common validation schemas"""

USER_SCHEMA = {
    "type": "object",
    "fields": {
        "email": {"type": "string", "required": True},
        "age": {"type": "integer", "min": 18},
        "username": {"type": "string", "required": True}
    }
}

PAYMENT_SCHEMA = {
    "type": "object",
    "fields": {
        "amount": {"type": "decimal", "required": True},
        "currency": {"type": "string", "required": True},
        "payment_method": {"type": "string"}
    }
}

ORDER_SCHEMA = {
    "type": "object",
    "fields": {
        "items": {"type": "array", "required": True},
        "total": {"type": "decimal", "required": True},
        "customer_id": {"type": "integer", "required": True}
    }
}
EOF

# Create service files with different usage patterns
cat > "$WORKSPACE_DIR/services/__init__.py" << 'EOF'
"""Business logic services"""
EOF

cat > "$WORKSPACE_DIR/services/user_service.py" << 'EOF'
"""User management service"""
from framework.validators import DataValidator
from models.schemas import USER_SCHEMA

def create_user(user_data):
    """Create a new user with validation"""
    result = DataValidator.validate_with_schema(user_data, USER_SCHEMA)
    if not result.is_valid:
        raise ValueError(f"Invalid user data: {result.errors}")
    return save_user(result.data)

def save_user(data):
    """Persist user to database"""
    return {"id": 123, **data}
EOF

cat > "$WORKSPACE_DIR/services/payment_service.py" << 'EOF'
"""Payment processing service"""
from framework.validators import DataValidator
from models.schemas import PAYMENT_SCHEMA
import logging

logger = logging.getLogger(__name__)

def process_payment(payment_data):
    """Process a payment with validation"""
    validation = DataValidator.validate_with_schema(payment_data, PAYMENT_SCHEMA)
    if validation.is_valid:
        return charge_card(validation.data)
    else:
        logger.error(f"Payment validation failed: {validation.errors}")
        return None

def charge_card(payment_info):
    """Charge the payment card"""
    return {"status": "success", "transaction_id": "txn_12345"}
EOF

cat > "$WORKSPACE_DIR/services/order_service.py" << 'EOF'
"""Order management service"""
from framework.validators import DataValidator
from models.schemas import ORDER_SCHEMA

def validate_order(order):
    """Validate order data before processing"""
    result = DataValidator.validate_with_schema(order, ORDER_SCHEMA)
    return result.is_valid, result.errors

def create_order(order_data):
    """Create new order with validation"""
    is_valid, errors = validate_order(order_data)
    if not is_valid:
        return {"error": errors}
    return {"order_id": 456, "status": "created"}
EOF

cat > "$WORKSPACE_DIR/services/product_service.py" << 'EOF'
"""Product catalog service"""
from framework.validators import DataValidator

PRODUCT_SCHEMA = {
    "type": "object",
    "fields": {
        "name": {"type": "string", "required": True},
        "price": {"type": "decimal", "min": 0, "required": True},
        "category": {"type": "string"}
    }
}

def update_product(product_id, updates):
    """Update product with validation"""
    validation_result = DataValidator.validate_with_schema(updates, PRODUCT_SCHEMA)
    if not validation_result.is_valid:
        return {"error": validation_result.errors}
    
    return apply_updates(product_id, validation_result.data)

def apply_updates(product_id, data):
    """Apply updates to product"""
    return {"product_id": product_id, "updated": True}
EOF

cat > "$WORKSPACE_DIR/services/auth_service.py" << 'EOF'
"""Authentication service"""
from framework.validators import DataValidator

CREDENTIAL_SCHEMA = {
    "type": "object",
    "fields": {
        "username": {"type": "string", "required": True},
        "password": {"type": "string", "required": True, "min_length": 8}
    }
}

def verify_credentials(creds):
    """Verify user credentials with validation"""
    try:
        result = DataValidator.validate_with_schema(creds, CREDENTIAL_SCHEMA)
        if result.is_valid:
            return authenticate(result.data)
        return None
    except Exception as e:
        log_error(e)
        return None

def authenticate(cred_data):
    """Authenticate user"""
    return {"authenticated": True, "user_id": 789}

def log_error(error):
    """Log authentication error"""
    pass
EOF

cat > "$WORKSPACE_DIR/services/notification_service.py" << 'EOF'
"""Notification service"""
from framework.validators import DataValidator

def send_notification(notification_data):
    """Send notification after validation"""
    schema = {
        "type": "object",
        "fields": {
            "recipient": {"type": "string", "required": True},
            "message": {"type": "string", "required": True},
            "priority": {"type": "string"}
        }
    }
    
    result = DataValidator.validate_with_schema(notification_data, schema)
    if result.is_valid:
        deliver_notification(result.data)
        return True
    return False

def deliver_notification(data):
    """Deliver the notification"""
    pass
EOF

# Create test examples
cat > "$WORKSPACE_DIR/tests/__init__.py" << 'EOF'
"""Test suite"""
EOF

cat > "$WORKSPACE_DIR/tests/test_validation.py" << 'EOF'
"""Validation tests"""
from framework.validators import DataValidator

def test_valid_data():
    """Test validation with valid data"""
    schema = {"type": "object", "fields": {"id": {"type": "integer", "required": True}}}
    result = DataValidator.validate_with_schema({"id": 123}, schema)
    assert result.is_valid == True
    
def test_invalid_data():
    """Test validation with invalid data"""
    schema = {"type": "object", "fields": {"id": {"type": "integer", "required": True}}}
    result = DataValidator.validate_with_schema({}, schema)
    assert result.is_valid == False
    assert len(result.errors) > 0

def test_missing_required_field():
    """Test validation with missing required field"""
    schema = {"type": "object", "fields": {"email": {"type": "string", "required": True}}}
    result = DataValidator.validate_with_schema({"name": "John"}, schema)
    assert not result.is_valid
EOF

# Create README
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Validator Project

Internal project using custom validation framework.

## Structure
- `framework/` - Core validation code
- `services/` - Business logic services  
- `models/` - Data models and schemas
- `tests/` - Test suite

## Validation Framework

The `DataValidator` class provides schema-based validation. See `framework/validators.py` for implementation.

### Usage