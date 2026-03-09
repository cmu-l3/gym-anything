package com.google.samples.apps.sunflower.data

/**
 * Represents a plant in the garden tracker.
 */
data class Plant(
    val plantId: String,
    val name: String,
    val description: String,
    val growZoneNumber: String,
    val wateringInterval: Int = 7,
    val imageUrl: String = ""
) {
    /**
     * Determines if the plant needs watering based on the last watering date.
     */
    fun shouldBeWatered(daysSinceLastWatering: Int): Boolean {
        return daysSinceLastWatering >= wateringInterval
    }

    /**
     * Returns plants in the given grow zone.
     */
    fun isInGrowZone(zone: Int): Boolean {
        return growZoneNumber == zone
    }

    /**
     * Returns a human-readable watering schedule string.
     */
    fun getWateringSchedule(): String {
        return when {
            wateringInterval == 1 -> "Water daily"
            wateringInterval <= 3 -> "Water every $wateringInterval days"
            wateringInterval <= 7 -> "Water weekly"
            else -> "Water every $wateringInterval days"
        }
    }

    override fun toString(): String {
        return "Plant(name='$name', zone=$growZoneNumber, water=$wateringInterval days)"
    }
}
