# CSV Import Task

**Difficulty**: 🟢 Easy
**Estimated Steps**: 10
**Timeout**: 120 seconds

## Objective

Import a CSV data file into LibreOffice Calc and format the columns appropriately. This task tests basic file import operations, data formatting, and spreadsheet handling.

## Starting State

- A CSV file (`employees.csv`) is available on the system with employee data
- The CSV contains columns: ID, Name, Department, Salary, Hire Date
- LibreOffice Calc is ready to open the file

## Required Actions

1. Open the CSV file in LibreOffice Calc
2. Verify data imported correctly
3. Format the Salary column as currency (if needed)
4. Format the Date column as dates (if needed)
5. Save the file as an ODS or keep as imported format

## Success Criteria

1. ✅ Data imported correctly (Name "Alice Smith" in B2)
2. ✅ Salary data correct (85000 in D2)
3. ✅ Date data present (2020 date in E2)
4. ✅ All rows present (header + 4 data rows minimum)

**Pass Threshold**: 75% (3 out of 4 criteria)

## Skills Tested

- File opening and import
- CSV format handling
- Data type recognition
- Column formatting
- Save operations

## CSV Data Structure

\`\`\`csv
ID,Name,Department,Salary,Hire Date
1,Alice Smith,Engineering,85000,2020-01-15
2,Bob Jones,Marketing,72000,2019-06-22
3,Charlie Brown,Sales,65000,2021-03-10
4,Diana Prince,Engineering,95000,2018-11-05
\`\`\`

## Tips

- LibreOffice Calc can open CSV files directly via File → Open
- The import dialog may ask about delimiters (use comma)
- Data types are usually detected automatically
- Currency formatting: Format → Cells → Currency
- Date formatting: Format → Cells → Date
