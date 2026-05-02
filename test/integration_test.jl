"""
HPC Integration Test — exercises all three topologies with real MPI.

Run single-node:  julia --project=. test/integration_test.jl
Run multi-rank:
  julia --project=. -e '
    using MPI
    MPI.mpiexec() do m
      run(`\$m -n 4 julia --project=. test/integration_test.jl`)
    end'
"""

using HPC, MORK
import MPI

# ── Initialise MPI via HPC (sets _MPI_COMM, rank, nranks) ─────────────────────
enable_multi_space!(true; use_mpi=true)

rank   = mpi_rank()
nranks = mpi_nranks()

println("[$rank/$nranks] HPC integration test starting")

# ─── Topology 1: each peer owns local domain spaces ───────────────────────────

reg = get_registry()
local_space = new_space!(reg, "domain-rank-$rank", Symbol("domain"))
space_add_all_sexpr!(local_space, "(fact rank-$rank a) (fact rank-$rank b) (fact rank-$rank c)")

@assert space_val_count(local_space) == 3
println("[$rank/$nranks] Topology 1 ✓  local space: $(space_val_count(local_space)) atoms")

# ─── Topology 2: ShardedSpace — common knowledge across all peers ─────────────

common = new_space!(reg, "common-kb", :common)
# Single-node → plain Space; multi-node → ShardedSpace

for i in 1:5
    atom = "(shared-fact rank-$rank item-$i)"
    if common isa ShardedSpace
        sharded_add!(common, atom)
    else
        space_add_all_sexpr!(common, atom)
    end
end

# Flush all incoming atoms from peer sharded_add! calls
if common isa ShardedSpace
    mpi_barrier!()     # wait for all sends to complete
    sharded_flush!(common)
    mpi_barrier!()     # ensure all flushes done
    sharded_flush!(common)  # second pass for any late arrivals
end

total    = common isa ShardedSpace ? sharded_val_count(common) : space_val_count(common)
expected = 5 * nranks
@assert total == expected "Topology 2: total=$total expected=$expected"
println("[$rank/$nranks] Topology 2 ✓  shared space: $total atoms across $nranks peers")

# Query common space for all shared-fact atoms
# sharded_query works for both ShardedSpace and plain Space (single-node)
results = common isa ShardedSpace ?
          sharded_query(common, "(shared-fact \$r \$i)") :
          filter(l -> startswith(l, "(shared-fact "),
                 split(space_dump_all_sexpr(common), "\n"; keepempty=false))

@assert length(results) == expected "Topology 2 query: got=$(length(results)) expected=$expected"
println("[$rank/$nranks] Topology 2 query ✓  found $(length(results)) atoms from all shards")

# ─── Topology 3: fruit-fly traversal gate ─────────────────────────────────────

test_space = new_space()
space_add_all_sexpr!(test_space, "(edge 0 1) (edge 1 2) (edge 2 3) (edge 3 4)")

# Dense pattern — should activate (4/4 = 1.0 ≥ 0.3)
result = space_traverse!(test_space, "(edge \$x \$y)"; threshold=0.3)
@assert result.activated  "traversal should activate"
@assert result.count == 4

# Sparse — should NOT activate
sparse = space_traverse!(test_space, "(nonexistent \$x)"; threshold=0.3)
@assert !sparse.activated

println("[$rank/$nranks] Topology 3 ✓  activated=$(result.activated) count=$(result.count)")

# ─── MPI traversal poll (Topology 3 cross-peer) ───────────────────────────────

n = process_mpi_traversals!(test_space)
println("[$rank/$nranks] MPI poll ✓  processed $n incoming traverse queries")

mpi_barrier!()
println("[$rank/$nranks] ALL TESTS PASSED ✓")

# Drain any pending non-blocking messages before finalizing
mpi_barrier!()
process_mpi_traversals!(test_space)
mpi_barrier!()

mpi_finalize!()
