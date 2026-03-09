#!/bin/bash
set -e
echo "=== Setting up Consolidate Portfolios Task ==="

# Define paths
JSTOCK_DIR="/home/ga/.jstock/1.0.7/UnitedState"
PORTFOLIO_ROOT="$JSTOCK_DIR/portfolios"

# Ensure clean slate for portfolios
rm -rf "$PORTFOLIO_ROOT"
mkdir -p "$PORTFOLIO_ROOT"

# ============================================================
# 1. Create Retirement Portfolio (Source 1)
# ============================================================
mkdir -p "$PORTFOLIO_ROOT/Retirement"
cat > "$PORTFOLIO_ROOT/Retirement/buyportfolio.csv" << 'EOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"VTI","Vanguard Total Stock Market","Jan 15, 2023","100.0","195.5","0.0","19550.0","0.0","-195.5","-19550.0","-100.0","0.0","0.0","0.0","19550.0","-19550.0","-100.0","Long Term"
"BND","Vanguard Total Bond Market","Jan 15, 2023","200.0","72.4","0.0","14480.0","0.0","-72.4","-14480.0","-100.0","0.0","0.0","0.0","14480.0","-14480.0","-100.0","Safety"
EOF
# Create required companion files
echo '"Code","Symbol","Date","Units","Selling Price","Purchase Price","Selling Value","Purchase Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Selling Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"' > "$PORTFOLIO_ROOT/Retirement/sellportfolio.csv"
echo '"Date","Amount","Comment"' > "$PORTFOLIO_ROOT/Retirement/depositsummary.csv"
echo '"Code","Symbol","Date","Amount","Comment"' > "$PORTFOLIO_ROOT/Retirement/dividendsummary.csv"

# ============================================================
# 2. Create Trading Portfolio (Source 2)
# ============================================================
mkdir -p "$PORTFOLIO_ROOT/Trading"
cat > "$PORTFOLIO_ROOT/Trading/buyportfolio.csv" << 'EOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"COIN","Coinbase Global","Nov 10, 2023","50.0","85.2","0.0","4260.0","0.0","-85.2","-4260.0","-100.0","0.0","0.0","0.0","4260.0","-4260.0","-100.0","Speculative"
EOF
# Create required companion files
echo '"Code","Symbol","Date","Units","Selling Price","Purchase Price","Selling Value","Purchase Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Selling Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"' > "$PORTFOLIO_ROOT/Trading/sellportfolio.csv"
echo '"Date","Amount","Comment"' > "$PORTFOLIO_ROOT/Trading/depositsummary.csv"
echo '"Code","Symbol","Date","Amount","Comment"' > "$PORTFOLIO_ROOT/Trading/dividendsummary.csv"

# ============================================================
# 3. Create Master Portfolio (Target - Empty)
# ============================================================
mkdir -p "$PORTFOLIO_ROOT/Master"
cat > "$PORTFOLIO_ROOT/Master/buyportfolio.csv" << 'EOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
EOF
# Create required companion files
echo '"Code","Symbol","Date","Units","Selling Price","Purchase Price","Selling Value","Purchase Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Selling Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"' > "$PORTFOLIO_ROOT/Master/sellportfolio.csv"
echo '"Date","Amount","Comment"' > "$PORTFOLIO_ROOT/Master/depositsummary.csv"
echo '"Code","Symbol","Date","Amount","Comment"' > "$PORTFOLIO_ROOT/Master/dividendsummary.csv"

# Fix permissions
chown -R ga:ga /home/ga/.jstock
find /home/ga/.jstock -type d -exec chmod 755 {} \;
find /home/ga/.jstock -type f -exec chmod 644 {} \;

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Launch JStock
if ! pgrep -f "jstock.jar" > /dev/null; then
    echo "Starting JStock..."
    su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock.log 2>&1 &"
    
    # Wait for JStock to start
    echo "Waiting for JStock window..."
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "JStock" > /dev/null; then
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Dismiss news dialog if present
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize JStock
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="