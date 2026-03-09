#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Print-to-PDF Landscape Task Setup ==="
echo "Task: Export webpage as PDF with landscape orientation"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install PDF processing libraries
pip3 install -q PyPDF2 pypdf 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create a sample webpage with wide content suitable for landscape
echo "Creating sample webpage with wide content..."
ARTICLE_DIR="/home/ga/Documents"
mkdir -p "$ARTICLE_DIR"

cat > "$ARTICLE_DIR/data_analysis_guide.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Data Analysis Best Practices Guide</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            margin: 30px;
            max-width: 1400px;
        }
        h1 { color: #2c3e50; margin-top: 20px; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        h2 { color: #34495e; margin-top: 15px; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; font-size: 14px; }
        th, td { border: 1px solid #ddd; padding: 10px; text-align: left; }
        th { background-color: #3498db; color: white; font-weight: bold; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .code-block { background-color: #f4f4f4; padding: 15px; font-family: monospace; overflow-x: auto; margin: 15px 0; }
        .note { background-color: #fff3cd; padding: 15px; border-left: 4px solid #ffc107; margin: 15px 0; }
    </style>
</head>
<body>
    <h1>Data Analysis Best Practices: A Comprehensive Guide</h1>
    
    <h2>1. Introduction to Data Analysis Workflows</h2>
    <p>Data analysis is a systematic process of inspecting, cleaning, transforming, and modeling data to discover useful information, draw conclusions, and support decision-making. This guide covers essential practices for effective data analysis across different domains and tools.</p>

    <h2>2. Common Data Analysis Tools Comparison</h2>
    <table>
        <thead>
            <tr>
                <th>Tool</th>
                <th>Primary Language</th>
                <th>Best For</th>
                <th>Data Size Limit</th>
                <th>Learning Curve</th>
                <th>Cost</th>
                <th>Key Libraries/Features</th>
            </tr>
        </thead>
        <tbody>
            <tr>
                <td>Python (Pandas)</td>
                <td>Python</td>
                <td>General purpose, ML integration</td>
                <td>~100M rows</td>
                <td>Medium</td>
                <td>Free</td>
                <td>NumPy, SciPy, Matplotlib, Scikit-learn</td>
            </tr>
            <tr>
                <td>R (dplyr/tidyverse)</td>
                <td>R</td>
                <td>Statistical analysis, visualization</td>
                <td>~50M rows</td>
                <td>Medium</td>
                <td>Free</td>
                <td>ggplot2, tidyr, stringr, forcats</td>
            </tr>
            <tr>
                <td>Excel</td>
                <td>Formulas/VBA</td>
                <td>Quick analysis, business reporting</td>
                <td>~1M rows</td>
                <td>Low</td>
                <td>Paid</td>
                <td>PivotTables, Power Query, Solver</td>
            </tr>
            <tr>
                <td>SQL (PostgreSQL)</td>
                <td>SQL</td>
                <td>Relational data, aggregations</td>
                <td>Billions of rows</td>
                <td>Medium</td>
                <td>Free</td>
                <td>Window functions, CTEs, JSON support</td>
            </tr>
            <tr>
                <td>Tableau</td>
                <td>Drag-and-drop</td>
                <td>Interactive dashboards, viz</td>
                <td>~10M rows (local)</td>
                <td>Low-Medium</td>
                <td>Paid</td>
                <td>Real-time analytics, story points</td>
            </tr>
            <tr>
                <td>Apache Spark</td>
                <td>Python/Scala</td>
                <td>Big data, distributed computing</td>
                <td>Petabytes</td>
                <td>High</td>
                <td>Free</td>
                <td>MLlib, Spark SQL, Streaming</td>
            </tr>
        </tbody>
    </table>

    <h2>3. Data Cleaning Checklist</h2>
    <table>
        <thead>
            <tr>
                <th>Issue Type</th>
                <th>Detection Method</th>
                <th>Resolution Strategy</th>
                <th>Python Example</th>
                <th>Impact Level</th>
            </tr>
        </thead>
        <tbody>
            <tr>
                <td>Missing Values</td>
                <td>df.isnull().sum()</td>
                <td>Imputation, deletion, flagging</td>
                <td>df.fillna(df.mean())</td>
                <td>High</td>
            </tr>
            <tr>
                <td>Duplicates</td>
                <td>df.duplicated().sum()</td>
                <td>Remove or aggregate</td>
                <td>df.drop_duplicates()</td>
                <td>Medium</td>
            </tr>
            <tr>
                <td>Outliers</td>
                <td>IQR method, Z-score</td>
                <td>Cap, remove, or investigate</td>
                <td>df[df['col'] < Q3 + 1.5*IQR]</td>
                <td>Medium</td>
            </tr>
            <tr>
                <td>Type Mismatches</td>
                <td>df.dtypes</td>
                <td>Convert to correct type</td>
                <td>pd.to_datetime(df['date'])</td>
                <td>High</td>
            </tr>
            <tr>
                <td>Inconsistent Formatting</td>
                <td>df['col'].unique()</td>
                <td>Standardize strings, dates</td>
                <td>df['col'].str.lower().str.strip()</td>
                <td>Medium</td>
            </tr>
        </tbody>
    </table>

    <h2>4. Statistical Tests Selection Guide</h2>
    <table>
        <thead>
            <tr>
                <th>Test Name</th>
                <th>Purpose</th>
                <th>Data Type</th>
                <th>Sample Size</th>
                <th>Assumptions</th>
                <th>Python Implementation</th>
            </tr>
        </thead>
        <tbody>
            <tr>
                <td>T-Test</td>
                <td>Compare means of two groups</td>
                <td>Continuous</td>
                <td>n > 30 recommended</td>
                <td>Normality, independence</td>
                <td>scipy.stats.ttest_ind()</td>
            </tr>
            <tr>
                <td>ANOVA</td>
                <td>Compare means of 3+ groups</td>
                <td>Continuous</td>
                <td>n > 20 per group</td>
                <td>Normality, homogeneity</td>
                <td>scipy.stats.f_oneway()</td>
            </tr>
            <tr>
                <td>Chi-Square</td>
                <td>Test independence (categorical)</td>
                <td>Categorical</td>
                <td>Expected freq > 5</td>
                <td>Independence</td>
                <td>scipy.stats.chi2_contingency()</td>
            </tr>
            <tr>
                <td>Correlation</td>
                <td>Measure linear relationship</td>
                <td>Continuous</td>
                <td>n > 30</td>
                <td>Linearity</td>
                <td>df.corr() or scipy.stats.pearsonr()</td>
            </tr>
            <tr>
                <td>Mann-Whitney U</td>
                <td>Non-parametric comparison</td>
                <td>Ordinal/Continuous</td>
                <td>Any size</td>
                <td>Independence only</td>
                <td>scipy.stats.mannwhitneyu()</td>
            </tr>
        </tbody>
    </table>

    <div class="note">
        <strong>Note:</strong> When working with wide datasets and complex tables, landscape orientation provides better readability and prevents content truncation. This is especially important for comparison tables, code snippets, and multi-column data displays.
    </div>

    <h2>5. Data Visualization Best Practices</h2>
    <p>Effective data visualization requires careful consideration of chart types, colors, and layout. Always choose visualizations that match your data type and communication goals. For time series data, use line charts; for comparisons, use bar charts; for distributions, use histograms or box plots.</p>

    <div class="code-block">
# Example: Creating a comprehensive data analysis workflow
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from scipy import stats

# Load and inspect data
df = pd.read_csv('data.csv')
print(df.info())
print(df.describe())

# Data cleaning
df = df.drop_duplicates()
df = df.fillna(df.median(numeric_only=True))

# Statistical analysis
correlation_matrix = df.corr()
t_statistic, p_value = stats.ttest_ind(df['group_a'], df['group_b'])

# Visualization
fig, axes = plt.subplots(2, 2, figsize=(12, 10))
df['column1'].hist(ax=axes[0, 0])
df.boxplot(column='column2', by='category', ax=axes[0, 1])
axes[1, 0].scatter(df['x'], df['y'])
correlation_matrix.plot(kind='bar', ax=axes[1, 1])
plt.tight_layout()
plt.savefig('analysis_results.png', dpi=300)
    </div>

    <h2>6. Performance Optimization Tips</h2>
    <ul>
        <li><strong>Vectorization:</strong> Use vectorized operations instead of loops (e.g., df['new'] = df['a'] + df['b'] instead of iterating)</li>
        <li><strong>Chunking:</strong> Process large files in chunks to manage memory (pd.read_csv with chunksize parameter)</li>
        <li><strong>Data Types:</strong> Optimize dtypes (use category for repeated strings, int8/int16 for small integers)</li>
        <li><strong>Indexing:</strong> Set appropriate indexes for faster lookups and joins</li>
        <li><strong>Caching:</strong> Cache intermediate results to avoid redundant computations</li>
    </ul>

    <h2>7. Conclusion</h2>
    <p>Effective data analysis requires a combination of technical skills, statistical knowledge, and domain expertise. By following these best practices and leveraging appropriate tools, analysts can extract meaningful insights from data efficiently and accurately. Remember to always validate assumptions, document your process, and communicate results clearly to stakeholders.</p>

</body>
</html>
EOF

chown ga:ga "$ARTICLE_DIR/data_analysis_guide.html"
echo "✓ Article HTML created at: $ARTICLE_DIR/data_analysis_guide.html"

# Ensure Chrome is properly focused and ready
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank" &
    sleep 5
else
    echo "Chrome is already running"
fi

# Wait for Chrome to be fully ready
sleep 2

# IMPORTANT: Click at center to select desktop (multi-desktop environments)
# This ensures we're on the first desktop where Chrome is running
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Chrome window using wmctrl
export DISPLAY=:1
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -z "$wid" ]; then
    echo "Warning: Could not find Chrome window"
else
    echo "Focusing Chrome window: $wid"
    wmctrl -i -a $wid || true
    sleep 1
fi

# Navigate to the article
ARTICLE_URL="file:///home/ga/Documents/data_analysis_guide.html"
echo "Navigating to: $ARTICLE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/data_analysis_guide.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome should be displaying the Data Analysis Guide with wide tables"
echo "Agent should now:"
echo "  1. Press Ctrl+P to open print dialog"
echo "  2. Select 'Save as PDF' as destination"
echo "  3. Choose Landscape orientation"
echo "  4. Save as: webpage_landscape_export.pdf"