#!/bin/bash
set -e
echo "=== Setting up SUR Grunfeld Investment Task ==="

source /workspace/scripts/task_utils.sh

DATA_DIR="/home/ga/Documents/gretl_data"
mkdir -p "$DATA_DIR"

# ==============================================================================
# Create Grunfeld Dataset (Real Data from Grunfeld, 1958 / Greene Table F13.1)
# ==============================================================================
# 20 observations (1935-1954)
# Variables:
#   invest_ge:  GE Gross Investment
#   value_ge:   GE Market Value
#   capital_ge: GE Capital Stock
#   invest_wh:  Westinghouse Gross Investment
#   value_wh:   Westinghouse Market Value
#   capital_wh: Westinghouse Capital Stock
# ==============================================================================

cat > "$DATA_DIR/grunfeld.gdt" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE gretldata SYSTEM "gretldata.dtd">
<gretldata name="Grunfeld" frequency="1" startobs="1935" endobs="1954" type="time-series">
<description>
Grunfeld (1958) Investment Data for GE and Westinghouse.
Data source: Greene (2012) Table F13.1.
</description>
<variables count="6">
<variable name="invest_ge" label="GE Gross Investment" />
<variable name="value_ge" label="GE Market Value" />
<variable name="capital_ge" label="GE Capital Stock" />
<variable name="invest_wh" label="WH Gross Investment" />
<variable name="value_wh" label="WH Market Value" />
<variable name="capital_wh" label="WH Capital Stock" />
</variables>
<observations count="20" labels="false">
<obs>33.1 1170.6 97.8 12.93 191.5 1.8</obs>
<obs>45.0 2015.8 104.4 25.90 516.0 0.8</obs>
<obs>77.2 2803.3 118.0 35.05 729.0 7.4</obs>
<obs>44.6 2039.7 156.2 22.89 560.4 18.1</obs>
<obs>48.1 2256.2 172.6 18.84 519.9 23.5</obs>
<obs>74.4 2132.2 186.6 28.57 628.5 26.5</obs>
<obs>113.0 1834.1 220.9 48.51 537.1 36.2</obs>
<obs>91.9 1588.0 287.8 43.34 561.2 60.8</obs>
<obs>61.3 1749.4 319.9 37.02 617.2 84.4</obs>
<obs>56.8 1687.2 321.3 37.81 626.7 91.2</obs>
<obs>93.6 2007.7 319.6 39.27 737.2 92.4</obs>
<obs>159.9 2208.3 346.0 53.46 760.5 86.0</obs>
<obs>147.2 1656.7 456.4 55.56 581.4 111.1</obs>
<obs>146.3 1604.4 543.4 49.56 662.3 130.6</obs>
<obs>98.3 1431.8 618.3 32.04 583.8 141.8</obs>
<obs>93.5 1610.5 647.4 32.24 635.2 136.7</obs>
<obs>135.2 1819.4 671.3 54.38 723.8 129.7</obs>
<obs>157.3 2079.7 726.1 71.78 864.1 145.5</obs>
<obs>179.5 2371.6 800.3 90.08 1193.5 174.8</obs>
<obs>189.6 2759.9 888.9 68.60 1188.9 213.5</obs>
</observations>
</gretldata>
EOF

chown ga:ga "$DATA_DIR/grunfeld.gdt"
chmod 644 "$DATA_DIR/grunfeld.gdt"

# ==============================================================================
# Setup Environment
# ==============================================================================

# Ensure output directory exists and is empty of previous results
mkdir -p /home/ga/Documents/gretl_output
rm -f /home/ga/Documents/gretl_output/sur_results.txt
chown -R ga:ga /home/ga/Documents/gretl_output

# Launch Gretl with the dataset
setup_gretl_task "grunfeld.gdt" "sur_grunfeld"

echo "=== Task setup complete ==="
echo "Dataset: Grunfeld Investment Data (GE & Westinghouse)"
echo "Output required at: /home/ga/Documents/gretl_output/sur_results.txt"