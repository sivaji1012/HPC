"""
Traverse — fruit-fly-inspired traversal for HPC multi-space queries.

Inspired by information flow in the Drosophila central brain (Lappalainen et al. 2024):
  traversal_probability = incoming_synapses_from_set / total_incoming_synapses

In MORK:
  traversal_probability = count(atoms matching functor) / total_atoms(space)

When p < threshold (default 0.3) the space is NOT traversed — sparse activation.

Stage 1: single-space traversal with probability gate.
Stage 2: propagate to peer spaces via MPI point-to-point.
Stage 3 (Web3): propagate globally with CID-addressed routing.
"""

const TRAVERSAL_THRESHOLD = 0.3

"""
    TraversalResult

  count      — number of matches found
  p_traverse — traversal probability
  activated  — whether the space was traversed (p ≥ threshold)
  rank       — traversal depth (0 = seed, 1 = first hop)
"""
struct TraversalResult
    count      :: Int
    p_traverse :: Float64
    activated  :: Bool
    rank       :: Int
end

"""
    space_traverse!(space, seed_str, depth=1; threshold, dest_peer) → TraversalResult

Fruit-fly-inspired traversal. Computes p = count(functor matches) / total_atoms.
If p < threshold (0.3), returns immediately — sparse activation gate.

Stage 2 MPI: when mpi_active() and p ≥ threshold, propagates seed to peer spaces
via non-blocking MPI send. Each peer independently decides to activate.

depth=0: local only (no MPI propagation — used when processing incoming peer queries).
dest_peer: LOCAL_PEER → broadcast to all peers; specific rank → point-to-point.
"""
function space_traverse!(space     :: Space,
                          seed_str  :: AbstractString,
                          depth     :: Int     = 1;
                          threshold :: Float64 = TRAVERSAL_THRESHOLD,
                          dest_peer :: Int32   = LOCAL_PEER) :: TraversalResult
    total   = Float64(max(1, space_val_count(space)))
    n_raw   = hpc_count_pattern(space, seed_str)
    n_match = n_raw == typemax(Int) ? 0 : n_raw
    p       = Float64(n_match) / total

    p < threshold && return TraversalResult(0, p, false, 0)

    # ── Stage 2: MPI peer propagation ─────────────────────────────────────────
    if mpi_active() && depth > 0
        query_bytes = Vector{UInt8}(seed_str)
        if dest_peer == LOCAL_PEER
            mpi_broadcast_traverse!(query_bytes)
        else
            mpi_send_traverse!(dest_peer, query_bytes)
        end
    end

    TraversalResult(n_match, p, true, 0)
end

"""
    process_mpi_traversals!(space; threshold) → Int

Poll and process all pending MPI traverse requests from peer nodes.
Returns number of requests handled. Non-blocking — zero overhead when no messages.

Call from the peer main loop:
    while true
        space_metta_calculus!(s, 100)
        process_mpi_traversals!(s)
    end
"""
function process_mpi_traversals!(space     :: Space;
                                  threshold :: Float64 = TRAVERSAL_THRESHOLD) :: Int
    mpi_active() || return 0
    count = 0
    while true
        msg = mpi_poll_traverse!()
        msg === nothing && break
        _, query_bytes = msg
        space_traverse!(space, String(query_bytes), 0; threshold=threshold)
        count += 1
    end
    count
end

export TRAVERSAL_THRESHOLD, TraversalResult, space_traverse!, process_mpi_traversals!
