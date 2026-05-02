"""
HPC — Julia HPC peer-to-peer multi-space layer for MORK.

Implements the distributed Atomspace model from Hyperon Whitepaper §9:
  - Multiple App Atomspaces (per-domain, local to each peer)
  - Common Atomspace (shared knowledge, ShardedSpace across all peers)

Three topologies (composable):
  Topology 1 — single node, multiple spaces  (SpaceRegistry, zero overhead)
  Topology 2 — single logical space, N peers (ShardedSpace, MPI collectives)
  Topology 3 — N independent spaces, peers   (space_traverse!, MPI point-to-point)

Architecture:
  - SPMD: every peer runs identical code, differentiated by MPI rank
  - No master/worker: every peer is equal
  - Routing: fruit-fly traversal probability gate (threshold=0.3, Drosophila paper)
  - Zero overhead: ENABLE_MULTI_SPACE[]=false bypasses everything

Scale:
  mpirun -n 1    julia script.jl   → single node, shared memory
  mpirun -n 128  julia script.jl   → 128 peers, same binary
  mpirun -n 9216 julia script.jl   → Frontier-scale HPC, same binary

Dependencies: MORK + MPI.jl only (no PRIMUS_Core, no PRIMUS_Metagraph).
"""
module HPC

using MORK

# ── Layer 0: Minimal parser (no MorkSupercompiler dependency) ────────────────
include("multispace/HPCParser.jl")

# ── Layer 1: Registry + peer identity ────────────────────────────────────────
include("multispace/MultiSpace.jl")

# ── Layer 2: MPI transport (Stage 2 — peer-to-peer + collectives) ────────────
include("multispace/MPITransport.jl")

# ── Layer 3: Sharded common space (Topology 2) ───────────────────────────────
include("multispace/ShardedSpace.jl")

# ── Layer 4: Fruit-fly traversal (Topology 3) ────────────────────────────────
include("multispace/Traverse.jl")

# ── Layer 5: MM2 command interception ────────────────────────────────────────
include("multispace/MM2Commands.jl")

# ── Layer 6: Persistence (save/load spaces) ──────────────────────────────────
include("multispace/Persistence.jl")

end # module
