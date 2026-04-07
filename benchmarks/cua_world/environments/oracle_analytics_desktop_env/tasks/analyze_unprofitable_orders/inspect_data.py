import pandas as pd
import sys

csv_file = '/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/oracle_analytics_desktop_env/data/order_lines.csv'
df_csv = pd.read_csv(csv_file, nrows=5)
print("CSV Columns:", df_csv.columns.tolist())

excel_file = '/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/oracle_analytics_desktop_env/data/sample_order_lines2023.xlsx'
xls = pd.ExcelFile(excel_file)
print("Excel Sheets:", xls.sheet_names)
for sheet in xls.sheet_names:
    df_xl = pd.read_excel(excel_file, sheet_name=sheet, nrows=5)
    print(f"Sheet {sheet} columns:", df_xl.columns.tolist())

    if 'Region' in df_xl.columns and 'Profit' in df_xl.columns:
        df_full = pd.read_excel(excel_file, sheet_name=sheet)
        loss_df = df_full.copy()
        loss_df['Loss'] = loss_df['Profit'] < 0
        grouped = loss_df.groupby('Region')['Loss'].agg(['sum', 'count'])
        grouped['Loss Rate'] = grouped['sum'] / grouped['count']
        print(f"--- {sheet} Loss Rate by Region ---")
        print(grouped)
        print(f"Min Loss Rate: {grouped['Loss Rate'].min()}")
        print(f"Max Loss Rate: {grouped['Loss Rate'].max()}")

