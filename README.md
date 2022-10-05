# SunMoonTables [![Build Status](https://github.com/yakir12/SunMoonTables.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/yakir12/SunMoonTables.jl/actions/workflows/CI.yml?query=branch%3Amain) [![Coverage](https://codecov.io/gh/yakir12/SunMoonTables.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/yakir12/SunMoonTables.jl)

A Julia package that creates tables describing sun and moon events.

## How to use
`main` takes the start-date and end-date of the period you are interested in as well as the latitude and longitude of the location you are interested in, and opens the resulting table with the local web-browser.

For example, to produce a table for the first 10 days of June in the year 2000 for London, run:

```julia
using SunMoonTables
main(Date(2000, 6, 1), Date(2000, 6, 10), 51.5085, -0.1257)
```

## What's in the tables
For each day we have sunrise with time and azimuth, time for each of the (default) elevations: 20°, 30°, 45°, 60°, and 75° beforenoon, time and azimuth at noon (i.e. highest sun-elevation that day), and afternoon, as well as time and azimuth for sunset. 
For the moon we have the time of the moonrise and moonset if it occurs during the night (i.e. between sunset and sunrise), as well as the phase of the moon (in percent).

# Notes
- The times are in local time (local to the coordinates you specified)
- During winter in the northern hemisphere (and vice versa), the sun might not reach very high elevations. Those null-elevations will therefore be omitted from the resulting table.
- To change the default elevations run `main` with the keyword-argument `elevations`. For example, to change the elevations in the example above to 5°, 10°, and 15°, run:
```julia
main(Date(2000, 1, 1), Date(2000, 1, 10), 51.5085, -0.1257; elevations = [5, 10, 15])
```
- It is entirely possible for the moon to rise after sunrise and set past midnight of the same day. The result of which would be no times in the table for both moonrise and moonset for that specific day (but be sure the moon will then set "early" the next day, i.e. a few minutes after midnight of the day "missing" a moonrise and moonset).
- To save a csv file of the resulting table run with `save_table=true`, e.g.: 
```julia
main(Date(2000, 1, 1), Date(2000, 1, 10), 51.5085, -0.1257; save_table=true)
```
