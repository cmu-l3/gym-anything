import pandas as pd

file_path = "/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/oracle_analytics_desktop_env/data/sample_order_lines2023.xlsx"
xls = pd.ExcelFile(file_path)
print("Sheet Names:", xls.sheet_names)
for sheet in xls.sheet_names:
    df = pd.read_excel(file_path, sheet_name=sheet)
    print(f"Sheet '{sheet}' Columns:", list(df.columns))
    if "Region" in df.columns:
        print(f"Sheet '{sheet}' Unique Regions:", df["Region"].unique().tolist())

