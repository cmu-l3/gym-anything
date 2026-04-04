#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Format Research Paper Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create the unformatted research paper document
# Based on real climate science research with real citations
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt

doc = Document()

# Title (plain text - agent must format as 16pt bold centered)
doc.add_paragraph(
    "Regional Climate Variability and Extreme Weather Events: "
    "A Multi-Decadal Analysis of Temperature and Precipitation Patterns "
    "in the Continental United States, 1950-2020"
)

# Authors (plain text - agent must format as 12pt italic centered)
doc.add_paragraph(
    "Hansen, J., Sato, M., Ruedy, R., Lo, K., and Medina-Elizade, M."
)

doc.add_paragraph("")

# Abstract section
doc.add_paragraph("Abstract")
doc.add_paragraph(
    "This study examines regional climate variability across the continental "
    "United States over a 70-year period from 1950 to 2020. Using data from "
    "the Global Historical Climatology Network (GHCN) and the North American "
    "Regional Reanalysis (NARR), we analyzed temperature and precipitation "
    "trends at 1,218 monitoring stations. Our results indicate a statistically "
    "significant warming trend of 0.16 degrees Celsius per decade (p < 0.001), "
    "with the rate of warming accelerating after 1980. Extreme heat events "
    "increased by 40% in frequency between the periods 1950-1985 and "
    "1986-2020, while extreme cold events decreased by 25%. Precipitation "
    "patterns showed increased variability, with both drought severity and "
    "intense rainfall events becoming more pronounced. These findings are "
    "consistent with global climate model projections and have implications "
    "for agricultural planning, water resource management, and public health "
    "policy in affected regions."
)

doc.add_paragraph("")

# Introduction
doc.add_paragraph("Introduction")
doc.add_paragraph(
    "Climate variability and its associated impacts on extreme weather events "
    "represent one of the most pressing challenges facing modern societies. "
    "The Intergovernmental Panel on Climate Change (IPCC) has documented "
    "widespread changes in temperature and precipitation patterns across the "
    "globe, with particular concern for regions that are both densely populated "
    "and agriculturally productive (IPCC, 2021). The continental United States, "
    "spanning multiple climate zones from the arid Southwest to the humid "
    "Southeast, provides a unique natural laboratory for examining regional "
    "climate variability."
)
doc.add_paragraph(
    "Previous studies have established that global mean surface temperature has "
    "increased by approximately 1.1 degrees Celsius since the pre-industrial "
    "era (Lenssen et al., 2019). However, regional analyses reveal substantial "
    "heterogeneity in both the magnitude and timing of warming trends. Karl "
    "et al. (2009) demonstrated that the rate of warming in the United States "
    "has been significantly higher than the global average, particularly during "
    "winter months. More recently, Vose et al. (2017) documented that minimum "
    "temperatures have increased at nearly twice the rate of maximum "
    "temperatures across much of the country."
)
doc.add_paragraph(
    "The objective of this study is to provide a comprehensive, multi-decadal "
    "analysis of temperature and precipitation variability across the "
    "continental United States, with particular attention to changes in the "
    "frequency and intensity of extreme weather events."
)

doc.add_paragraph("")

# Methods
doc.add_paragraph("Methods")
doc.add_paragraph("")

doc.add_paragraph("Data Collection")
doc.add_paragraph(
    "Temperature and precipitation data were obtained from the Global "
    "Historical Climatology Network Daily (GHCN-D) database maintained by "
    "the National Centers for Environmental Information (NCEI). We selected "
    "1,218 stations across the continental United States that met the "
    "following criteria: (1) continuous daily records spanning at least "
    "60 of the 70 years in the study period, (2) fewer than 5% missing "
    "observations in any given year, and (3) no documented station "
    "relocations greater than 1 kilometer."
)

doc.add_paragraph("")

doc.add_paragraph("Statistical Analysis")
doc.add_paragraph(
    "Trend analysis was performed using the non-parametric Mann-Kendall "
    "test (Mann, 1945; Kendall, 1975), with trend magnitude estimated "
    "using Sen's slope estimator (Sen, 1968). To account for serial "
    "autocorrelation in the time series, we applied the modified "
    "Mann-Kendall test proposed by Hamed and Rao (1998). Extreme events "
    "were defined using percentile-based thresholds: extreme heat was "
    "defined as daily maximum temperature exceeding the local 95th "
    "percentile, and extreme cold as daily minimum temperature falling "
    "below the local 5th percentile."
)

doc.add_paragraph("")

# Results
doc.add_paragraph("Results")
doc.add_paragraph("")

doc.add_paragraph("Temperature Trends")
doc.add_paragraph(
    "The analysis revealed a statistically significant warming trend "
    "across the continental United States, with a mean rate of 0.16 "
    "degrees Celsius per decade over the full 70-year study period "
    "(p < 0.001). However, the rate of warming was not uniform over "
    "time. During the period 1950-1979, the mean warming rate was "
    "0.08 degrees Celsius per decade, while during 1980-2020 the rate "
    "increased to 0.27 degrees Celsius per decade. The acceleration "
    "was statistically significant (p < 0.01) when tested using a "
    "piecewise linear regression model."
)

doc.add_paragraph("")

doc.add_paragraph("Precipitation Patterns")
doc.add_paragraph(
    "Precipitation trends were more spatially heterogeneous than "
    "temperature trends. Nationally averaged annual precipitation "
    "increased by approximately 4% over the study period, but this "
    "average masked substantial regional variation. The Northeast and "
    "Midwest experienced increases of 8-12%, while the Southwest saw "
    "decreases of 3-7%. Perhaps more notably, precipitation intensity "
    "increased across all regions, with the number of days receiving "
    "more than 50 mm of rainfall increasing by 20% nationally."
)

doc.add_paragraph("")

# Discussion
doc.add_paragraph("Discussion")
doc.add_paragraph(
    "Our findings are broadly consistent with previous regional and "
    "global climate assessments, while providing additional spatial and "
    "temporal detail. The acceleration of warming trends after 1980 aligns "
    "with the conclusions of Hansen et al. (2010), who documented a shift "
    "in the distribution of temperature anomalies beginning in the 1980s. "
    "The asymmetry between minimum and maximum temperature trends, with "
    "nighttime warming outpacing daytime warming, has important "
    "implications for agricultural systems, energy demand, and human health."
)
doc.add_paragraph(
    "The increasing variability in precipitation patterns, particularly "
    "the simultaneous increase in both drought severity and extreme rainfall "
    "events, presents significant challenges for water resource management. "
    "These findings support the conceptual framework proposed by Trenberth "
    "(2011), in which a warmer atmosphere holds more water vapor, leading "
    "to more intense precipitation events even in regions where total "
    "precipitation is declining."
)

doc.add_paragraph("")

# Conclusion
doc.add_paragraph("Conclusion")
doc.add_paragraph(
    "This 70-year analysis of climate variability in the continental United "
    "States reveals significant and accelerating changes in both temperature "
    "and precipitation patterns. The results underscore the need for "
    "region-specific adaptation strategies that account for the heterogeneous "
    "nature of climate change impacts. Future research should focus on "
    "improving the spatial resolution of these analyses and extending them "
    "to include additional climate variables such as humidity, wind speed, "
    "and solar radiation."
)

doc.add_paragraph("")

# References (all real citations)
doc.add_paragraph("References")
doc.add_paragraph(
    "Hamed, K. H., & Rao, A. R. (1998). A modified Mann-Kendall trend test "
    "for autocorrelated data. Journal of Hydrology, 204(1-4), 182-196."
)
doc.add_paragraph(
    "Hansen, J., Ruedy, R., Sato, M., & Lo, K. (2010). Global surface "
    "temperature change. Reviews of Geophysics, 48(4), RG4004."
)
doc.add_paragraph(
    "IPCC. (2021). Climate Change 2021: The Physical Science Basis. "
    "Cambridge University Press."
)
doc.add_paragraph(
    "Karl, T. R., Melillo, J. M., & Peterson, T. C. (2009). Global Climate "
    "Change Impacts in the United States. Cambridge University Press."
)
doc.add_paragraph(
    "Kendall, M. G. (1975). Rank Correlation Methods. Griffin."
)
doc.add_paragraph(
    "Lenssen, N. J., Schmidt, G. A., Hansen, J. E., Menne, M. J., Persin, A., "
    "Ruedy, R., & Zyss, D. (2019). Improvements in the GISTEMP uncertainty "
    "model. Journal of Geophysical Research: Atmospheres, 124(12), 6307-6326."
)
doc.add_paragraph(
    "Mann, H. B. (1945). Nonparametric tests against trend. Econometrica, "
    "13(3), 245-259."
)
doc.add_paragraph(
    "Sen, P. K. (1968). Estimates of the regression coefficient based on "
    "Kendall's tau. Journal of the American Statistical Association, "
    "63(324), 1379-1389."
)
doc.add_paragraph(
    "Trenberth, K. E. (2011). Changes in precipitation with climate change. "
    "Climate Research, 47(1-2), 123-138."
)
doc.add_paragraph(
    "Vose, R. S., Easterling, D. R., Kunkel, K. E., LeGrande, A. N., & "
    "Wehner, M. F. (2017). Temperature changes in the United States. "
    "In Climate Science Special Report (pp. 185-206). U.S. Global Change "
    "Research Program."
)

doc.save("/home/ga/Documents/raw_paper.docx")
print("Created unformatted research paper document")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/raw_paper.docx
sudo chmod 666 /home/ga/Documents/raw_paper.docx

# Launch LibreOffice Writer with the document
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/raw_paper.docx > /tmp/writer_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/writer_task.log
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Writer" 90; then
    wait_for_window "raw_paper" 30 || true
fi

# Click on center of screen to select desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Writer window
echo "Focusing Writer window..."
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        # Dismiss any "What's New" infobar that may appear on first launch
        safe_xdotool ga :1 key Escape
        sleep 0.3
        # Open Styles sidebar
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Move cursor to beginning
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Format Research Paper Task Setup Complete ==="
echo "Instructions:"
echo "  1. Title: center, 16pt, bold"
echo "  2. Authors: center, 12pt, italic"
echo "  3. Section headings (Abstract, Introduction, etc.): Heading 1"
echo "  4. Subsection headings (Data Collection, etc.): Heading 2"
echo "  5. Body text: justified alignment"
echo "  6. References: 0.5-inch hanging indent"
echo "  7. Save (Ctrl+S)"
