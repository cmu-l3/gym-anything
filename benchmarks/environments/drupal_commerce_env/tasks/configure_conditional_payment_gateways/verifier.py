def verify_conditions(config_json, expected_operator, expected_amount):
    """Parses Drupal Commerce condition configuration."""
    conditions = config_json.get('conditions', [])
    for condition in conditions:
        if condition.get('plugin') == 'order_total_price':
            conf = condition.get('configuration', {})
            op = conf.get('operator')
            amount = conf.get('amount', {}).get('number')
            
            # Allow flexible amount formatting (500, 500.00)
            try:
                if op == expected_operator and float(amount) == float(expected_amount):
                    return True
            except (ValueError, TypeError):
                continue
    return False