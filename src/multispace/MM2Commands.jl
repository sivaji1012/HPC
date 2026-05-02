"""
MM2Commands — intercept and execute multi-space MM2 commands.

Supported commands (all intercepted BEFORE space_metta_calculus!):
  (new-space name)           — create space with default role :app
  (new-space name role)      — create space with any user-defined role
  (new-space name common)    — create shared space (ShardedSpace on MPI)
  (shared-space)             — returns the designated :common space
  (save-space name path.act) — persist space to .act file
  (load-space name path.act) — load/restore space from .act file
  (list-spaces)              — print all registered spaces

Role is any user-defined symbol. Architects name their own topology freely.
Only :common has special semantics (ShardedSpace when MPI active, plain
Space on single-node). All other roles create a local Space.
Examples: common, genomics, robotics, games, drug-discovery, mathematics
Cognitive algorithms (PLN/ECAN/MOSES rules) are atoms IN :common, not separate spaces.

When ENABLE_MULTI_SPACE[] = false, this module is a no-op.
"""

# ── Command detection ─────────────────────────────────────────────────────────

const _MULTISPACE_COMMANDS = Set(["new-space", "shared-space",
                                   "save-space", "load-space", "list-spaces"])

"""
    is_multispace_command(node::HPCNode) → Bool

True if this atom is a recognised multi-space MM2 command.
"""
function is_multispace_command(node::HPCNode) :: Bool
    node isa HPCList || return false
    items = (node::HPCList).items
    isempty(items) && return false
    items[1] isa HPCAtom || return false
    (items[1]::HPCAtom).name ∈ _MULTISPACE_COMMANDS
end

# ── Command execution ─────────────────────────────────────────────────────────

"""
    execute_multispace_command!(reg, node) → Bool

Execute one multi-space MM2 command against `reg`.
Returns true if the command was handled, false if unrecognised.
"""
function execute_multispace_command!(reg::SpaceRegistry, node::HPCNode) :: Bool
    node isa HPCList || return false
    items = (node::HPCList).items
    isempty(items) && return false
    items[1] isa HPCAtom || return false
    cmd = (items[1]::HPCAtom).name

    if cmd == "new-space"
        length(items) >= 2 || error("(new-space \"name\") requires at least 1 argument")
        name = _extract_string(items[2])
        role = length(items) >= 3 ? _extract_role(items[3]) : :app
        new_space!(reg, name, role)
        @info "MultiSpace: created space \"$name\" (:$role)"
        return true

    elseif cmd == "shared-space"
        s = common_space(reg)
        @info "MultiSpace: common space has $(space_val_count(s)) atoms"
        return true

    elseif cmd == "save-space"
        length(items) >= 3 || error("(save-space \"name\" \"path\") requires 2 arguments")
        name = _extract_string(items[2])
        path = _extract_string(items[3])
        save_space!(reg, name, path)
        return true

    elseif cmd == "load-space"
        length(items) >= 3 || error("(load-space \"name\" \"path\") requires 2 arguments")
        name = _extract_string(items[2])
        path = _extract_string(items[3])
        load_space!(reg, name, path)
        return true

    elseif cmd == "list-spaces"
        _print_space_list(reg)
        return true
    end

    false
end

# ── Program preprocessing ─────────────────────────────────────────────────────

"""
    process_multispace_commands!(reg, program) → String

Scan `program` for multi-space MM2 commands, execute them, and return
the remaining program text with those commands removed.

Called by `execute!` / `run!` / `plan!` when ENABLE_MULTI_SPACE[] = true.
Zero overhead when ENABLE_MULTI_SPACE[] = false (not called at all).
"""
function process_multispace_commands!(reg::SpaceRegistry,
                                       program::AbstractString) :: String
    nodes    = hpc_parse(program)
    remaining = HPCNode[]

    for node in nodes
        if is_multispace_command(node)
            execute_multispace_command!(reg, node)
        else
            push!(remaining, node)
        end
    end

    hpc_sprint_program(remaining)
end

# ── Helpers ───────────────────────────────────────────────────────────────────

function _extract_string(node::HPCNode) :: String
    node isa HPCAtom && return (node::HPCAtom).name
    # Handle quoted strings stored as atoms with quotes stripped
    node isa HPCList && return hpc_sprint_sexpr(node)
    error("expected string atom, got $(hpc_sprint_sexpr(node))")
end

function _extract_role(node::HPCNode) :: Symbol
    node isa HPCAtom || error("expected a role symbol (e.g. common, genomics, robotics, games)")
    name = (node::HPCAtom).name
    # Strip optional leading colon (":app" → "app", ":common" → "common")
    startswith(name, ":") && (name = name[2:end])
    # Any symbol is valid — architect freely names their topology
    # Only :common has special semantics (ShardedSpace when MPI active)
    Symbol(name)
end

function _print_space_list(reg::SpaceRegistry)
    entries = list_spaces(reg)
    if isempty(entries)
        println("MultiSpace: no spaces registered")
        return
    end
    println("MultiSpace registry:")
    for e in entries
        disk_str = e.disk === nothing ? "" : " [$(e.disk)]"
        println("  $(rpad(e.name, 24))  :$(e.role)  $(e.atoms) atoms$disk_str")
    end
end

export is_multispace_command, execute_multispace_command!
export process_multispace_commands!
