library(sf)
library(spdep)
sids <- st_read(system.file("shapes/sids.shp", package="spData"), quiet=TRUE)
print("sids:")
print(colnames(sids))

if ("BIR74" %in% colnames(sids)) {
    sids$RATE <- (sids$SID74 / sids$BIR74) * 1000
    nb <- poly2nb(sids)
    lw <- nb2listw(nb)
    print("Moran sids rate:")
    print(moran.test(sids$RATE, lw)$estimate[1])
}
