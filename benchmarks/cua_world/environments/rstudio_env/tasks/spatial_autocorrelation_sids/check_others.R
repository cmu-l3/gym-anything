library(sf)
library(spdep)
nc <- st_read(system.file("shape/nc.shp", package="sf"), quiet=TRUE)
RATE <- (nc$SID74 / nc$BIR74) * 1000
nb <- poly2nb(nc)
lw <- nb2listw(nb)
print("Geary:")
g <- geary.test(RATE, lw)
print(g$estimate[1])

print("Lag cor:")
print(cor(RATE, lag.listw(lw, RATE)))
