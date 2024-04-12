module SunMoonTables

using Dates, Statistics, Downloads
using AstroLib, TimeZones, PrettyTables, DataFrames, ApproxFun, Interpolations, TimeZoneFinder, DefaultApplication, CSV, SatelliteToolbox, DataDeps, NCDatasets, GLMakie

export main, moon_app, Date

const ALTITUDE = Ref{Interpolations.GriddedInterpolation{Float64, 2, Matrix{Union{Missing, Int16}}, Gridded{Linear{Throw{OnGrid}}}, Tuple{Vector{Float64}, Vector{Float64}}}}()

function fallback_download(remotepath, localdir)
    @assert(isdir(localdir))
    filename = basename(remotepath)  # only works for URLs with filename as last part of name
    localpath = joinpath(localdir, filename)
    downloader = Downloads.Downloader()
    downloader.easy_hook = (easy, info) -> Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_LOW_SPEED_TIME, 60)
    Downloads.download(remotepath, localpath; downloader=downloader)
    return localpath
end

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

function get_sun_tbl(sun, elevations_set, latitude, longitude, altitude, tz, md, crepuscular_elevation)
    dsun = sun'
    jd = roots(dsun)
    push!(elevations_set, crepuscular_elevation, 0)
    filter!(x -> crepuscular_elevation ≤ x ≤ 90, elevations_set)
    elevations = sort(collect(elevations_set))
    jd = mapreduce(e -> roots(sun - e), vcat, elevations, init = jd)
    df = DataFrame(sun_jd2row.(jd, latitude, longitude, altitude, tz, dsun, md))
    subset!(df, :elevation => ByRow(≥(crepuscular_elevation)))
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

function sunmoon(start_datetime, end_datetime, latitude, longitude, altitude, tz, elevations_set, points_per_day, md, crepuscular_elevation)
    jd1 = TimeZones.zdt2julian(ZonedDateTime(start_datetime, tz))
    jd2 = TimeZones.zdt2julian(ZonedDateTime(end_datetime, tz))

    sun, moon = get_sun_moon(jd1, jd2, latitude, longitude, altitude, points_per_day)

    sun_tbl = get_sun_tbl(sun, elevations_set, latitude, longitude, altitude, tz, md, crepuscular_elevation)
    moon_tbl = get_moon_tbl(moon, sun, tz, jd1, jd2)

    tbl = outerjoin(sun_tbl, moon_tbl, on = :Date)
    sort!(tbl, :Date)
    tbl.Date = string.(tbl.Date)
    return tbl
end

function get_table(start_date, end_date, latitude, longitude, elevations, points_per_day, crepuscular_elevation)
    altitude = get_altitude(latitude, longitude)
    tz = timezone_at(latitude, longitude)
    md = magnetic_declination(decimaldate(start_date), latitude, longitude, altitude)
    @info "the magnetic declination angle is $(round(md; digits=2))°"
    start_datetime = DateTime(start_date, Time(0, 1, 0))
    end_datetime = DateTime(end_date, Time(23, 59, 0))
    elevations_set = Set(elevations)
    return sunmoon(start_datetime, end_datetime, latitude, longitude, altitude, tz, elevations_set, points_per_day, md, crepuscular_elevation)
end

function main(start_date, end_date, latitude, longitude; location_name="$latitude:$longitude", elevations=[20, 30, 45, 60, 75], points_per_day=24, save_table=false, crepuscular_elevation=0)
    @assert end_date ≥ start_date "ending date must be equal or later than starting date"
    @assert -90 ≤ latitude ≤ 90 "latitude must be between -90 and 90"
    @assert -180 ≤ latitude ≤ 180 "longitude must be between -180 and 180"
    @assert crepuscular_elevation ≤ 0 "crepuscular elevation must be smaller than 0"
    df = get_table(start_date, end_date, latitude, longitude, elevations, points_per_day, crepuscular_elevation)
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

tosecond(t::T) where {T} = round(Int, t / convert(T, Dates.Second(1)))
julian2second(jd, tz, jd1) = tosecond(julian2dt(jd, tz) - julian2dt(jd1, tz))
_second2(s, jd1, tz) = julian2dt(jd1, tz) + Second(s)
const time_form = dateformat"HH:MM"
const date_form = dateformat"u-d"
second2time(s, jd1, tz) = Dates.format(Time(_second2(s, jd1, tz)), time_form)
second2date(s, jd1, tz) = Dates.format(Date(_second2(s, jd1, tz)), date_form)


function moon_figure(jd1, jd2, tz, crepuscular_elevation, sun, moon)
    n = round(Int, 240*(jd2 - jd1))
    jds = range(jd1, jd2, n)
    x = julian2second.(jds, tz, jd1)
    fig = Figure()
    axt = Axis(fig[1,1], xtickformat = s -> second2time.(s, jd1, tz), limits=(nothing, (0,90)), yticks = 0:10:90, xlabel = "Time", ylabel = "Elevation", ytickformat = "{:n}°")
    js = roots(sun + crepuscular_elevation)
    sort!(unique!(push!(js, jd1, jd2)))
    s = julian2second.(js, tz, jd1)
    start = s[1:2:end]
    stop = s[2:2:end]
    vspan!(axt, start, stop, color=(:gray, 0.5))
    lines!(axt, x, moon.(jds))
    axd = Axis(fig[1,1], xticks = WilkinsonTicks(2), xtickformat = s -> second2date.(s, jd1, tz), limits=(nothing, (0,100)), yticks = 0:10:100, xlabel = "Date", ylabel = "Phase", ytickformat = "{:n}%",  xaxisposition = :top, yaxisposition = :right)
    lines!(axd, x, 100mphase.(jds))
    hidespines!(axd)
    hidedecorations!(axd, label = false, ticklabels = false, ticks = false, grid = true, minorgrid = true, minorticks = false)
    sl = IntervalSlider(fig[2, 1], range = range(jd1, jd2, n), startvalues = (jd1, min(jd1+1, jd2)))
    on(sl.interval) do jds
        s1, s2 = julian2second.(jds, tz, jd1)
        xlims!(axt, s1, s2) 
        xlims!(axd, s1, s2) 
        dt1, dt2 = julian2dt.(jds, tz)
        dt1 = ceil(dt1, Hour(1))
        dt2 = floor(dt2, Hour(1))
        dts = range(dt1, dt2, step=Hour(3))
        s =  tosecond.(dts .- julian2dt(jd1, tz))
        axt.xticks[] = s
    end
    notify(sl.interval)
    return fig
end

function moon_app(start_date, end_date, latitude, longitude; location_name="$latitude:$longitude", elevations=[20, 30, 45, 60, 75], points_per_day=24, save_table=false, crepuscular_elevation=0)
    @assert end_date ≥ start_date "ending date must be equal or later than starting date"
    @assert -90 ≤ latitude ≤ 90 "latitude must be between -90 and 90"
    @assert -180 ≤ latitude ≤ 180 "longitude must be between -180 and 180"
    @assert crepuscular_elevation ≤ 0 "crepuscular elevation must be smaller than 0"
    altitude = get_altitude(latitude, longitude)
    tz = timezone_at(latitude, longitude)
    start_datetime = DateTime(start_date, Time(0, 1, 0))
    end_datetime = DateTime(end_date, Time(23, 59, 0))
    elevations_set = Set(elevations)
    jd1 = TimeZones.zdt2julian(ZonedDateTime(start_datetime, tz))
    jd2 = TimeZones.zdt2julian(ZonedDateTime(end_datetime, tz))
    sun, moon = get_sun_moon(jd1, jd2, latitude, longitude, altitude, points_per_day)
    fig = moon_figure(jd1, jd2, tz, crepuscular_elevation, sun, moon)
    display(fig)
end

end

# start_date, end_date, latitude, longitude = (Date(2000, 6, 1), Date(2000, 6, 10), 51.5085, -0.1257)
# location_name="$latitude:$longitude"
# elevations=[20, 30, 45, 60, 75]
# points_per_day=24
# save_table=false
# crepuscular_elevation=-15
