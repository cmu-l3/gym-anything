package com.example.hr;

import com.example.hr.model.Employee;
import com.example.hr.model.Department;

import java.util.Date;
import java.util.Calendar;

public class HrApplication {

    public static void main(String[] args) {
        EmployeeDirectory directory = new EmployeeDirectory();
        PayrollCalculator payroll = new PayrollCalculator();
        ReportGenerator reportGen = new ReportGenerator();

        // Create departments
        directory.addDepartment(new Department(0, "Engineering", "CC-001", 0));
        directory.addDepartment(new Department(0, "Finance", "CC-002", 0));

        // Create employees with legacy Date API
        Calendar cal = Calendar.getInstance();
        cal.set(2015, Calendar.MARCH, 10);
        Date hireDate = cal.getTime();
        cal.set(1985, Calendar.JUNE, 20);
        Date dob = cal.getTime();

        Employee emp = new Employee(0, "Jane", "Doe", "jane.doe@example.com",
            "Engineering", "Senior Engineer", hireDate, dob, 95000.0);
        directory.addEmployee(emp);

        System.out.println("HR System loaded. Employees: " + directory.getEmployeeCount());
    }
}
