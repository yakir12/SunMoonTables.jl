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
For each day we have sunrise with time and local magnetic azimuth, time for each of the (default) elevations: 20°, 30°, 45°, 60°, and 75° beforenoon, time and elevation at noon (i.e. highest sun-elevation that day), and afternoon, as well as time and local magnetic azimuth for sunset. 
For the moon we have the time of each of the moonrises and moonsets within every 24 hours, as well as the phase of the moon (in percent).

# Options
- `location_name`: A name for the location (e.g. Vryburg); only used in the title of the table and defaults to "latitude:longitude".
- `elevations`: Specific sun elevations to be included in the table. Defaults to 20°, 30°, 45°, 60°, and 75°.
- `points_per_day`: Number of data points per day; increase to have more accurate (but slower) results. Defaults to the number of hours per day: 24.
- `save_table`: Set to true to save a csv copy of the table. Defaults to false.

For example, to produce a table for the first 10 days of June in the year 2000 for London, with elevations 5°, 10°, 15°, "London city" in its title, 240 data points per day for higher accuracy, and saved csv copy of the results, we would run:
```julia
main(Date(2000, 6, 1), Date(2000, 6, 10), 51.5085, -0.1257; elevations=[5, 10, 15], location_name="London city", points_per_day=240, save_table=true))
```

# Notes
- The reported azimuth is not the azimuth to the global geographic North but to the local magnetic North. The angle between these two directions is called the magnetic declination angle and is reported to the user when running `main`. The declination angle does not change much within 1 year and 100 km.
- The times are in local time (local to the coordinates you specified).
- During winter in the northern hemisphere (and vice versa), the sun might not reach very high elevations. Those null-elevations will therefore be omitted from the resulting table.
- It is entirely possible for the moon to rise in one day but set the next day, resulting in a seldom moonrise in one of the days.
