module SunMoonTables

using Dates, Statistics, Downloads
using AstroLib, TimeZones, PrettyTables, DataFrames, ApproxFun, Interpolations, TimeZoneFinder, DefaultApplication, CSV, SatelliteToolbox, DataDeps, NCDatasets

export main, Date

const ALTITUDE = Ref{Interpolations.GriddedInterpolation{Float64, 2, Matrix{Union{Missing, Int16}}, Gridded{Linear{Throw{OnGrid}}}, Tuple{Vector{Float64}, Vector{Float64}}}}()

function __init__()
    register(
        DataDep(
            "Earth2014",
            """
            Reference:
            - Hirt, C. and M. Rexer (2015), Earth2014: 1 arc-min shape, topography, bedrock 
            and ice-sheet models — available as gridded data and degree-10,800 spherical 
            harmonics, International Journal of Applied Earth Observation and Geoinformation
            39, 103–112, doi:10.10.1016/j.jag.2015.03.001.
            """,
            "http://ddfe.curtin.edu.au/models/Earth2014/data_1min/GMT/Earth2014.BED2014.1min.geod.grd",
            "c7350f22ccfdc07bc2c751015312eb3d5a97d9e75b1259efff63ee0e6e8d17a5",
            fetch_method = fallback_download
        )
    )
    ALTITUDE[] = NCDataset(datadep"Earth2014/Earth2014.BED2014.1min.geod.grd") do ds
        interpolate((ds["x"][:], ds["y"][:]), ds["z"][:, :], Gridded(Linear()))
    end
end

function fallback_download(remotepath, localdir)
    @assert(isdir(localdir))
    filename = basename(remotepath)  # only works for URLs with filename as last part of name
    localpath = joinpath(localdir, filename)
    downloader = Downloads.Downloader()
    downloader.easy_hook = (easy, info) -> Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_LOW_SPEED_TIME, 60)
    Downloads.download(remotepath, localpath; downloader=downloader)
    return localpath
end

get_altitude(latitude, longitude) = ALTITUDE[](longitude, latitude)

function sun_alt_az(julian_dates, latitude, longitude, altitude)
    right_ascension, declination = sunpos(julian_dates)
    α, γ, _ = eq2hor(right_ascension, declination, julian_dates, latitude, longitude, altitude)
    return (; α, γ)
end

sun_α(julian_dates, latitude, longitude, altitude) = sun_alt_az(julian_dates, latitude, longitude, altitude).α

function moon_α(julian_dates, latitude, longitude, altitude)
    right_ascension, declination = moonpos(julian_dates)
    α, γ, _  = eq2hor(right_ascension, declination, julian_dates, latitude, longitude, altitude)
    return α
end

function get_sun_moon(jd1, jd2, latitude, longitude, altitude, points_per_day)
    ndays = round(Int, jd2 - jd1)
    S = Chebyshev(jd1..jd2)
    p = points(S, points_per_day*ndays)
    v = sun_α.(p, latitude, longitude, altitude)
    sun = Fun(S, ApproxFun.transform(S, v))

    v = moon_α.(p, latitude, longitude, altitude)
    moon = Fun(S, ApproxFun.transform(S, v))
    return sun, moon
end

julian2dt(jd, tz) = DateTime(astimezone(TimeZones.julian2zdt(jd), tz))

function magnetic_declination(year, latitude, longitude, altitude)
    mfv = igrfd(year, altitude, latitude, longitude, Val(:geodetic))
    return atand(mfv[2], mfv[1])
end

decimaldate(dtm) = year(dtm) + (dayofyear(dtm) - 1) / daysinyear(dtm)

function sun_jd2row(jd, latitude, longitude, altitude, tz, dsun, md)
    el, az = sun_alt_az(jd, latitude, longitude, altitude)
    elevation = abs(el) < 1 ? 0 : round(Int, el)
    dt = round(julian2dt(jd, tz), Minute(1))
    date = Date(dt)
    time = Dates.format(Time(dt), "HH:MM")
    γ = round(Int, az + md)
    sl = dsun(jd)
    variable = abs(sl) < 0.01 ? "Noon" : sl > 0 ? "↑$(elevation)°" : "↓$(elevation)°"
    value = variable == "Noon" ? join([time, string(elevation, "°")], " ") : elevation == 0 ? join([time, string(γ, "°")], " ") : time
    (; Date = date, variable, value, elevation)
end

function get_sun_tbl(sun, elevations_set, latitude, longitude, altitude, tz, md)
    dsun = sun'
    jd = roots(dsun)
    push!(elevations_set, 0)
    filter!(x -> 0 ≤ x ≤ 90, elevations_set)
    elevations = sort(collect(elevations_set))
    jd = mapreduce(e -> roots(sun - e), vcat, elevations, init = jd)
    df = DataFrame(sun_jd2row.(jd, latitude, longitude, altitude, tz, dsun, md))
    subset!(df, :elevation => ByRow(≥(0)))
    sun_tbl = unstack(df, :Date, :variable, :value; combine=last)
    cols = filter(∈(unique(subset(df, :variable => ByRow(≠("Noon"))).elevation)), elevations)
    select!(sun_tbl, ["Date", string.("↑", cols, "°")..., "Noon", string.("↓", reverse(cols), "°")...])
    rename!(sun_tbl, "↑0°" => "Sunrise", "↓0°" => "Sunset")
end

function moon_jd2row(jd, tz, dmoon)
    dt = round(julian2dt(jd, tz), Minute(1))
    date = Date(dt)
    time = Dates.format(Time(dt), "HH:MM")
    direction = dmoon(jd) > 0 ? "↑" : "↓"
    event = string(direction, " ", time)
    (; jd, Date = date, event)
end

function get_moon_tbl(moon, sun, tz, jd1, jd2)
    jd = roots(moon)
    # filter!(jd -> sun(jd) < 0, jd)
    df1 = DataFrame(moon_jd2row.(jd, tz, moon'))
    df2 = combine(groupby(df1, :Date), :event => (xs -> join(xs, ", ")) => "Moon events", :jd => mean => :jd)
    DataFrames.transform!(df2, :jd => ByRow(jd -> string.(round.(Int, 100mphase.(jd .+ 0.5)), "%")) => :Phase)
    select!(df2, Not(:jd))
    return df2
end

function sunmoon(start_datetime, end_datetime, latitude, longitude, altitude, tz, elevations_set, points_per_day, md)
    jd1 = TimeZones.zdt2julian(ZonedDateTime(start_datetime, tz))
    jd2 = TimeZones.zdt2julian(ZonedDateTime(end_datetime, tz))

    sun, moon = get_sun_moon(jd1, jd2, latitude, longitude, altitude, points_per_day)

    sun_tbl = get_sun_tbl(sun, elevations_set, latitude, longitude, altitude, tz, md)
    moon_tbl = get_moon_tbl(moon, sun, tz, jd1, jd2)

    tbl = outerjoin(sun_tbl, moon_tbl, on = :Date)
    sort!(tbl, :Date)
    tbl.Date = string.(tbl.Date)
    return tbl
end

function get_table(start_date, end_date, latitude, longitude, elevations, points_per_day)
    altitude = get_altitude(latitude, longitude)
    tz = timezone_at(latitude, longitude)
    md = magnetic_declination(decimaldate(start_date), latitude, longitude, altitude)
    @info "the magnetic declination angle is $(round(md; digits=2))°"
    start_datetime = DateTime(start_date, Time(0, 0, 0))
    end_datetime = DateTime(end_date, Time(23, 59, 59))
    elevations_set = Set(elevations)
    return sunmoon(start_datetime, end_datetime, latitude, longitude, altitude, tz, elevations_set, points_per_day, md)
end

function main(start_date, end_date, latitude, longitude; location_name="$latitude:$longitude", elevations=[20, 30, 45, 60, 75], points_per_day=24, save_table=false)
    @assert end_date ≥ start_date "ending date must be equal or later than starting date"
    @assert -90 ≤ latitude ≤ 90 "latitude must be between -90 and 90"
    @assert -180 ≤ latitude ≤ 180 "longitude must be between -180 and 180"
    df = get_table(start_date, end_date, latitude, longitude, elevations, points_per_day)
    save_table && CSV.write("table.csv", df)
    file = print2html(df, start_date, end_date, location_name)
    DefaultApplication.open(file)
end

function print2html(df, start_date, end_date, location_name)
    file = tempname() * ".html"
    tf = PrettyTables.HtmlTableFormat(css = PrettyTables.tf_html_simple.css * """
                                      td, th {
                                      border: 2px solid black;
                                      border-left: 2px solid black;
                                      border-right: 2px solid black;
                                      }
                                      caption {
                                      font-size: 20px; 
                                      font-weight: bold;
                                      }""")
    open(file, "w") do io
        pretty_table(io, df; backend=Val(:html), tf=tf, show_subheader = false, formatters = ft_nomissing, standalone=true, highlighters=hl_row(1:2:nrow(df), HtmlDecoration(background = "light_gray",)), show_row_number=false, title="$start_date - $end_date @ $location_name", title_alignment=:c)
    end
    return file
end

end
