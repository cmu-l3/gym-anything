#!/usr/bin/env python3
"""
Generate realistic production log file for triage task
Creates 8000+ lines with mixed severity levels, transaction IDs, and error patterns
"""

import random
import sys
from datetime import datetime, timedelta

# Error types with their typical frequencies
ERROR_TYPES = {
    'ERR_PAYMENT_TIMEOUT': 23,
    'ERR_INVALID_CARD': 8,
    'ERR_GATEWAY_UNAVAILABLE': 12,
    'ERR_INSUFFICIENT_FUNDS': 5,
    'ERR_CARD_DECLINED': 7,
    'ERR_NETWORK_ERROR': 15,
    'ERR_RATE_LIMIT': 4,
    'ERR_INVALID_CVV': 6,
}

# Components that generate logs
COMPONENTS = [
    'PaymentService', 'PaymentGateway', 'OrderService', 'RetryHandler',
    'DatabasePool', 'CacheService', 'AuthService', 'NotificationService'
]

# Payment gateways
GATEWAYS = ['stripe', 'paypal', 'square', 'braintree']

# Log levels and their frequencies (INFO is most common, CRITICAL is rare)
LOG_LEVELS = {
    'DEBUG': 0.35,
    'INFO': 0.45,
    'WARN': 0.12,
    'ERROR': 0.06,
    'CRITICAL': 0.02
}


def generate_transaction_id():
    """Generate transaction ID in format txn_XXXXXXXXXXXX"""
    return f"txn_{random.randint(100000000000, 999999999999)}"


def generate_timestamp(base_time, offset_seconds):
    """Generate timestamp"""
    ts = base_time + timedelta(seconds=offset_seconds)
    return ts.strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]


def generate_info_log(component, txn_id, gateway):
    """Generate INFO level log message"""
    messages = [
        f"Processing transaction {txn_id}",
        f"Transaction {txn_id} completed successfully (amount=${random.uniform(10, 500):.2f})",
        f"Starting payment processing batch",
        f"Payment processed for {txn_id} via gateway={gateway}",
        f"Order #{random.randint(10000, 99999)} marked as payment_complete",
        f"Cache hit for customer_id={random.randint(1000, 9999)}",
        f"Database transaction committed successfully",
        f"User authentication successful (user_id={random.randint(1000, 9999)})",
    ]
    return random.choice(messages)


def generate_debug_log(component, txn_id, gateway):
    """Generate DEBUG level log message"""
    messages = [
        f"Connection acquired from pool (pool_size={random.randint(5, 20)})",
        f"Cache lookup for key=payment_{txn_id}",
        f"Validating card data for {txn_id}",
        f"Invoking gateway API: gateway={gateway}, endpoint=/v1/charge",
        f"Parsing response payload (size={random.randint(200, 2000)} bytes)",
        f"Token validation successful",
        f"Query execution time: {random.uniform(0.01, 0.5):.3f}s",
    ]
    return random.choice(messages)


def generate_warn_log(component, txn_id, gateway):
    """Generate WARN level log message"""
    messages = [
        f"Slow response from gateway={gateway} ({random.uniform(1.5, 3.0):.1f}s)",
        f"Retry attempt {random.randint(1, 2)} for transaction {txn_id}",
        f"Connection pool near capacity ({random.randint(18, 20)}/20)",
        f"Cache miss rate elevated: {random.uniform(15, 25):.1f}%",
        f"High memory usage detected: {random.randint(80, 95)}%",
    ]
    return random.choice(messages)


def generate_error_log(component, txn_id, gateway, error_type):
    """Generate ERROR level log message"""
    details = {
        'ERR_PAYMENT_TIMEOUT': f"Gateway timeout for {txn_id} (gateway={gateway}, amount={random.uniform(50, 500):.2f}, retry={random.randint(1, 3)})",
        'ERR_INVALID_CARD': f"Card validation failed for {txn_id} (gateway={gateway}, reason={random.choice(['expired', 'invalid_number', 'invalid_format'])})",
        'ERR_GATEWAY_UNAVAILABLE': f"Gateway {gateway} returned 503 Service Unavailable for {txn_id}",
        'ERR_INSUFFICIENT_FUNDS': f"Payment declined for {txn_id}: insufficient funds (gateway={gateway})",
        'ERR_CARD_DECLINED': f"Card declined by issuer for {txn_id} (gateway={gateway}, decline_code={random.choice(['fraud_suspected', 'lost_card', 'generic_decline'])})",
        'ERR_NETWORK_ERROR': f"Network error while processing {txn_id}: connection reset by peer",
        'ERR_RATE_LIMIT': f"Rate limit exceeded for gateway={gateway} (txn={txn_id})",
        'ERR_INVALID_CVV': f"CVV validation failed for {txn_id} (gateway={gateway})",
    }
    return f"{error_type}: {details.get(error_type, f'Error processing {txn_id}')}"


def generate_critical_log(component, txn_id, error_type):
    """Generate CRITICAL level log message"""
    messages = [
        f"PAYMENT_PROCESSING_FAILED: Unable to process {txn_id} after 3 retries",
        f"DATABASE_CONNECTION_FAILED: Could not establish connection after 5 attempts",
        f"SYSTEM_OVERLOAD: Request queue full, dropping transaction {txn_id}",
    ]
    return random.choice(messages)


def main():
    if len(sys.argv) != 2:
        print("Usage: generate_log.py <output_file>")
        sys.exit(1)
    
    output_file = sys.argv[1]
    
    # Start time: 2024-01-15 03:15:00
    base_time = datetime(2024, 1, 15, 3, 15, 0)
    
    # Track transaction IDs for errors (reuse some for retries)
    error_transactions = {}
    for error_type, count in ERROR_TYPES.items():
        error_transactions[error_type] = [generate_transaction_id() for _ in range(count)]
    
    all_txn_ids = [generate_transaction_id() for _ in range(500)]  # Pool of normal transactions
    
    lines = []
    current_offset = 0
    
    # Generate ~8247 lines
    for i in range(8247):
        # Determine log level based on frequency distribution
        rand = random.random()
        cumulative = 0
        level = 'INFO'
        for lv, freq in LOG_LEVELS.items():
            cumulative += freq
            if rand <= cumulative:
                level = lv
                break
        
        component = random.choice(COMPONENTS)
        gateway = random.choice(GATEWAYS)
        txn_id = random.choice(all_txn_ids)
        
        timestamp = generate_timestamp(base_time, current_offset)
        current_offset += random.uniform(0.1, 2.0)  # 0.1-2 seconds between logs
        
        # Generate message based on level
        if level == 'DEBUG':
            message = generate_debug_log(component, txn_id, gateway)
        elif level == 'INFO':
            message = generate_info_log(component, txn_id, gateway)
        elif level == 'WARN':
            message = generate_warn_log(component, txn_id, gateway)
        elif level == 'ERROR':
            # Pick an error type and use its pre-generated transaction ID
            error_type = random.choice(list(ERROR_TYPES.keys()))
            if error_transactions[error_type]:
                txn_id = random.choice(error_transactions[error_type])
            message = generate_error_log(component, txn_id, gateway, error_type)
        elif level == 'CRITICAL':
            # Use error transactions for critical logs
            error_type = random.choice(['ERR_PAYMENT_TIMEOUT', 'ERR_GATEWAY_UNAVAILABLE'])
            if error_transactions[error_type]:
                txn_id = random.choice(error_transactions[error_type])
            message = generate_critical_log(component, txn_id, error_type)
        
        line = f"{timestamp} [{level}] {component} - {message}"
        lines.append(line)
    
    # Write to file
    with open(output_file, 'w') as f:
        f.write('\n'.join(lines))
        f.write('\n')
    
    print(f"✅ Generated {len(lines)} log lines")
    print(f"✅ Written to {output_file}")
    
    # Print statistics for verification
    total_errors = sum(ERROR_TYPES.values())
    print(f"📊 Expected errors: {total_errors}")
    for error_type, count in ERROR_TYPES.items():
        print(f"   - {error_type}: {count}")


if __name__ == '__main__':
    main()