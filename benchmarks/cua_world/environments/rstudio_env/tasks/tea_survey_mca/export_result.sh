#!/bin/bash
echo "=== Exporting Tea Survey MCA Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/RProjects/output"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize result variables
EIGEN_EXISTS="false"
EIGEN_IS_NEW="false"
COORDS_EXISTS="false"
COORDS_IS_NEW="false"
PLOT_EXISTS="false"
PLOT_IS_NEW="false"
SUMMARY_EXISTS="false"
SUMMARY_CONTENT=""
PKG_INSTALLED="false"

# Check Eigenvalues CSV
if [ -f "$OUTPUT_DIR/mca_eigenvalues.csv" ]; then
    EIGEN_EXISTS="true"
    MTIME=$(stat -c %Y "$OUTPUT_DIR/mca_eigenvalues.csv" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        EIGEN_IS_NEW="true"
    fi
fi

# Check Coordinates CSV
if [ -f "$OUTPUT_DIR/mca_coordinates.csv" ]; then
    COORDS_EXISTS="true"
    MTIME=$(stat -c %Y "$OUTPUT_DIR/mca_coordinates.csv" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        COORDS_IS_NEW="true"
    fi
fi

# Check Biplot PNG
if [ -f "$OUTPUT_DIR/mca_biplot.png" ]; then
    PLOT_EXISTS="true"
    MTIME=$(stat -c %Y "$OUTPUT_DIR/mca_biplot.png" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        PLOT_IS_NEW="true"
    fi
    PLOT_SIZE=$(stat -c %s "$OUTPUT_DIR/mca_biplot.png" 2>/dev/null || echo "0")
else
    PLOT_SIZE="0"
fi

# Check Summary Text
if [ -f "$OUTPUT_DIR/mca_summary.txt" ]; then
    SUMMARY_EXISTS="true"
    SUMMARY_CONTENT=$(cat "$OUTPUT_DIR/mca_summary.txt" | head -n 1)
fi

# Check if FactoMineR is installed
PKG_CHECK=$(R --slave -e "cat(requireNamespace('FactoMineR', quietly=TRUE))" 2>/dev/null)
if [ "$PKG_CHECK" == "TRUE" ]; then
    PKG_INSTALLED="true"
fi

# Extract values from CSVs for verification using a temporary R script
# We do this here to avoid complex CSV parsing in bash or python without pandas
cat > /tmp/verify_values.R << 'R_EOF'
json_out <- list()

# Check Eigenvalues
tryCatch({
    if(file.exists("/home/ga/RProjects/output/mca_eigenvalues.csv")) {
        df <- read.csv("/home/ga/RProjects/output/mca_eigenvalues.csv")
        # Look for eigenvalue column (flexible naming)
        val_col <- grep("eigen|inertia", names(df), ignore.case=TRUE, value=TRUE)[1]
        if(!is.na(val_col)) {
            json_out$dim1_eigen <- df[1, val_col]
            json_out$dim2_eigen <- df[2, val_col]
        }
    }
}, error=function(e) { json_out$error_eigen <- e$message })

# Check Coordinates
tryCatch({
    if(file.exists("/home/ga/RProjects/output/mca_coordinates.csv")) {
        df <- read.csv("/home/ga/RProjects/output/mca_coordinates.csv")
        # Just grab the first few rows to check structure
        json_out$coord_rows <- nrow(df)
        json_out$coord_cols <- names(df)
        
        # Check specific known categories if possible (Tea shop usually high on Dim1)
        # We'll just pass the data to python to verify
        json_out$coord_sample <- head(df, 5)
    }
}, error=function(e) { json_out$error_coords <- e$message })

# Output JSON
library(jsonlite)
cat(toJSON(json_out, auto_unbox=TRUE))
R_EOF

# Run extraction script
R_VALUES=$(R --slave -f /tmp/verify_values.R 2>/dev/null || echo "{}")

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "eigen_exists": $EIGEN_EXISTS,
    "eigen_is_new": $EIGEN_IS_NEW,
    "coords_exists": $COORDS_EXISTS,
    "coords_is_new": $COORDS_IS_NEW,
    "plot_exists": $PLOT_EXISTS,
    "plot_is_new": $PLOT_IS_NEW,
    "plot_size_bytes": $PLOT_SIZE,
    "summary_exists": $SUMMARY_EXISTS,
    "summary_content": "$SUMMARY_CONTENT",
    "pkg_installed": $PKG_INSTALLED,
    "r_extracted_values": $R_VALUES
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="