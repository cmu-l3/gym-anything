package com.google.samples.apps.sunflower.data

/**
 * Represents a plant in the garden tracker.
 *
 * @property plantId Unique identifier for the plant
 * @property name Display name of the plant
 * @property description Detailed description of the plant
 * @property growZoneNumber The USDA hardiness grow zone where this plant thrives
 * @property wateringInterval Number of days between watering, defaults to 7
 * @property imageUrl URL for the plant image
 */
data class Plant(
    val plantId: String,
    val name: String,
    val description: String,
    val growZoneNumber: Int,
    val wateringInterval: Int = 7,
    val imageUrl: String = ""
) {
    /**
     * Determines if the plant needs watering based on the last watering date.
     * A plant needs watering if the number of days since the last watering
     * exceeds its watering interval.
     */
    fun shouldBeWatered(daysSinceLastWatering: Int): Boolean {
        return daysSinceLastWatering >= wateringInterval
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
