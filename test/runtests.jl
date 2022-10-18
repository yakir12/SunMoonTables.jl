using SunMoonTables
using Test

start_date, end_date, latitude, longitude, elevations, points_per_day = (Date(2000, 6, 1), Date(2000, 6, 10), 51.5085, -0.1257, [20, 30, 45, 60, 75], 24)

# main(start_date, end_date, latitude, longitude; elevations, points_per_day, save_table=true)

@testset "SunMoonTables.jl" begin
    tbl = SunMoonTables.DataFrame(SunMoonTables.CSV.File("table.csv"; types=String))
    df = SunMoonTables.get_table(start_date, end_date, latitude, longitude, elevations, points_per_day)
    @test tbl == df
end

@testset "IO" begin
    df = SunMoonTables.DataFrame()
    start_date = end_date = location_name = ""
    file = SunMoonTables.print2html(df, start_date, end_date, location_name)
    @test isfile(file)
end
