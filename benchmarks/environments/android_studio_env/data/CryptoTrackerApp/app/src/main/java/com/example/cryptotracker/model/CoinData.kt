package com.example.cryptotracker.model

/**
 * Data model representing a cryptocurrency.
 *
 * After Retrofit integration, a separate response DTO with JSON field name
 * annotations should be created for API deserialization, mapping to this model.
 */
data class CoinData(
    val id: String,
    val name: String,
    val symbol: String,
    val currentPrice: Double,
    val priceChangePercent24h: Double,
    val marketCap: Long,
    val volume24h: Double = 0.0,
    val circulatingSupply: Double = 0.0
) {
    val isPriceUp: Boolean get() = priceChangePercent24h >= 0

    fun formattedPrice(): String = "$${String.format("%,.2f", currentPrice)}"

    fun formattedMarketCap(): String {
        return when {
            marketCap >= 1_000_000_000_000 -> "$${String.format("%.2f", marketCap / 1_000_000_000_000.0)}T"
            marketCap >= 1_000_000_000 -> "$${String.format("%.2f", marketCap / 1_000_000_000.0)}B"
            marketCap >= 1_000_000 -> "$${String.format("%.2f", marketCap / 1_000_000.0)}M"
            else -> "$$marketCap"
        }
    }
}
