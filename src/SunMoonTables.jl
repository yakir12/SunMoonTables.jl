module SunMoonTables

using Dates, AstroLib, TimeZones, PrettyTables, DataFrames, ApproxFun, Earth2014, Interpolations, TimeZoneFinder, DefaultApplication, CSV, Statistics

export main, Date

function elevation_timezone(latitude, longitude)
    x, y, z = Earth2014.load(; hide_citation=true)
    world = linear_interpolation((y, x), z)
    elevation = world(latitude, longitude)
    tz_str = timezone_at(latitude, longitude) # does not exist!
    elevation, tz_str
end

function sun_alt_az(julian_dates, latitude, longitude, elevation)
    right_ascension, declination = sunpos(julian_dates)
    altitude, azimuth, _ = eq2hor(right_ascension, declination, julian_dates, latitude, longitude, elevation)
    return (; altitude, azimuth)
end

sun_altitude(julian_dates, latitude, longitude, elevation) = sun_alt_az(julian_dates, latitude, longitude, elevation).altitude

function moon_altitude(julian_dates, latitude, longitude, elevation)
    right_ascension, declination = moonpos(julian_dates)
    altitude, azimuth, _  = eq2hor(right_ascension, declination, julian_dates, latitude, longitude, elevation)
    return altitude
end

function get_sun_moon(jd1, jd2, latitude, longitude, elevation, points_per_day)
    ndays = round(Int, jd2 - jd1)
    S = Chebyshev(jd1..jd2)
    p = points(S, points_per_day*ndays)
    v = sun_altitude.(p, latitude, longitude, elevation)
    sun = Fun(S, ApproxFun.transform(S, v))

    v = moon_altitude.(p, latitude, longitude, elevation)
    moon = Fun(S, ApproxFun.transform(S, v))
    return sun, moon
end

julian2dt(jd, tz) = DateTime(astimezone(TimeZones.julian2zdt(jd), tz))

function sun_jd2row(jd, latitude, longitude, elevation, tz, dsun)
    el, az = sun_alt_az(jd, latitude, longitude, elevation)
    elevation = abs(el) < 1 ? 0 : round(Int, el)
    azimuth = round(Int, az)
    dt = round(julian2dt(jd, tz), Minute(1))
    date = Date(dt)
    time = Dates.format(Time(dt), "HH:MM")
    sl = dsun(jd)
    variable = abs(sl) < 0.01 ? "Noon" : sl > 0 ? "↑$(elevation)°" : "↓$(elevation)°"
    value = variable == "Noon" ? join([time, string(elevation, "°")], " ") : elevation == 0 ? join([time, string(azimuth, "°")], " ") : time
    (; Date = date, variable, value, elevation)
end

function get_sun_tbl(sun, elevations_set, latitude, longitude, elevation, tz)
    dsun = sun'
    jd = roots(dsun)
    # elevations = copy(elevations)
    push!(elevations_set, 0)
    filter!(x -> 0 ≤ x ≤ 90, elevations_set)
    elevations = sort(collect(elevations_set))
    jd = mapreduce(e -> roots(sun - e), vcat, elevations, init = jd)
    df = DataFrame(sun_jd2row.(jd, latitude, longitude, elevation, tz, dsun))
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

function sunmoon(start_datetime, end_datetime, latitude, longitude, elevation, tz, elevations_set, points_per_day)
    jd1 = TimeZones.zdt2julian(ZonedDateTime(start_datetime, tz))
    jd2 = TimeZones.zdt2julian(ZonedDateTime(end_datetime, tz))

    sun, moon = get_sun_moon(jd1, jd2, latitude, longitude, elevation, points_per_day)

    sun_tbl = get_sun_tbl(sun, elevations_set, latitude, longitude, elevation, tz)
    moon_tbl = get_moon_tbl(moon, sun, tz, jd1, jd2)

    tbl = outerjoin(sun_tbl, moon_tbl, on = :Date)
    sort!(tbl, :Date)
    tbl.Date = string.(tbl.Date)
    return tbl
end

function get_table(start_date, end_date, latitude, longitude, elevations, points_per_day)
    elevation, tz = elevation_timezone(latitude, longitude)
    start_datetime = DateTime(start_date, Time(0, 0, 0))
    end_datetime = DateTime(end_date, Time(23, 59, 59))
    elevations_set = Set(elevations)
    return sunmoon(start_datetime, end_datetime, latitude, longitude, elevation, tz, elevations_set, points_per_day)
end

function main(start_date, end_date, latitude, longitude; location_name = "$latitude:$longitude", elevations=[20, 30, 45, 60, 75], points_per_day=24, save_table=false)
    @assert end_date ≥ start_date "ending date must be equal or later than starting date"
    @assert -90 ≤ latitude ≤ 90 "latitude must be between -90 and 90"
    @assert -180 ≤ latitude ≤ 180 "longitude must be between -180 and 180"
    df = get_table(start_date, end_date, latitude, longitude, elevations, points_per_day)
    save_table && CSV.write("table.csv", df)
    print2html(df, start_date, end_date, location_name)
end

function print2html(df, start_date, end_date, location_name)
    file, io = mktemp(; cleanup=false)
    tf = PrettyTables.HTMLTableFormat(css = PrettyTables.tf_html_simple.css * """
                                      td, th {
                                      border: 2px solid black;
                                      border-left: 2px solid black;
                                      border-right: 2px solid black;
                                      }
                                      caption {
                                      font-size: 20px; 
                                      font-weight: bold;
                                      }""")
    pretty_table(io, df; backend=Val(:html), tf=tf, nosubheader = true, formatters = ft_nomissing, standalone=true, highlighters=hl_row(1:2:nrow(df), HTMLDecoration(background = "light_gray",)), show_row_number=false, title="$start_date - $end_date @ $location_name", title_alignment=:c)
    close(io)
    DefaultApplication.open(file)
end

end
