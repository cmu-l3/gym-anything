#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Extract Minimal Reproduction Task ==="

WORKSPACE_DIR="/home/ga/workspace/portfolio_risk"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Install required libraries
echo "Installing numpy and numpy-financial..."
pip3 install -q numpy==1.24.0 numpy-financial==1.0.0 || pip3 install -q numpy numpy-financial

# Create complex production code
cat > "$WORKSPACE_DIR/production_code.py" << 'EOFPROD'
"""
Complex production portfolio risk calculator
This file contains the bug embedded in business logic
"""
import numpy as np
import numpy_financial as npf

class PortfolioAnalyzer:
    """Analyzes portfolio risk and returns for financial products."""
    
    def __init__(self, config):
        self.config = config
        self.risk_factor = config.get('risk_factor', 1.0)
        
    def calculate_portfolio_irr(self, portfolio_id, start_date, end_date):
        """
        Calculate Internal Rate of Return for a portfolio.
        
        This is embedded in complex business logic with database connections,
        risk models, and proprietary calculations.
        """
        # In reality, this would fetch from database
        holdings = self._fetch_holdings(portfolio_id, start_date, end_date)
        
        # Aggregate cash flows across holdings
        cash_flows = self._aggregate_cash_flows(holdings)
        
        # Apply company-specific risk adjustments
        adjusted_flows = self._apply_risk_adjustments(cash_flows)
        
        # Normalize currencies to USD
        normalized_flows = self._normalize_currency(adjusted_flows)
        
        # Calculate IRR - THIS IS WHERE THE BUG OCCURS
        try:
            irr_result = npf.irr(normalized_flows)
            validated_result = self._validate_result(irr_result)
            return validated_result
        except Exception as e:
            print(f"IRR calculation failed: {e}")
            return None
            
    def _fetch_holdings(self, portfolio_id, start_date, end_date):
        """Simulate fetching holdings from database."""
        # In production, this queries a database
        return [
            {'id': 1, 'amount': 1000, 'date': start_date},
            {'id': 2, 'amount': 0.000001, 'date': '2024-03-01'},
            {'id': 3, 'amount': 0.000001, 'date': '2024-06-01'},
            {'id': 4, 'amount': 0.000001, 'date': '2024-09-01'},
            {'id': 5, 'amount': 1000.5, 'date': end_date},
        ]
    
    def _aggregate_cash_flows(self, holdings):
        """Aggregate cash flows from multiple holdings."""
        flows = []
        for holding in holdings:
            # Complex business logic for aggregation
            amount = holding['amount']
            # Apply transaction fees, taxes, etc.
            flows.append(amount)
        return flows
    
    def _apply_risk_adjustments(self, cash_flows):
        """Apply proprietary risk model adjustments."""
        # Complex risk calculations using internal models
        adjusted = []
        for cf in cash_flows:
            # Apply risk factor based on proprietary model
            adjusted_cf = cf * self.risk_factor
            adjusted.append(adjusted_cf)
        return adjusted
    
    def _normalize_currency(self, cash_flows):
        """
        Convert all cash flows to USD.
        
        THE BUG: This returns an array with very small values near zero
        which causes npf.irr() to behave unexpectedly.
        """
        # Complex currency conversion logic
        # After all conversions, we get this problematic pattern:
        result = np.array([-1000, 0.000001, 0.000001, 0.000001, 1000.5])
        return result
    
    def _validate_result(self, result):
        """Validate IRR result meets business rules."""
        if result is None or np.isnan(result):
            raise ValueError("Invalid IRR calculation")
        if abs(result) > 10:
            print(f"Warning: Suspicious IRR value: {result}")
        return result


def main():
    """Example usage that demonstrates the bug."""
    config = {'risk_factor': 1.0}
    analyzer = PortfolioAnalyzer(config)
    
    result = analyzer.calculate_portfolio_irr(
        portfolio_id=12345,
        start_date="2024-01-01",
        end_date="2024-12-31"
    )
    
    print(f"Portfolio IRR: {result}")
    

if __name__ == "__main__":
    main()
EOFPROD

# Create test file
cat > "$WORKSPACE_DIR/test_irr_bug.py" << 'EOFTEST'
"""
Test that demonstrates the bug but is tangled with business logic.
"""
import pytest
from production_code import PortfolioAnalyzer

def test_small_value_irr():
    """
    This test fails but it's embedded in the complex business logic.
    Hard to share with library maintainers.
    """
    config = {'risk_factor': 1.0}
    analyzer = PortfolioAnalyzer(config)
    
    result = analyzer.calculate_portfolio_irr(
        portfolio_id=12345,
        start_date="2024-01-01",
        end_date="2024-12-31"
    )
    
    # Expected reasonable IRR, but gets unexpected value
    assert result is not None, "IRR should not be None"
    assert not pytest.approx(result, nan=True), "IRR should not be NaN"
    assert -1 < result < 1, f"Expected IRR between -100% and 100%, got {result}"


if __name__ == "__main__":
    test_small_value_irr()
    print("Test passed!")
EOFTEST

# Create requirements.txt
cat > "$WORKSPACE_DIR/requirements.txt" << 'EOFREQ'
numpy==1.24.0
numpy-financial==1.0.0
pandas==2.0.0
pytest==7.4.0
# Internal company dependencies (not public):
# company-internal-risk-models==2.3.1
# company-internal-database==1.5.0
EOFREQ

# Create task instructions
cat > "$WORKSPACE_DIR/TASK_INSTRUCTIONS.md" << 'EOFINSTRUCT'
# Task: Extract Minimal Reproducible Example

## Situation
Your production code (`production_code.py`) has a bug in IRR calculation when 
cash flows include very small values near zero. The production codebase has 
complex business logic, database connections, and internal dependencies that 
cannot be shared publicly.

## The Bug
Located in the `_normalize_currency()` method, which returns: