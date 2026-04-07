#!/bin/bash
set -e
echo "=== Setting up Executive Dashboard Task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_executive_dashboard"
PROJECT_DIR="/home/ga/PycharmProjects/executive_dashboard"

# Cleanup previous
rm -rf "$PROJECT_DIR"
rm -f /tmp/${TASK_NAME}_result.json /tmp/${TASK_NAME}_start_ts

# Create Directory Structure
su - ga -c "mkdir -p $PROJECT_DIR/data $PROJECT_DIR/reporting $PROJECT_DIR/tests $PROJECT_DIR/output"

# 1. Generate Data (financials.csv)
cat > "$PROJECT_DIR/data/financials.csv" << 'CSVEOF'
Date,Region,Revenue,Fixed_Cost,Variable_Cost,Profit
Jan-2023,North,1200000,400000,300000,500000
Feb-2023,North,1300000,400000,350000,550000
Mar-2023,North,1250000,400000,320000,530000
Apr-2023,North,1400000,420000,380000,600000
May-2023,North,1500000,420000,400000,680000
Jun-2023,North,1600000,420000,450000,730000
Jan-2023,South,800000,300000,200000,300000
Feb-2023,South,850000,300000,220000,330000
Mar-2023,South,900000,300000,240000,360000
Apr-2023,South,880000,310000,230000,340000
May-2023,South,920000,310000,250000,360000
Jun-2023,South,950000,310000,260000,380000
Jan-2023,East,2000000,600000,500000,900000
Feb-2023,East,2100000,600000,550000,950000
Mar-2023,East,2050000,600000,520000,930000
Apr-2023,East,2200000,620000,600000,980000
May-2023,East,2300000,620000,650000,1030000
Jun-2023,East,2400000,620000,700000,1080000
Jan-2023,West,1500000,500000,400000,600000
Feb-2023,West,1550000,500000,420000,630000
Mar-2023,West,1600000,500000,450000,650000
Apr-2023,West,1580000,510000,440000,630000
May-2023,West,1650000,510000,480000,660000
Jun-2023,West,1700000,510000,500000,690000
CSVEOF

# 2. reporting/data.py (Contains Bug 1: Date Sorting)
cat > "$PROJECT_DIR/reporting/data.py" << 'PYEOF'
import pandas as pd
import os

def load_data(filepath):
    """Load and clean financial data."""
    if not os.path.exists(filepath):
        raise FileNotFoundError(f"File not found: {filepath}")
    
    df = pd.read_csv(filepath)
    
    # BUG 1: Sorting by 'Date' string causes alphabetical sort (Apr, Aug, Dec, Feb...)
    # Should convert to datetime first
    df = df.sort_values(by='Date')
    
    return df

def get_monthly_summary(df):
    """Aggregate data by month."""
    # Grouping by string Date preserves the bad sort order if not fixed
    summary = df.groupby('Date')[['Revenue', 'Fixed_Cost', 'Variable_Cost']].sum().reset_index()
    return summary

def get_regional_summary(df):
    """Aggregate profit by region."""
    summary = df.groupby('Region')['Profit'].sum().reset_index()
    return summary
PYEOF

# 3. reporting/dashboard.py (Contains Bugs 2, 3, 4)
cat > "$PROJECT_DIR/reporting/dashboard.py" << 'PYEOF'
import matplotlib.pyplot as plt
import pandas as pd

def generate_dashboard(monthly_df, regional_df, output_path):
    """Generate the executive dashboard figure."""
    
    # Create a layout with 3 subplots
    fig = plt.figure(figsize=(15, 10))
    gs = fig.add_gridspec(2, 2)
    
    ax1 = fig.add_subplot(gs[0, :])  # Top: Revenue Trend
    ax2 = fig.add_subplot(gs[1, 0])  # Bottom Left: Cost Structure
    ax3 = fig.add_subplot(gs[1, 1])  # Bottom Right: Regional Profit
    
    # --- PLOT 1: Revenue Trend ---
    ax1.plot(monthly_df['Date'], monthly_df['Revenue'], marker='o', linestyle='-', color='blue')
    ax1.set_title('Monthly Revenue Trend')
    ax1.set_xlabel('Month')
    
    # BUG 3: Scale Mismatch
    # Label says Millions, but data is raw (e.g. 1,500,000)
    ax1.set_ylabel('Revenue (Millions USD)')
    ax1.grid(True)
    
    # --- PLOT 2: Cost Structure (Stacked Bar) ---
    months = monthly_df['Date']
    fixed = monthly_df['Fixed_Cost']
    variable = monthly_df['Variable_Cost']
    
    ax2.bar(months, fixed, label='Fixed Costs', color='gray')
    
    # BUG 2: Hidden Data (Missing bottom parameter)
    # The variable costs are drawn starting from 0, overlapping fixed costs
    ax2.bar(months, variable, label='Variable Costs', color='orange')
    
    ax2.set_title('Cost Structure')
    ax2.set_ylabel('Cost (USD)')
    ax2.legend()
    plt.setp(ax2.xaxis.get_majorticklabels(), rotation=45)
    
    # --- PLOT 3: Regional Profit (Pie) ---
    # BUG 4: Legend Error
    # We plot the data as is, but sort the legend labels alphabetically.
    # If the dataframe isn't sorted alphabetically by region, this mismatches.
    wedges, texts, autotexts = ax3.pie(regional_df['Profit'], autopct='%1.1f%%', startangle=90)
    
    ax3.set_title('Profit Share by Region')
    
    # Force a mismatch by sorting labels but not data
    sorted_labels = sorted(regional_df['Region'])
    ax3.legend(wedges, sorted_labels, title="Regions", loc="center left", bbox_to_anchor=(1, 0, 0.5, 1))

    plt.tight_layout()
    plt.savefig(output_path)
    print(f"Dashboard saved to {output_path}")
    return fig
PYEOF

# 4. main.py
cat > "$PROJECT_DIR/main.py" << 'PYEOF'
import os
from reporting.data import load_data, get_monthly_summary, get_regional_summary
from reporting.dashboard import generate_dashboard

def main():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    data_path = os.path.join(base_dir, 'data', 'financials.csv')
    output_path = os.path.join(base_dir, 'output', 'dashboard.png')
    
    print("Loading data...")
    df = load_data(data_path)
    
    print("Aggregating data...")
    monthly_summary = get_monthly_summary(df)
    regional_summary = get_regional_summary(df)
    
    print("Generating dashboard...")
    generate_dashboard(monthly_summary, regional_summary, output_path)

if __name__ == "__main__":
    main()
PYEOF

# 5. Tests
cat > "$PROJECT_DIR/tests/test_dashboard.py" << 'PYEOF'
import pytest
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
from reporting.dashboard import generate_dashboard
from datetime import datetime

@pytest.fixture
def sample_data():
    # Create controlled data for testing
    dates = ['Jan-2023', 'Feb-2023', 'Mar-2023']
    # Sorted chronologically, but alphabetical would be Feb, Jan, Mar
    monthly_data = {
        'Date': dates,
        'Revenue': [1000000, 2000000, 1500000],
        'Fixed_Cost': [100, 100, 100],
        'Variable_Cost': [50, 50, 50]
    }
    monthly_df = pd.DataFrame(monthly_data)
    
    regional_data = {
        'Region': ['West', 'East', 'North'], # Not alphabetical
        'Profit': [100, 200, 50]
    }
    regional_df = pd.DataFrame(regional_data)
    return monthly_df, regional_df

def test_timeline_is_chronological(sample_data, tmp_path):
    """Test that the x-axis dates are handled chronologically, not alphabetically."""
    m_df, r_df = sample_data
    # Force the dataframe to have proper datetime objects or sorted order for the test
    # The actual fix in the app is in data.py, but here we test if the PLOT respects order
    # if passed correctly, or if the user fixed the dataframe passed to it.
    
    # We rely on the user fixing data.py to pass sorted data.
    # To test the fix end-to-end, we should import load_data, but let's test the plot logic 
    # assuming correct input, OR verify that the X-axis data in the plot matches input order.
    
    fig = generate_dashboard(m_df, r_df, str(tmp_path / "test.png"))
    ax1 = fig.axes[0]
    
    # Get x-axis tick labels or data
    lines = ax1.get_lines()[0]
    x_data = lines.get_xdata()
    
    # If dates are strings, Matplotlib plots them in order of appearance usually.
    # The Bug 1 is in data.py (sorting alphabetically).
    # This test might pass on the dashboard function itself if input is already sorted.
    # Let's verify data.py logic instead for this one.
    pass 

def test_data_loader_sorts_chronologically(tmp_path):
    """Bug 1: Verify data loader sorts dates correctly."""
    from reporting.data import load_data
    
    csv_path = tmp_path / "data.csv"
    with open(csv_path, "w") as f:
        f.write("Date,Region,Revenue,Fixed_Cost,Variable_Cost,Profit\n")
        f.write("Apr-2023,N,1,1,1,1\n")
        f.write("Jan-2023,N,1,1,1,1\n")
    
    df = load_data(str(csv_path))
    
    # Should be Jan then Apr
    assert df.iloc[0]['Date'] == 'Jan-2023', "First row should be Jan-2023 (Chronological)"
    assert df.iloc[1]['Date'] == 'Apr-2023', "Second row should be Apr-2023"

def test_stacked_bars_are_stacked(sample_data, tmp_path):
    """Bug 2: Verify bar chart is stacked."""
    m_df, r_df = sample_data
    fig = generate_dashboard(m_df, r_df, str(tmp_path / "test.png"))
    ax2 = fig.axes[1] # Cost structure
    
    # Check for bars
    containers = ax2.containers
    assert len(containers) >= 2, "Should have at least 2 bar containers (Fixed and Variable)"
    
    # The second container (Variable) should have 'bottom' set to Fixed heights
    variable_bars = containers[1]
    fixed_heights = [rect.get_height() for rect in containers[0]]
    
    # Check bottom of first bar in variable group
    # Using small epsilon for float comparison
    first_bar_bottom = variable_bars[0].get_y()
    assert abs(first_bar_bottom - fixed_heights[0]) < 0.001, \
        f"Bars are not stacked. Variable cost started at {first_bar_bottom}, expected {fixed_heights[0]}"

def test_y_axis_scaling_matches_label(sample_data, tmp_path):
    """Bug 3: Verify Y-axis scaling."""
    m_df, r_df = sample_data
    fig = generate_dashboard(m_df, r_df, str(tmp_path / "test.png"))
    ax1 = fig.axes[0] # Revenue
    
    y_label = ax1.get_ylabel()
    max_data = ax1.get_ylim()[1]
    
    if "Millions" in y_label:
        # If label says Millions, data should be small numbers (e.g. 1.0, 2.0)
        # Input data is 1,000,000. So max should be around 2-3, not 2,000,000.
        assert max_data < 1000, f"Label says Millions but max value is {max_data}. Did you divide by 1e6?"
    else:
        # If they changed the label to 'Revenue', that's also acceptable
        pass

def test_pie_chart_legend_match(sample_data, tmp_path):
    """Bug 4: Verify pie chart legend matches slices."""
    m_df, r_df = sample_data
    fig = generate_dashboard(m_df, r_df, str(tmp_path / "test.png"))
    ax3 = fig.axes[2] # Regional Profit
    
    legend = ax3.get_legend()
    legend_labels = [t.get_text() for t in legend.get_texts()]
    
    # The input dataframe was West, East, North (in that order)
    # The bug sorts legend to East, North, West
    # But Matplotlib pie plots in data order (West, East, North)
    
    # We check if the first legend label matches the first data point's label
    # In the buggy version: Legend[0]=East, Data[0]=West. Mismatch.
    
    first_legend = legend_labels[0]
    first_data_label = r_df.iloc[0]['Region']
    
    assert first_legend == first_data_label, \
        f"Legend mismatch! First legend item is {first_legend} but first data slice is {first_data_label}"
PYEOF

cat > "$PROJECT_DIR/requirements.txt" << 'PYEOF'
pandas
matplotlib
pytest
PYEOF

# Create init
touch "$PROJECT_DIR/reporting/__init__.py"

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Timestamp
date +%s > /tmp/${TASK_NAME}_start_ts

# Setup PyCharm project (open it)
echo "Opening PyCharm..."
source /workspace/scripts/task_utils.sh
setup_pycharm_project "$PROJECT_DIR"

echo "=== Setup Complete ==="