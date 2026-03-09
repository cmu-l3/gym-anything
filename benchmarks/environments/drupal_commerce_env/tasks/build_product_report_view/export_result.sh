# Check if view exists
drush config:get views.view.product_summary_report

# Export view config as YAML for parsing
drush config:get views.view.product_summary_report --format=yaml

# Quick check: list all views
drush views:list