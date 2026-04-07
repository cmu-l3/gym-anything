#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Quant Backtest Bias Task ==="

WORKSPACE_DIR="/home/ga/workspace/quant_backtester"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"
cd "$WORKSPACE_DIR"

# ─────────────────────────────────────────────────────────────
# 1. Fetch Real Market Data and Inject Missing Values (NaNs)
# ─────────────────────────────────────────────────────────────
echo "Fetching real market data..."

# Using Plotly's public dataset for Apple stock (real historical data)
wget -q -O "$WORKSPACE_DIR/data/AAPL_raw.csv" "https://raw.githubusercontent.com/plotly/datasets/master/finance-charts-apple.csv"

# Process the data to create realistic missing values (NaNs) to test the imputation bug
python3 << 'PYDATA'
import pandas as pd
import numpy as np

# Load real data
df = pd.read_csv('/home/ga/workspace/quant_backtester/data/AAPL_raw.csv')

# Standardize columns to match typical financial datasets
df = df[['Date', 'AAPL.Open', 'AAPL.High', 'AAPL.Low', 'AAPL.Close', 'AAPL.Volume']]
df.columns = ['Date', 'Open', 'High', 'Low', 'Close', 'Volume']

# Inject NaNs randomly (approx 2% of the time) to trigger the imputation bug
np.random.seed(42)
mask = np.random.rand(len(df)) < 0.02
df.loc[mask, 'Close'] = np.nan

df.to_csv('/home/ga/workspace/quant_backtester/data/market_data.csv', index=False)
PYDATA

rm "$WORKSPACE_DIR/data/AAPL_raw.csv"
chown -R ga:ga "$WORKSPACE_DIR/data"

# ─────────────────────────────────────────────────────────────
# 2. Create the Buggy Backtest Engine
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/backtest_engine.py" << 'EOF'
import pandas as pd
import numpy as np

class BacktestEngine:
    def __init__(self, data_path, cost_per_trade=0.001):
        self.df = pd.read_csv(data_path)
        self.cost_per_trade = cost_per_trade

    def impute_data(self):
        """Handle missing price data."""
        # BUG 1: Future leakage. Uses the global mean to fill past missing values.
        self.df['Close'] = self.df['Close'].fillna(self.df['Close'].mean())

    def calculate_signals(self):
        """Generate trading signals (Simple Moving Average Crossover)."""
        self.df['SMA_10'] = self.df['Close'].rolling(window=10).mean()
        self.df['SMA_50'] = self.df['Close'].rolling(window=50).mean()
        
        # 1 = Long, 0 = Neutral
        self.df['Position'] = np.where(self.df['SMA_10'] > self.df['SMA_50'], 1, 0)

    def calculate_returns(self):
        """Calculate daily and cumulative strategy returns."""
        self.df['Daily_Return'] = self.df['Close'].pct_change()

        # BUG 2: Lookahead bias. Multiplies today's position by today's return.
        # Since position is decided at the end of the day, it captures today's return retroactively!
        self.df['Strategy_Return'] = self.df['Position'] * self.df['Daily_Return']

    def apply_costs(self):
        """Deduct transaction costs."""
        # BUG 3: Overcharging. Subtracts cost every day a position is held.
        days_in_market = (self.df['Position'].abs() > 0).astype(int)
        self.df['Strategy_Return'] -= days_in_market * self.cost_per_trade

    def calculate_drawdown(self):
        """Calculate maximum drawdown."""
        self.df['Cumulative_Return'] = (1 + self.df['Strategy_Return']).cumprod()
        
        # BUG 4: Global Max Drawdown. Compares to the absolute global peak of the entire timeline.
        global_peak = self.df['Cumulative_Return'].max()
        self.df['Drawdown'] = (self.df['Cumulative_Return'] - global_peak) / global_peak

    def run(self):
        self.impute_data()
        self.calculate_signals()
        self.calculate_returns()
        self.apply_costs()
        self.calculate_drawdown()

        metrics = {
            'Total_Return_Pct': round((self.df['Cumulative_Return'].iloc[-1] - 1) * 100, 2),
            'Max_Drawdown_Pct': round(self.df['Drawdown'].min() * 100, 2),
            'Annualized_Vol_Pct': round(self.df['Strategy_Return'].std() * np.sqrt(252) * 100, 2)
        }
        return metrics
EOF

# ─────────────────────────────────────────────────────────────
# 3. Create Runner Script
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/run_backtest.py" << 'EOF'
from backtest_engine import BacktestEngine
import json

if __name__ == "__main__":
    print("Initializing Backtest Engine...")
    engine = BacktestEngine('data/market_data.csv')
    
    print("Running Backtest...")
    results = engine.run()
    
    print("\n--- Backtest Results ---")
    print(json.dumps(results, indent=4))
    
    if results['Total_Return_Pct'] > 100:
        print("\nWARNING: Extremely high returns detected. Check for lookahead bias!")
EOF

chown -R ga:ga "$WORKSPACE_DIR"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Start VSCode in the workspace
if ! pgrep -f "code.*--ms-enable-electron" > /dev/null; then
    su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR/backtest_engine.py &"
    sleep 5
fi

# Wait for VSCode and maximize
wait_for_vscode 30
WID=$(get_vscode_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot showing the buggy code
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="