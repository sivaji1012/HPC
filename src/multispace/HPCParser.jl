"""
HPCParser — minimal s-expression tokeniser for HPC command parsing.

Handles only what HPC needs without depending on MorkSupercompiler's SExpr layer:
  1. Tokenise flat (cmd arg1 arg2 ...) MM2 commands.
  2. Count atoms matching a functor pattern in a Space.

Intentionally minimal — not a full MeTTa parser.
"""

# ── Minimal atom types ────────────────────────────────────────────────────────

abstract type HPCNode end

struct HPCAtom <: HPCNode
    name :: String
end

struct HPCList <: HPCNode
    items :: Vector{HPCNode}
end

# ── Tokeniser ─────────────────────────────────────────────────────────────────

"""
    hpc_parse(src) → Vector{HPCNode}

Parse `src` into a sequence of flat HPCNodes.
Handles: symbols, (list ...) expressions.
Sufficient for MM2 commands like (new-space name role).
"""
function hpc_parse(src::AbstractString) :: Vector{HPCNode}
    tokens = _tokenise(src)
    nodes  = HPCNode[]
    pos    = Ref(1)
    while pos[] <= length(tokens)
        push!(nodes, _parse_token(tokens, pos))
    end
    nodes
end

function _tokenise(src::AbstractString) :: Vector{String}
    tokens = String[]
    i = firstindex(src)
    while i <= lastindex(src)
        c = src[i]
        if c in (' ', '\t', '\n', '\r')
            i = nextind(src, i)
        elseif c == '('
            push!(tokens, "("); i = nextind(src, i)
        elseif c == ')'
            push!(tokens, ")"); i = nextind(src, i)
        elseif c == ';'   # line comment
            while i <= lastindex(src) && src[i] != '\n'
                i = nextind(src, i)
            end
        else
            j = i
            while j <= lastindex(src) && !(src[j] in (' ', '\t', '\n', '\r', '(', ')'))
                j = nextind(src, j)
            end
            push!(tokens, src[i:prevind(src, j)])
            i = j
        end
    end
    tokens
end

function _parse_token(tokens::Vector{String}, pos::Ref{Int}) :: HPCNode
    tok = tokens[pos[]]
    pos[] += 1
    if tok == "("
        items = HPCNode[]
        while pos[] <= length(tokens) && tokens[pos[]] != ")"
            push!(items, _parse_token(tokens, pos))
        end
        pos[] <= length(tokens) && (pos[] += 1)  # consume ")"
        return HPCList(items)
    else
        return HPCAtom(tok)
    end
end

# ── Pattern count (replaces dynamic_count for traversal probability) ──────────

"""
    hpc_count_pattern(space, pattern_str) → Int

Count atoms in `space` whose functor matches the head of `pattern_str`.
Uses space_dump_all_sexpr + functor prefix search.

Less precise than MorkSupercompiler's dynamic_count (binary prefix matching)
but sufficient for the traversal probability gate.
Returns 1 for bare atoms/vars, typemax(Int) for unparseable patterns.
"""
function hpc_count_pattern(space::Space, pattern_str::AbstractString) :: Int
    stripped = strip(pattern_str)
    # Bare atom or variable
    !startswith(stripped, "(") && return 1

    # Extract functor: "(edge $x $y)" → "edge"
    m = match(r"^\(\s*(\S+)", stripped)
    m === nothing && return typemax(Int)
    functor = m.captures[1]
    startswith(functor, "\$") && return typemax(Int)  # variable head

    dump = space_dump_all_sexpr(space)
    prefix = "($functor "
    exact  = "($functor)"
    count(line -> startswith(line, prefix) || line == exact,
          split(dump, "\n"; keepempty=false))
end

# ── Serialiser ────────────────────────────────────────────────────────────────

"""hpc_sprint_sexpr(node) → String — serialise an HPCNode back to s-expression."""
hpc_sprint_sexpr(n::HPCAtom) = n.name
hpc_sprint_sexpr(n::HPCList) = "(" * join(hpc_sprint_sexpr.(n.items), " ") * ")"

"""hpc_sprint_program(nodes) → String — serialise a list of HPCNodes."""
hpc_sprint_program(nodes::Vector{HPCNode}) = join(hpc_sprint_sexpr.(nodes), "\n")

export HPCNode, HPCAtom, HPCList, hpc_parse, hpc_count_pattern
export hpc_sprint_sexpr, hpc_sprint_program
