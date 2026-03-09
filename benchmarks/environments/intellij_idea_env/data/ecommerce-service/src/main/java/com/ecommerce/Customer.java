package com.ecommerce;

/**
 * Represents a registered customer of the online retail platform.
 */
public class Customer {

    private final String customerId;
    private final String fullName;
    private final String email;
    private final boolean isPremiumMember;

    public Customer(String customerId, String fullName, String email, boolean isPremiumMember) {
        this.customerId = customerId;
        this.fullName = fullName;
        this.email = email;
        this.isPremiumMember = isPremiumMember;
    }

    public String getCustomerId()   { return customerId; }
    public String getFullName()     { return fullName; }
    public String getEmail()        { return email; }
    public boolean isPremiumMember(){ return isPremiumMember; }

    @Override
    public String toString() {
        return String.format("Customer{id='%s', name='%s', premium=%b}", customerId, fullName, isPremiumMember);
    }
}
