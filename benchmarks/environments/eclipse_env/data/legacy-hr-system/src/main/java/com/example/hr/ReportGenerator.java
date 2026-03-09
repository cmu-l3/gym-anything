package com.example.hr;

import com.example.hr.model.Employee;

import java.util.Date;
import java.util.List;
import java.util.ArrayList;
import java.text.SimpleDateFormat;

/**
 * Generates formatted HR reports.
 *
 * LEGACY ISSUES:
 * 1. Uses StringBuffer throughout — should be modernized.
 * 2. Uses java.util.Date and SimpleDateFormat — consider modern date/time alternatives.
 * 3. Returns and accepts raw List types.
 */
public class ReportGenerator {

    /**
     * Generate a headcount report for a list of employees.
     * LEGACY: Accepts raw List, uses StringBuffer, uses Date/SimpleDateFormat.
     */
    public String generateHeadcountReport(List employees, String reportTitle) {
        // LEGACY: StringBuffer
        StringBuffer report = new StringBuffer();
        report.append("=== ").append(reportTitle).append(" ===\n");
        // LEGACY: Date + SimpleDateFormat
        report.append("Generated: ").append(new SimpleDateFormat("yyyy-MM-dd").format(new Date())).append("\n");
        report.append("Total employees: ").append(employees.size()).append("\n\n");

        for (Object obj : employees) {
            Employee emp = (Employee) obj;
            report.append(emp.getFirstName()).append(" ").append(emp.getLastName())
                  .append(" | ").append(emp.getDepartment())
                  .append(" | ").append(emp.getJobTitle()).append("\n");
        }
        return report.toString();
    }

    /**
     * Generate a salary band report grouped by department.
     * LEGACY: Uses StringBuffer, Date, raw List, raw Map.
     */
    public String generateSalaryReport(List employees) {
        StringBuffer report = new StringBuffer();
        report.append("=== Salary Report ===\n");
        report.append("As of: ").append(new SimpleDateFormat("yyyy-MM-dd HH:mm").format(new Date())).append("\n\n");

        double totalPayroll = 0;
        for (Object obj : employees) {
            Employee emp = (Employee) obj;
            report.append(String.format("%-30s %-20s $%,.2f%n",
                emp.getFirstName() + " " + emp.getLastName(),
                emp.getDepartment(),
                emp.getSalary()));
            totalPayroll += emp.getSalary();
        }
        report.append(String.format("%nTotal payroll: $%,.2f%n", totalPayroll));
        return report.toString();
    }

    /**
     * Format a date for display in reports.
     * LEGACY: Uses Date parameter — consider modern date type.
     */
    public String formatDate(Date date) {
        if (date == null) return "N/A";
        return new SimpleDateFormat("dd MMM yyyy").format(date);
    }
}
