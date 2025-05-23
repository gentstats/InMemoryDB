module InMemoryDB

using Base.Threads
using DataStructures: OrderedDict
using UUIDs

# Export with more specific names to avoid conflicts
export Database, Table, Index, Query
export create_table!, drop_table!, db_insert!, db_select, db_update!, db_delete!
export create_index!, drop_index!
export @db_query
# Export index types
export HashIndex, BTreeIndex
# Export query clause types
export WhereClause, SelectClause, OrderByClause, LimitClause

# Type system for database values
const DBValue = Union{Int, Float64, String, Bool, Nothing, Vector{UInt8}}
const DBRow = Dict{Symbol, DBValue}
const DBRowInput = Dict{Symbol, Any}  # More flexible input type

# Forward declarations for abstract types
abstract type AbstractIndex end
abstract type AbstractQuery end
abstract type QueryClause end

# Index implementations using Julia's type system
"""
Hash index for O(1) equality lookups
"""
struct HashIndex <: AbstractIndex
    column::Symbol
    index::Dict{DBValue, Vector{Int}}
    
    HashIndex(column::Symbol) = new(column, Dict{DBValue, Vector{Int}}())
end

"""
B-tree style index using Julia's built-in sorted collections for range queries
"""
struct BTreeIndex <: AbstractIndex
    column::Symbol
    index::OrderedDict{DBValue, Vector{Int}}
    
    BTreeIndex(column::Symbol) = new(column, OrderedDict{DBValue, Vector{Int}}())
end

"""
Table structure with columnar storage for better cache performance
"""
mutable struct Table
    name::Symbol
    schema::Dict{Symbol, Type}
    columns::Dict{Symbol, Vector{DBValue}}
    indices::Dict{Symbol, AbstractIndex}
    row_count::Int
    deleted_rows::Set{Int}
    lock::ReentrantLock
    
    function Table(name::Symbol, schema::Dict{Symbol, Type})
        columns = Dict{Symbol, Vector{DBValue}}()
        for (col_name, col_type) in schema
            columns[col_name] = Vector{DBValue}()
        end
        new(name, schema, columns, Dict{Symbol, AbstractIndex}(), 0, Set{Int}(), ReentrantLock())
    end
end

"""
Thread-safe in-memory database implementation optimized for Julia
"""
mutable struct Database
    tables::Dict{Symbol, Table}
    lock::ReentrantLock
    
    function Database()
        new(Dict{Symbol, Table}(), ReentrantLock())
    end
end

# Query system using Julia's multiple dispatch
struct WhereClause <: QueryClause
    column::Symbol
    operator::Symbol
    value::DBValue
end

struct SelectClause <: QueryClause
    columns::Vector{Symbol}
end

struct OrderByClause <: QueryClause
    column::Symbol
    ascending::Bool
end

struct LimitClause <: QueryClause
    limit::Int
end

"""
Query builder pattern
"""
mutable struct Query
    table::Symbol
    clauses::Vector{QueryClause}
    
    Query(table::Symbol) = new(table, QueryClause[])
end

# Database operations with multiple dispatch
"""
Create a new table with specified schema
"""
function create_table!(db::Database, name::Symbol, schema::Dict{Symbol, Type})
    lock(db.lock) do
        if haskey(db.tables, name)
            throw(ArgumentError("Table $name already exists"))
        end
        db.tables[name] = Table(name, schema)
    end
    return nothing
end

"""
Drop an existing table
"""
function drop_table!(db::Database, name::Symbol)
    lock(db.lock) do
        if !haskey(db.tables, name)
            throw(ArgumentError("Table $name does not exist"))
        end
        delete!(db.tables, name)
    end
    return nothing
end

"""
Insert a row into a table with automatic type checking
"""
function db_insert!(db::Database, table_name::Symbol, row::DBRowInput)
    table = get_table(db, table_name)
    
    lock(table.lock) do
        # Validate schema
        validate_row_schema(table, row)
        
        # Insert into columns
        row_id = table.row_count + 1
        for (col_name, col_type) in table.schema
            value = get(row, col_name, nothing)
            push!(table.columns[col_name], value)
        end
        
        table.row_count += 1
        
        # Update indices
        update_indices_insert!(table, row, row_id)
    end
    
    return table.row_count
end

"""
Batch insert for better performance
"""
function db_insert!(db::Database, table_name::Symbol, rows::Vector{DBRowInput})
    table = get_table(db, table_name)
    
    lock(table.lock) do
        start_row_id = table.row_count + 1
        
        # Pre-allocate space for better performance
        for col_name in keys(table.schema)
            sizehint!(table.columns[col_name], table.row_count + length(rows))
        end
        
        for (i, row) in enumerate(rows)
            validate_row_schema(table, row)
            
            row_id = start_row_id + i - 1
            for (col_name, col_type) in table.schema
                value = get(row, col_name, nothing)
                push!(table.columns[col_name], value)
            end
            
            update_indices_insert!(table, row, row_id)
        end
        
        table.row_count += length(rows)
    end
    
    return table.row_count
end

"""
Select data using query builder or direct conditions
"""
function db_select(db::Database, query::Query)
    table = get_table(db, query.table)
    
    lock(table.lock) do
        # Start with all valid row IDs
        matching_rows = Set(1:table.row_count)
        setdiff!(matching_rows, table.deleted_rows)
        
        # Apply WHERE clauses
        for clause in query.clauses
            if clause isa WhereClause
                matching_rows = apply_where_clause(table, matching_rows, clause)
            end
        end
        
        # Convert to vector for indexing
        row_ids = collect(matching_rows)
        
        # Apply ORDER BY
        order_clause = findfirst(c -> c isa OrderByClause, query.clauses)
        if order_clause !== nothing
            clause = query.clauses[order_clause]
            sort_column = table.columns[clause.column]
            sort!(row_ids, by=id -> sort_column[id], rev=!clause.ascending)
        end
        
        # Apply LIMIT
        limit_clause = findfirst(c -> c isa LimitClause, query.clauses)
        if limit_clause !== nothing
            clause = query.clauses[limit_clause]
            row_ids = row_ids[1:min(length(row_ids), clause.limit)]
        end
        
        # Apply SELECT
        select_clause = findfirst(c -> c isa SelectClause, query.clauses)
        columns_to_select = if select_clause !== nothing
            query.clauses[select_clause].columns
        else
            collect(keys(table.schema))
        end
        
        # Build result
        return build_result(table, row_ids, columns_to_select)
    end
end

"""
Simple select interface
"""
function db_select(db::Database, table_name::Symbol; 
                   where::Union{Nothing, Tuple{Symbol, Symbol, DBValue}} = nothing,
                   columns::Vector{Symbol} = Symbol[],
                   order_by::Union{Nothing, Tuple{Symbol, Bool}} = nothing,
                   limit::Union{Nothing, Int} = nothing)
    
    query = Query(table_name)
    
    if where !== nothing
        push!(query.clauses, WhereClause(where[1], where[2], where[3]))
    end
    
    if !isempty(columns)
        push!(query.clauses, SelectClause(columns))
    end
    
    if order_by !== nothing
        push!(query.clauses, OrderByClause(order_by[1], order_by[2]))
    end
    
    if limit !== nothing
        push!(query.clauses, LimitClause(limit))
    end
    
    return db_select(db, query)
end

# Helper function for type conversion in select operations
function db_select_with_conversion(db::Database, table_name::Symbol; 
                                 where::Union{Nothing, Tuple{Symbol, Symbol, <:Any}} = nothing,
                                 columns::Vector{Symbol} = Symbol[],
                                 order_by::Union{Nothing, Tuple{Symbol, Bool}} = nothing,
                                 limit::Union{Nothing, Int} = nothing)
    
    # Convert where clause to use DBValue
    converted_where = if where !== nothing
        (where[1], where[2], convert_to_dbvalue(where[3]))
    else
        nothing
    end
    
    query = Query(table_name)
    
    if converted_where !== nothing
        push!(query.clauses, WhereClause(converted_where[1], converted_where[2], converted_where[3]))
    end
    
    if !isempty(columns)
        push!(query.clauses, SelectClause(columns))
    end
    
    if order_by !== nothing
        push!(query.clauses, OrderByClause(order_by[1], order_by[2]))
    end
    
    if limit !== nothing
        push!(query.clauses, LimitClause(limit))
    end
    
    return db_select(db, query)
end

"""
Update records matching conditions
"""
function db_update!(db::Database, table_name::Symbol, updates::DBRowInput;
                    where::Union{Nothing, Tuple{Symbol, Symbol, DBValue}} = nothing)
    table = get_table(db, table_name)
    
    lock(table.lock) do
        # Find matching rows
        matching_rows = if where !== nothing
            query = Query(table_name)
            push!(query.clauses, WhereClause(where[1], where[2], where[3]))
            row_ids = Set(1:table.row_count)
            setdiff!(row_ids, table.deleted_rows)
            apply_where_clause(table, row_ids, query.clauses[1])
        else
            Set(1:table.row_count) |> r -> setdiff!(r, table.deleted_rows)
        end
        
        # Update columns
        updated_count = 0
        for row_id in matching_rows
            old_row = get_row(table, row_id)
            
            # Update indices (remove old values)
            update_indices_delete!(table, old_row, row_id)
            
            # Update the row
            for (col_name, new_value) in updates
                if haskey(table.schema, col_name)
                    table.columns[col_name][row_id] = new_value
                end
            end
            
            # Update indices (add new values)
            new_row = get_row(table, row_id)
            update_indices_insert!(table, new_row, row_id)
            
            updated_count += 1
        end
        
        return updated_count
    end
end

# Helper function for update with type conversion
function db_update_with_conversion!(db::Database, table_name::Symbol, updates::DBRowInput;
                                   where::Union{Nothing, Tuple{Symbol, Symbol, <:Any}} = nothing)
    
    # Convert where clause to use DBValue
    converted_where = if where !== nothing
        (where[1], where[2], convert_to_dbvalue(where[3]))
    else
        nothing
    end
    
    return db_update!(db, table_name, updates, where=converted_where)
end

"""
Delete records matching conditions
"""
function db_delete!(db::Database, table_name::Symbol;
                    where::Union{Nothing, Tuple{Symbol, Symbol, DBValue}} = nothing)
    table = get_table(db, table_name)
    
    lock(table.lock) do
        # Find matching rows
        matching_rows = if where !== nothing
            query = Query(table_name)
            push!(query.clauses, WhereClause(where[1], where[2], where[3]))
            row_ids = Set(1:table.row_count)
            setdiff!(row_ids, table.deleted_rows)
            apply_where_clause(table, row_ids, query.clauses[1])
        else
            Set(1:table.row_count) |> r -> setdiff!(r, table.deleted_rows)
        end
        
        # Mark rows as deleted and update indices
        deleted_count = 0
        for row_id in matching_rows
            if !(row_id in table.deleted_rows)
                push!(table.deleted_rows, row_id)
                
                # Remove from indices
                row = get_row(table, row_id)
                update_indices_delete!(table, row, row_id)
                
                deleted_count += 1
            end
        end
        
        return deleted_count
    end
end

# Helper function for delete with type conversion
function db_delete_with_conversion!(db::Database, table_name::Symbol;
                                   where::Union{Nothing, Tuple{Symbol, Symbol, <:Any}} = nothing)
    
    # Convert where clause to use DBValue
    converted_where = if where !== nothing
        (where[1], where[2], convert_to_dbvalue(where[3]))
    else
        nothing
    end
    
    return db_delete!(db, table_name, where=converted_where)
end

# Index management
"""
Create an index on a column
"""
function create_index!(db::Database, table_name::Symbol, column::Symbol, 
                      index_type::Type{<:AbstractIndex} = HashIndex)
    table = get_table(db, table_name)
    
    lock(table.lock) do
        if haskey(table.indices, column)
            throw(ArgumentError("Index on column $column already exists"))
        end
        
        # Check if column exists in schema
        if !haskey(table.schema, column)
            throw(ArgumentError("Column $column does not exist in table $table_name"))
        end
        
        # Create index
        index = index_type(column)
        
        # Populate index with existing data
        for row_id in 1:table.row_count
            if !(row_id in table.deleted_rows)
                value = table.columns[column][row_id]
                add_to_index!(index, value, row_id)
            end
        end
        
        table.indices[column] = index
    end
    
    return nothing
end

"""
Drop an index
"""
function drop_index!(db::Database, table_name::Symbol, column::Symbol)
    table = get_table(db, table_name)
    
    lock(table.lock) do
        if !haskey(table.indices, column)
            throw(ArgumentError("Index on column $column does not exist"))
        end
        
        delete!(table.indices, column)
    end
    
    return nothing
end

# Query macro for SQL-like syntax
"""
Macro for SQL-like query syntax
"""
macro db_query(db, expr)
    # This would be expanded to parse SQL-like syntax
    # For now, return a simple implementation
    return quote
        # Parse and execute query
        $(esc(expr))
    end
end

# Helper functions
function get_table(db::Database, name::Symbol)
    if !haskey(db.tables, name)
        throw(ArgumentError("Table $name does not exist"))
    end
    return db.tables[name]
end

function validate_row_schema(table::Table, row::DBRowInput)
    for (col_name, col_type) in table.schema
        if haskey(row, col_name)
            value = row[col_name]
            if value !== nothing && !isa(value, col_type)
                throw(ArgumentError("Column $col_name expects type $col_type, got $(typeof(value))"))
            end
        end
    end
end

function get_row(table::Table, row_id::Int)
    row = DBRow()
    for (col_name, column) in table.columns
        row[col_name] = column[row_id]
    end
    return row
end

function build_result(table::Table, row_ids::Vector{Int}, columns::Vector{Symbol})
    result = Vector{DBRow}()
    sizehint!(result, length(row_ids))
    
    for row_id in row_ids
        row = DBRow()
        for col_name in columns
            if haskey(table.columns, col_name)
                row[col_name] = table.columns[col_name][row_id]
            end
        end
        push!(result, row)
    end
    
    return result
end

# Index operations using multiple dispatch
function add_to_index!(index::HashIndex, value::DBValue, row_id::Int)
    if !haskey(index.index, value)
        index.index[value] = Int[]
    end
    push!(index.index[value], row_id)
end

function add_to_index!(index::BTreeIndex, value::DBValue, row_id::Int)
    if !haskey(index.index, value)
        index.index[value] = Int[]
    end
    push!(index.index[value], row_id)
end

function remove_from_index!(index::HashIndex, value::DBValue, row_id::Int)
    if haskey(index.index, value)
        filter!(id -> id != row_id, index.index[value])
        if isempty(index.index[value])
            delete!(index.index, value)
        end
    end
end

function remove_from_index!(index::BTreeIndex, value::DBValue, row_id::Int)
    if haskey(index.index, value)
        filter!(id -> id != row_id, index.index[value])
        if isempty(index.index[value])
            delete!(index.index, value)
        end
    end
end

function update_indices_insert!(table::Table, row::Union{DBRow, DBRowInput}, row_id::Int)
    for (col_name, index) in table.indices
        value = row[col_name]
        add_to_index!(index, value, row_id)
    end
end

function update_indices_delete!(table::Table, row::DBRow, row_id::Int)
    for (col_name, index) in table.indices
        value = row[col_name]
        remove_from_index!(index, value, row_id)
    end
end

function apply_where_clause(table::Table, row_ids::Set{Int}, clause::WhereClause)
    column = table.columns[clause.column]
    
    # Use index if available
    if haskey(table.indices, clause.column) && clause.operator == :(==)
        index = table.indices[clause.column]
        if haskey(index.index, clause.value)
            indexed_ids = Set(index.index[clause.value])
            return intersect(row_ids, indexed_ids)
        else
            return Set{Int}()
        end
    end
    
    # Fallback to full scan with optimized operations
    result = Set{Int}()
    
    if clause.operator == :(==)
        @inbounds for row_id in row_ids
            if column[row_id] == clause.value
                push!(result, row_id)
            end
        end
    elseif clause.operator == :(!=)
        @inbounds for row_id in row_ids
            if column[row_id] != clause.value
                push!(result, row_id)
            end
        end
    elseif clause.operator == :(<)
        @inbounds for row_id in row_ids
            if column[row_id] < clause.value
                push!(result, row_id)
            end
        end
    elseif clause.operator == :(<=)
        @inbounds for row_id in row_ids
            if column[row_id] <= clause.value
                push!(result, row_id)
            end
        end
    elseif clause.operator == :(>)
        @inbounds for row_id in row_ids
            if column[row_id] > clause.value
                push!(result, row_id)
            end
        end
    elseif clause.operator == :(>=)
        @inbounds for row_id in row_ids
            if column[row_id] >= clause.value
                push!(result, row_id)
            end
        end
    end
    
    return result
end

# Add type conversion helper
function convert_to_dbvalue(value)
    if value isa DBValue
        return value
    elseif value isa Int || value isa Float64 || value isa String || value isa Bool || value === nothing
        return value
    elseif value isa Vector{UInt8}
        return value
    else
        # Try to convert common types
        if isa(value, AbstractString)
            return String(value)
        elseif isa(value, Real)
            return Float64(value)
        else
            throw(ArgumentError("Cannot convert value of type $(typeof(value)) to DBValue"))
        end
    end
end

end # module InMemoryDB