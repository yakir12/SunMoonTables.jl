using SunMoonTables
using Test

tbl = SunMoonTables.DataFrame(SunMoonTables.CSV.File("table.csv"; types=String))
tbl = tbl[:, SunMoonTables.Not([:Moonrise, :Moonset])]

@testset "SunMoonTables.jl" begin
    df = SunMoonTables.get_table(Date(2000, 6, 1), Date(2000, 6, 10), 51.5085, -0.1257, [20, 30, 45, 60, 75])
    df = df[:, SunMoonTables.Not([:Moonrise, :Moonset])]
    @test tbl == df
end
