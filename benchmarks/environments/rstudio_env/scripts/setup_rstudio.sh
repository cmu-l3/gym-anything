#!/bin/bash
set -e

echo "=== Setting up RStudio environment ==="

# Wait for desktop to be ready
sleep 5

# Create RStudio configuration directory
mkdir -p /home/ga/.config/rstudio
mkdir -p /home/ga/.local/share/rstudio
mkdir -p /home/ga/RProjects
mkdir -p /home/ga/R/library

# Copy RStudio preferences if available
if [ -f /workspace/config/rstudio-prefs.json ]; then
    cp /workspace/config/rstudio-prefs.json /home/ga/.config/rstudio/rstudio-prefs.json
else
    # Create default RStudio preferences
    cat > /home/ga/.config/rstudio/rstudio-prefs.json << 'EOF'
{
    "auto_save_on_idle": "commit",
    "initial_working_directory": "~/RProjects",
    "save_workspace": "never",
    "load_workspace": false,
    "always_save_history": true,
    "remove_history_duplicates": true,
    "show_line_numbers": true,
    "highlight_selected_line": true,
    "show_margin": true,
    "margin_column": 80,
    "soft_wrap_r_files": false,
    "syntax_color_console": true,
    "show_invisibles": false,
    "editor_keybindings": "default",
    "font_size_points": 12,
    "tab_size": 2,
    "insert_spaces": true,
    "auto_append_newline": true,
    "strip_trailing_whitespace": true,
    "check_for_updates": false,
    "submit_crash_reports": false,
    "send_usage_stats": false
}
EOF
fi

# Create a welcome R script in the projects folder
cat > /home/ga/RProjects/welcome.R << 'EOF'
# Welcome to RStudio!
# This is your workspace for data analysis with R

# Load common libraries
library(tidyverse)

# Check R version
print(R.version.string)

# List available datasets
print("Available built-in datasets:")
print(head(data()$results[, "Item"], 20))

# Quick demonstration with mtcars
print("Quick summary of mtcars dataset:")
summary(mtcars)

# Simple plot
ggplot(mtcars, aes(x = wt, y = mpg)) +
  geom_point() +
  labs(title = "MPG vs Weight", x = "Weight (1000 lbs)", y = "Miles per Gallon") +
  theme_minimal()
EOF

# Download real datasets for tasks
echo "Downloading real datasets..."

# Create datasets directory
mkdir -p /home/ga/RProjects/datasets

# Download Gapminder dataset (real world development indicators)
if [ ! -f /home/ga/RProjects/datasets/gapminder.csv ]; then
    echo "Downloading Gapminder dataset..."
    wget -q -O /home/ga/RProjects/datasets/gapminder.csv \
        "https://raw.githubusercontent.com/jennybc/gapminder/main/data-raw/gapminder.tsv" 2>/dev/null || \
    wget -q -O /home/ga/RProjects/datasets/gapminder.csv \
        "https://raw.githubusercontent.com/plotly/datasets/master/gapminderDataFiveYear.csv" 2>/dev/null || \
    echo "Could not download Gapminder dataset"
fi

# Download Palmer Penguins dataset (real penguin measurements)
if [ ! -f /home/ga/RProjects/datasets/penguins.csv ]; then
    echo "Downloading Palmer Penguins dataset..."
    wget -q -O /home/ga/RProjects/datasets/penguins.csv \
        "https://raw.githubusercontent.com/allisonhorst/palmerpenguins/main/inst/extdata/penguins.csv" 2>/dev/null || \
    echo "Could not download Palmer Penguins dataset"
fi

# Download NYC Flights dataset sample (real flight data)
if [ ! -f /home/ga/RProjects/datasets/flights_sample.csv ]; then
    echo "Downloading NYC Flights sample..."
    wget -q -O /home/ga/RProjects/datasets/flights_sample.csv \
        "https://raw.githubusercontent.com/tidyverse/nycflights13/main/data-raw/flights.csv" 2>/dev/null || \
    echo "Could not download NYC Flights dataset"
fi

# Set proper ownership
chown -R ga:ga /home/ga/.config
chown -R ga:ga /home/ga/.local
chown -R ga:ga /home/ga/RProjects
chown -R ga:ga /home/ga/R

# Create desktop launcher
cat > /home/ga/Desktop/launch_rstudio.sh << 'EOF'
#!/bin/bash
export DISPLAY=:1
export R_LIBS_USER=/home/ga/R/library
cd /home/ga/RProjects
rstudio &
EOF
chmod +x /home/ga/Desktop/launch_rstudio.sh
chown ga:ga /home/ga/Desktop/launch_rstudio.sh

# Create desktop shortcut
cat > /home/ga/Desktop/RStudio.desktop << 'EOF'
[Desktop Entry]
Name=RStudio
Comment=RStudio IDE for R
Exec=/usr/bin/rstudio
Icon=rstudio
Terminal=false
Type=Application
Categories=Development;IDE;
EOF
chmod +x /home/ga/Desktop/RStudio.desktop
chown ga:ga /home/ga/Desktop/RStudio.desktop

# Trust the desktop file (GNOME)
dbus-launch gio set /home/ga/Desktop/RStudio.desktop metadata::trusted true 2>/dev/null || true

# Configure RStudio to not show crash reporting dialog
mkdir -p /home/ga/.config/rstudio
# Write complete JSON file (don't append to avoid invalid JSON)
cat > /home/ga/.config/rstudio/rstudio-prefs.json << 'EOF_PREFS'
{
    "submit_crash_reports": false,
    "check_for_updates": false,
    "send_usage_stats": false,
    "show_rmd_render_command": false,
    "rmd_viewer_type": "pane"
}
EOF_PREFS
chown -R ga:ga /home/ga/.config/rstudio

# Launch RStudio
echo "Launching RStudio..."
su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/welcome.R &"

# Wait for RStudio to start
sleep 10

# Dismiss any startup dialogs by pressing Escape
DISPLAY=:1 xdotool key Escape
sleep 1
DISPLAY=:1 xdotool key Escape

# Maximize RStudio window
RSTUDIO_WID=$(DISPLAY=:1 wmctrl -l | grep -i "rstudio\|RStudio" | head -1 | awk '{print $1}')
if [ -n "$RSTUDIO_WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$RSTUDIO_WID" -b add,maximized_vert,maximized_horz
    echo "RStudio window maximized"
fi

echo "=== RStudio setup complete ==="
