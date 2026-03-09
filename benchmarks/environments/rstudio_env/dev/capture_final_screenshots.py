#!/usr/bin/env python3
"""Capture final output screenshots showing completed RStudio tasks."""

import sys
import os
import time
import json

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))) + '/..')

from gym_anything.api import from_config

EVIDENCE_DIR = 'benchmarks/environments/rstudio_env/evidence'


def save_screenshot(env, filename):
    """Save screenshot from environment."""
    filepath = os.path.join(EVIDENCE_DIR, filename)
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    if env._runner.capture_screenshot(filepath):
        print(f"Screenshot saved: {filepath}")
        return filepath
    else:
        print(f"Failed to capture screenshot: {filepath}")
        return None


def capture_scatter_plot_output():
    """Capture screenshot after creating scatter plot."""
    env_path = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'rstudio_env')

    print("=== Capturing Scatter Plot Output ===")
    env = from_config(env_path, task_id="create_scatter_plot")

    try:
        # Reset the environment
        obs = env.reset(seed=42, use_cache=False)
        print("Environment reset with create_scatter_plot task")
        time.sleep(3)

        # Save initial screenshot
        save_screenshot(env, "scatter_01_initial_template.png")

        # Write complete R code
        r_code = '''# Scatter Plot Analysis
library(ggplot2)

# Load the penguins dataset
penguins <- read.csv("/home/ga/RProjects/datasets/penguins.csv")

# Create scatter plot of flipper length vs body mass
p <- ggplot(penguins, aes(x = flipper_length_mm, y = body_mass_g, color = species)) +
  geom_point(size = 3, alpha = 0.7) +
  labs(
    title = "Penguin Flipper Length vs Body Mass",
    x = "Flipper Length (mm)",
    y = "Body Mass (g)",
    color = "Species"
  ) +
  theme_minimal()

# Save the plot
ggsave("/home/ga/RProjects/output/penguin_scatter.png", p, width = 8, height = 6, dpi = 150)
print("Plot saved successfully!")
'''

        # Write R code to file using a safer approach
        env._runner.exec_capture("rm -f /tmp/analysis_code.R")

        # Write line by line to avoid shell escaping issues
        for line in r_code.split('\n'):
            # Escape single quotes and special characters
            escaped_line = line.replace("'", "'\\''")
            env._runner.exec_capture(f"echo '{escaped_line}' >> /tmp/analysis_code.R")

        env._runner.exec_capture("cp /tmp/analysis_code.R /home/ga/RProjects/analysis.R")
        env._runner.exec_capture("chown ga:ga /home/ga/RProjects/analysis.R")

        # Verify the script was written
        script_content = env._runner.exec_capture("cat /home/ga/RProjects/analysis.R")
        print(f"Script content written:\n{script_content[:500]}...")

        # Execute R script
        print("\nExecuting R script...")
        result = env._runner.exec_capture("su - ga -c 'Rscript /home/ga/RProjects/analysis.R' 2>&1")
        print(f"R output:\n{result}")
        time.sleep(2)

        # Check if output was created
        check_result = env._runner.exec_capture("ls -la /home/ga/RProjects/output/")
        print(f"\nOutput directory:\n{check_result}")

        # Check file info
        file_info = env._runner.exec_capture("file /home/ga/RProjects/output/penguin_scatter.png 2>&1")
        print(f"File info: {file_info}")

        # Take screenshot
        save_screenshot(env, "scatter_02_completed.png")

        # Copy the generated plot to evidence
        plot_evidence_path = os.path.join(EVIDENCE_DIR, "penguin_scatter_generated.png")
        try:
            env._runner.copy_from("/home/ga/RProjects/output/penguin_scatter.png", plot_evidence_path)
            print(f"Generated plot copied to: {plot_evidence_path}")
        except Exception as e:
            print(f"Could not copy plot: {e}")

        print("=== Scatter Plot Capture Complete ===\n")

    finally:
        env.close()


def capture_summary_output():
    """Capture screenshot after creating dataset summary."""
    env_path = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'rstudio_env')

    print("=== Capturing Summary Dataset Output ===")
    env = from_config(env_path, task_id="summarize_dataset")

    try:
        # Reset the environment
        obs = env.reset(seed=42, use_cache=False)
        print("Environment reset with summarize_dataset task")
        time.sleep(3)

        # Save initial screenshot
        save_screenshot(env, "summary_01_initial_template.png")

        # Write complete R code
        r_code = '''# Dataset Summary Analysis
library(dplyr)

# Load the penguins dataset
penguins <- read.csv("/home/ga/RProjects/datasets/penguins.csv")

# Create summary by species
summary_stats <- penguins %>%
  group_by(species) %>%
  summarize(
    mean_mass = mean(body_mass_g, na.rm = TRUE),
    sd_mass = sd(body_mass_g, na.rm = TRUE)
  )

# Display summary
print(summary_stats)

# Save to CSV
write.csv(summary_stats, "/home/ga/RProjects/output/species_summary.csv", row.names = FALSE)
print("Summary saved successfully!")
'''

        # Write R code to file
        env._runner.exec_capture("rm -f /tmp/summary_code.R")

        for line in r_code.split('\n'):
            escaped_line = line.replace("'", "'\\''")
            env._runner.exec_capture(f"echo '{escaped_line}' >> /tmp/summary_code.R")

        env._runner.exec_capture("cp /tmp/summary_code.R /home/ga/RProjects/summary_analysis.R")
        env._runner.exec_capture("chown ga:ga /home/ga/RProjects/summary_analysis.R")

        # Verify the script was written
        script_content = env._runner.exec_capture("cat /home/ga/RProjects/summary_analysis.R")
        print(f"Script content written:\n{script_content[:500]}...")

        # Execute R script
        print("\nExecuting R script...")
        result = env._runner.exec_capture("su - ga -c 'Rscript /home/ga/RProjects/summary_analysis.R' 2>&1")
        print(f"R output:\n{result}")
        time.sleep(2)

        # Check output
        check_result = env._runner.exec_capture("cat /home/ga/RProjects/output/species_summary.csv 2>&1")
        print(f"\nGenerated CSV:\n{check_result}")

        # Take screenshot
        save_screenshot(env, "summary_02_completed.png")

        # Copy the generated CSV to evidence
        csv_evidence_path = os.path.join(EVIDENCE_DIR, "species_summary_generated.csv")
        try:
            env._runner.copy_from("/home/ga/RProjects/output/species_summary.csv", csv_evidence_path)
            print(f"Generated CSV copied to: {csv_evidence_path}")
        except Exception as e:
            print(f"Could not copy CSV: {e}")

        print("=== Summary Capture Complete ===\n")

    finally:
        env.close()


if __name__ == "__main__":
    os.chdir(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))

    # Check which task to run
    if len(sys.argv) > 1:
        if sys.argv[1] == "scatter":
            capture_scatter_plot_output()
        elif sys.argv[1] == "summary":
            capture_summary_output()
        else:
            print(f"Unknown task: {sys.argv[1]}")
            print("Usage: python capture_final_screenshots.py [scatter|summary|all]")
    else:
        # Run both
        capture_scatter_plot_output()
        capture_summary_output()
