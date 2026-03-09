package com.example.hr;

import com.example.hr.model.Employee;

import java.util.Calendar;
import java.util.Date;
import java.util.List;
import java.util.ArrayList;

/**
 * Computes payroll-related values for employees.
 *
 * LEGACY ISSUE 1: Uses java.util.Calendar for date arithmetic.
 * Calendar is error-prone (0-based months!) and verbose.
 * Consider migrating to modern java.time date/time classes.
 *
 * LEGACY ISSUE 2: Uses raw type List (no generic parameter).
 * All collections should use proper generic type parameters.
 */
public class PayrollCalculator {

    /**
     * Calculate years of service for an employee.
     * LEGACY: Uses Calendar for date arithmetic — consider modern alternatives.
     */
    public int calculateYearsOfService(Employee employee) {
        Date hireDate = employee.getHireDate();
        if (hireDate == null) return 0;

        Calendar hireCal = Calendar.getInstance();
        hireCal.setTime(hireDate);

        Calendar now = Calendar.getInstance();

        int years = now.get(Calendar.YEAR) - hireCal.get(Calendar.YEAR);
        if (now.get(Calendar.DAY_OF_YEAR) < hireCal.get(Calendar.DAY_OF_YEAR)) {
            years--;
        }
        return Math.max(0, years);
    }

    /**
     * Calculate employee age in years.
     * LEGACY: Uses Calendar for age calculation — consider modern alternatives.
     */
    public int calculateAge(Employee employee) {
        Date dob = employee.getDateOfBirth();
        if (dob == null) return 0;

        Calendar dobCal = Calendar.getInstance();
        dobCal.setTime(dob);

        Calendar now = Calendar.getInstance();

        int age = now.get(Calendar.YEAR) - dobCal.get(Calendar.YEAR);
        if (now.get(Calendar.MONTH) < dobCal.get(Calendar.MONTH) ||
            (now.get(Calendar.MONTH) == dobCal.get(Calendar.MONTH) &&
             now.get(Calendar.DAY_OF_MONTH) < dobCal.get(Calendar.DAY_OF_MONTH))) {
            age--;
        }
        return Math.max(0, age);
    }

    /**
     * Calculate monthly gross salary.
     */
    public double calculateMonthlyGross(Employee employee) {
        return employee.getSalary() / 12.0;
    }

    /**
     * Calculate annual bonus based on years of service.
     * LEGACY: Returns raw unparameterized List type
     */
    public List getAnnualBonusHistory(Employee employee, int years) {
        // BUG: raw type List
        List bonuses = new ArrayList();
        double baseSalary = employee.getSalary();
        for (int i = 0; i < years; i++) {
            double rate = 0.05 + (i * 0.01);
            bonuses.add(baseSalary * rate);
        }
        return bonuses;
    }

    /**
     * Get employees eligible for long-service award (>= 10 years).
     * LEGACY: Returns raw List and takes raw List parameter.
     */
    public List getLongServiceEmployees(List employees) {
        List result = new ArrayList();
        for (Object obj : employees) {
            Employee emp = (Employee) obj;
            if (calculateYearsOfService(emp) >= 10) {
                result.add(emp);
            }
        }
        return result;
    }
}
