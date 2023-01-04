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

## Options
- `location_name`: A name for the location (e.g. Vryburg); only used in the title of the table and defaults to "latitude:longitude".
- `elevations`: Specific sun elevations to be included in the table. Defaults to 20°, 30°, 45°, 60°, and 75°.
- `points_per_day`: Number of data points per day; increase to have more accurate (but slower) results. Defaults to the number of hours per day: 24.
- `save_table`: Set to true to save a csv copy of the table. Defaults to false.

For example, to produce a table for the first 10 days of June in the year 2000 for London, with elevations 5°, 10°, 15°, "London city" in its title, 240 data points per day for higher accuracy, and saved csv copy of the results, we would run:
```julia
main(Date(2000, 6, 1), Date(2000, 6, 10), 51.5085, -0.1257; elevations=[5, 10, 15], location_name="London city", points_per_day=240, save_table=true))
```

## Notes
- The reported azimuth is not the azimuth to the global geographic North but to the local magnetic North. The angle between these two directions is called the magnetic declination angle and is reported to the user when running `main`. The declination angle does not change much within 1 year and 100 km.
- The times are in local time (local to the coordinates you specified).

## Troubleshoot
1. Some of my highest elevations are missing from the table

During winter in the northern hemisphere (and vice versa), the sun might not reach very high elevations. Those null-elevations will therefore be omitted from the resulting table. If the sun does not reach these high elevations in any of the requested days then the columns for those elevations will be entirely omitted from the table. If the sun will not reach those elevations for some, but not all, of the days, then the cells for those days & elevations will be empty.

2. Some mid-elevation cells are empty

If you have empty cells between two non-empty columns then you should increase `points_per_day` from its default value of 24 data points per day (increase to 240 for example). This can occur when the resolution of the interpolation is too low. Increasing its resolution solves these kinds of problems.

3. Times change as a function of the number of days included in the table

These changes are due to rounding errors and are never larger than a minute. If you see larger changes than a minute or two please open an issue. 

4. Moon-events included only one (rise/set) event, not two

It is entirely possible for the moon to rise in one day but set the next day, resulting in a seldom moonrise in one of the days (and vice versa).

5. I tried testing the package first but ran into errors (e.g. `…user provided invalid input 100 times…`)

After you've `add`ed the package, simply start `using` it before `test`ing it. You can `test` the package thereafter if you like. 
