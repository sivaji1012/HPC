using Test, HPC, MORK

@testset "HPC" begin
    include("test_multispace.jl")
    include("test_mpi_transport.jl")
    include("test_sharded_space.jl")
end

println("All tests passed ✓")
