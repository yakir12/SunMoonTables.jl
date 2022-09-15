using SunMoonTables
function generate_test_table()
    df = SunMoonTables.get_table(Date(2000, 6, 1), Date(2000, 6, 10), 51.5085, -0.1257, [20, 30, 45, 60, 75])
    SunMoonTables.CSV.write("/home/yakir/.julia/dev/SunMoonTables/test/table.csv", df)
end




    - \\usepackage{anyfontsize}
\\fontsize{24}{29}\\selectfont

function highest_sun_elevation(day::Date, location)
    latitude, longitude, elevation, tz_str = locations[location]
    tz = TimeZone(tz_str)
    jd1 = TimeZones.zdt2julian(ZonedDateTime(day, tz))
    jd2 = jd1 + 1
    S = Chebyshev(jd1..jd2)
    p = points(S, 24)
    v = sun_altitude.(p, latitude, longitude, elevation)
    sun = Fun(S, ApproxFun.transform(S, v))
    jd = last(roots(sun'))
    x = julian2dt(jd, tz)[2]
    y = sun(jd)
    string("The sun elevation will be ", round(Int, y), "° at ", x, " on ", day)
end

msg = highest_sun_elevation(Date(2022, 5, 18), location)


using SunMoonTables, Dates

main(Date(2000, 6, 1), Date(2000, 6, 10), 51.5085, -0.1257)



start_date = Date(2000,1,1)
end_date = Date(2000,1,10)
latitude = 51.5085
longitude = -0.1257
elevations= Set([20, 30, 45, 60, 75])
elevation, tz = SunMoonTables.elevation_timezone(latitude, longitude)
start_date = DateTime(start_date, Time(0, 0, 0))
end_date = DateTime(end_date, Time(23, 59, 59))

    push!(elevations, 0)
    filter!(<(90), elevations)
    elevations = sort(collect(elevations))

    jd1 = SunMoonTables.TimeZones.zdt2julian(SunMoonTables.ZonedDateTime(start_date, tz))
    jd2 = SunMoonTables.TimeZones.zdt2julian(SunMoonTables.ZonedDateTime(end_date, tz))

julian_dates = jd1
right_ascension, declination = SunMoonTables.sunpos(julian_dates)
altitude, azimuth, _ = SunMoonTables.eq2hor(right_ascension, declination, julian_dates, latitude, longitude, elevation)


ndays = round(Int, jd2 - jd1)
S = SunMoonTables.Chebyshev(jd1..jd2)
p = SunMoonTables.points(S, 24*ndays)

v = sun_altitude.(p, latitude, longitude, elevation)

using pandoc_jll

start_date, end_date, latitude, longitude = (Date(2000, 6, 1), Date(2000, 6, 10), 51.5085, -0.1257)
elevations= [20, 30, 45, 60, 75]
pdf = false
elevation, tz_str = elevation_timezone(latitude, longitude)

start_date, end_date, latitude, longitude, elevation, tz, elevations = (DateTime(start_date, Time(0, 0, 1)), DateTime(end_date, Time(23, 59, 59)), latitude, longitude, elevation, tz_str, Set(elevations))


function print2pdf(df, latitude, longitude, start_date, end_date)
    mktemp() do file, io
        println(io, """
                ---
                title: "lat:$latitude-lon:$longitude"
                subtitle: "$start_date - $end_date"
                documentclass: extarticle
                fontsize: 20pt
                papersize: a3
                classoption: table
                geometry: "landscape, margin = 1cm"
                header-includes: 
                - \\pagenumbering{gobble}
                - \\rowcolors{3}{gray!0}{gray!20} 
                - \\setcounter{secnumdepth}{0} 
                ---

                """)
        pretty_table(io, df; tf = tf_markdown, nosubheader = true, formatters = ft_nomissing)
        close(io)
        pandoc_jll.pandoc() do exe
            run(`$exe -f markdown -o table.pdf $file`)
        end
    end
end

    # pdf ? print2pdf(df, latitude, longitude, start_date, end_date) : 
