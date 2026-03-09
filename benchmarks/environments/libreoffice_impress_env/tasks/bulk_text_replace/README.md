# Bulk Text Replace Task

**Difficulty**: 🔴 Medium-Hard  
**Skills**: Find/replace, bulk editing  
**Duration**: 120 seconds  
**Steps**: ~20

## Objective

Use Find & Replace (Ctrl+H) to change all instances of "Company" to "Organization" across all slides.

## Verification Criteria

1. ✅ **Old Text Removed**: "Company" no longer present
2. ✅ **New Text Present**: "Organization" appears at least 2 times

**Pass Threshold**: 75%
```

---

## Validation Instructions

To validate and run the LibreOffice Impress environment:

```bash
# Validate the entire environment
python -m gym_anything.cli validate libreoffice_impress_env

# Validate a specific task
python -m gym_anything.cli validate libreoffice_impress_env --task create_basic_presentation

# Run a task
python -m gym_anything.cli run libreoffice_impress_env --task create_basic_presentation --steps 50

# Run all tasks
python -m gym_anything.cli run libreoffice_impress_env --all-tasks
