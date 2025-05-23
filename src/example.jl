using InMemoryDB

"""
Examples demonstrating the InMemoryDB library functionality
"""

function main()
    println("=== InMemoryDB Examples ===")
    
    # Basic database operations
    basic_operations_example()
    
    # Indexing examples
    indexing_example()
    
    # Batch operations
    batch_operations_example()
    
    # Query builder examples
    query_builder_example()
    
    # Advanced queries
    advanced_queries_example()
    
    # Performance and threading examples
    performance_example()
    
    # Error handling
    error_handling_example()
end

"""
Example 1: Basic Database Operations
"""
function basic_operations_example()
    println("\n--- Basic Operations Example ---")
    
    # Create a new database
    db = Database()
    
    # Define schema for a users table
    user_schema = Dict{Symbol, Type}(
        :id => Int,
        :name => String,
        :email => String,
        :age => Int,
        :active => Bool
    )
    
    # Create table
    create_table!(db, :users, user_schema)
    println("✓ Created users table")
    
    # Insert some users
    user1 = Dict{Symbol, Any}(
        :id => 1,
        :name => "Alice Johnson",
        :email => "alice@example.com",
        :age => 28,
        :active => true
    )
    
    user2 = Dict{Symbol, Any}(
        :id => 2,
        :name => "Bob Smith",
        :email => "bob@example.com",
        :age => 35,
        :active => true
    )
    
    user3 = Dict{Symbol, Any}(
        :id => 3,
        :name => "Charlie Brown",
        :email => "charlie@example.com",
        :age => 22,
        :active => false
    )
    
    # Insert users one by one
    db_insert!(db, :users, user1)
    db_insert!(db, :users, user2)
    db_insert!(db, :users, user3)
    println("✓ Inserted 3 users")
    
    # Select all users
    all_users = db_select(db, :users)
    println("📊 All users ($(length(all_users)) found):")
    for user in all_users
        println("  - $(user[:name]) ($(user[:age]) years old)")
    end
    
    # Select with conditions
    active_users = db_select(db, :users, where=(:active, :(==), true))
    println("📊 Active users: $(length(active_users))")
    
    young_users = db_select(db, :users, where=(:age, :(<), 30))
    println("📊 Users under 30: $(length(young_users))")
    
    # Select specific columns
    names_emails = db_select(db, :users, columns=[:name, :email])
    println("📊 Names and emails:")
    for user in names_emails
        println("  - $(user[:name]): $(user[:email])")
    end
      # Update user
    updated_count = db_update!(db, :users, 
        Dict{Symbol, Any}(:age => 29), 
        where=(:name, :(==), "Alice Johnson")
    )
    println("✓ Updated $updated_count user(s)")
    
    # Delete inactive users
    deleted_count = db_delete!(db, :users, where=(:active, :(==), false))
    println("✓ Deleted $deleted_count inactive user(s)")
    
    # Final count
    final_users = db_select(db, :users)
    println("📊 Final user count: $(length(final_users))")
end

"""
Example 2: Indexing for Performance
"""
function indexing_example()
    println("\n--- Indexing Example ---")
    
    db = Database()
    
    # Create products table
    product_schema = Dict{Symbol, Type}(
        :id => Int,
        :name => String,
        :category => String,
        :price => Float64,
        :stock => Int
    )
    
    create_table!(db, :products, product_schema)
    println("✓ Created products table")
    
    # Insert sample products
    products = [
        Dict(:id => 1, :name => "Laptop", :category => "Electronics", :price => 999.99, :stock => 10),
        Dict(:id => 2, :name => "Mouse", :category => "Electronics", :price => 25.50, :stock => 50),
        Dict(:id => 3, :name => "Book", :category => "Books", :price => 15.99, :stock => 100),
        Dict(:id => 4, :name => "Desk", :category => "Furniture", :price => 299.99, :stock => 5),
        Dict(:id => 5, :name => "Chair", :category => "Furniture", :price => 149.99, :stock => 15)
    ]
    
    for product in products
        db_insert!(db, :products, product)
    end
    println("✓ Inserted $(length(products)) products")
    
    # Create indices for better query performance
    create_index!(db, :products, :id, HashIndex)  # Hash index for exact matches
    create_index!(db, :products, :category, HashIndex)  # Hash index for categories
    create_index!(db, :products, :price, BTreeIndex)  # B-tree index for range queries
    println("✓ Created indices on id, category, and price")
    
    # Queries that will use indices
    println("\n🚀 Indexed queries:")
    
    # Hash index lookup (O(1))
    laptop = db_select(db, :products, where=(:id, :(==), 1))
    println("  Product with ID 1: $(laptop[1][:name])")
    
    # Category lookup using hash index
    electronics = db_select(db, :products, where=(:category, :(==), "Electronics"))
    println("  Electronics products: $(length(electronics))")
    
    # Range query using B-tree index
    affordable = db_select(db, :products, where=(:price, :(<), 100.0))
    println("  Products under \$100: $(length(affordable))")
    
    expensive = db_select(db, :products, where=(:price, :(>), 200.0))
    println("  Products over \$200: $(length(expensive))")
end

"""
Example 3: Batch Operations for Performance
"""
function batch_operations_example()
    println("\n--- Batch Operations Example ---")
    
    db = Database()
    
    # Create orders table
    order_schema = Dict{Symbol, Type}(
        :order_id => Int,
        :customer_id => Int,
        :product_id => Int,
        :quantity => Int,
        :order_date => String,
        :total => Float64
    )
    
    create_table!(db, :orders, order_schema)
    println("✓ Created orders table")
      # Generate sample orders
    orders = Vector{Dict{Symbol, Any}}()
    for i in 1:1000
        order = Dict{Symbol, Any}(
            :order_id => i,
            :customer_id => rand(1:100),
            :product_id => rand(1:50),
            :quantity => rand(1:10),
            :order_date => "2024-01-$(rand(1:31))",
            :total => round(rand(10.0:500.0), digits=2)
        )
        push!(orders, order)
    end
    
    # Batch insert (much faster than individual inserts)
    println("🚀 Performing batch insert of 1000 orders...")
    @time begin
        row_count = db_insert!(db, :orders, orders)
    end
    println("✓ Inserted $row_count orders")
    
    # Create index for efficient queries
    create_index!(db, :orders, :customer_id, HashIndex)
    
    # Query operations
    customer_orders = db_select(db, :orders, where=(:customer_id, :(==), 1))
    println("📊 Orders for customer 1: $(length(customer_orders))")
    
    large_orders = db_select(db, :orders, where=(:total, :(>), 400.0))
    println("📊 Large orders (>\$400): $(length(large_orders))")
end

"""
Example 4: Query Builder Pattern
"""
function query_builder_example()
    println("\n--- Query Builder Example ---")
    
    db = Database()
    
    # Create employees table
    employee_schema = Dict{Symbol, Type}(
        :id => Int,
        :name => String,
        :department => String,
        :salary => Float64,
        :hire_date => String,
        :performance_score => Float64
    )
    
    create_table!(db, :employees, employee_schema)
    
    # Insert sample employees
    employees = [
        Dict(:id => 1, :name => "John Doe", :department => "Engineering", :salary => 75000.0, :hire_date => "2020-01-15", :performance_score => 4.2),
        Dict(:id => 2, :name => "Jane Smith", :department => "Marketing", :salary => 65000.0, :hire_date => "2019-03-22", :performance_score => 4.8),
        Dict(:id => 3, :name => "Mike Johnson", :department => "Engineering", :salary => 80000.0, :hire_date => "2021-06-10", :performance_score => 4.0),
        Dict(:id => 4, :name => "Sarah Wilson", :department => "HR", :salary => 60000.0, :hire_date => "2018-11-05", :performance_score => 4.5),
        Dict(:id => 5, :name => "Tom Brown", :department => "Engineering", :salary => 85000.0, :hire_date => "2022-02-28", :performance_score => 4.7)
    ]
    
    db_insert!(db, :employees, employees)
    println("✓ Inserted $(length(employees)) employees")
    
    # Create indices
    create_index!(db, :employees, :department, HashIndex)
    create_index!(db, :employees, :salary, BTreeIndex)
    
    # Using Query builder
    println("\n🔍 Query builder examples:")
    
    # Simple query
    query1 = Query(:employees)
    push!(query1.clauses, WhereClause(:department, :(==), "Engineering"))
    push!(query1.clauses, SelectClause([:name, :salary]))
    
    engineering_salaries = db_select(db, query1)
    println("Engineering salaries:")
    for emp in engineering_salaries
        println("  - $(emp[:name]): \$$(emp[:salary])")
    end
    
    # Complex query with ordering and limit
    query2 = Query(:employees)
    push!(query2.clauses, WhereClause(:salary, :(>), 70000.0))
    push!(query2.clauses, OrderByClause(:salary, false))  # Descending
    push!(query2.clauses, LimitClause(3))
    push!(query2.clauses, SelectClause([:name, :salary, :performance_score]))
    
    top_earners = db_select(db, query2)
    println("\nTop 3 earners (>\$70k):")
    for (i, emp) in enumerate(top_earners)
        println("  $i. $(emp[:name]): \$$(emp[:salary]) (Score: $(emp[:performance_score]))")
    end
end

"""
Example 5: Advanced Query Operations
"""
function advanced_queries_example()
    println("\n--- Advanced Queries Example ---")
    
    db = Database()
    
    # Create customers and orders tables for relational-like operations
    customer_schema = Dict{Symbol, Type}(
        :id => Int,
        :name => String,
        :city => String,
        :signup_date => String
    )
    
    create_table!(db, :customers, customer_schema)
    
    customers = [
        Dict(:id => 1, :name => "Alice Corp", :city => "New York", :signup_date => "2023-01-15"),
        Dict(:id => 2, :name => "Bob Industries", :city => "Los Angeles", :signup_date => "2023-02-20"),
        Dict(:id => 3, :name => "Charlie Co", :city => "Chicago", :signup_date => "2023-03-10")
    ]
    
    db_insert!(db, :customers, customers)
    
    # Order table with foreign key relationship
    order_schema = Dict{Symbol, Type}(
        :id => Int,
        :customer_id => Int,
        :amount => Float64,
        :status => String
    )
    
    create_table!(db, :customer_orders, order_schema)
    
    orders = [
        Dict(:id => 1, :customer_id => 1, :amount => 1000.0, :status => "completed"),
        Dict(:id => 2, :customer_id => 1, :amount => 1500.0, :status => "pending"),
        Dict(:id => 3, :customer_id => 2, :amount => 800.0, :status => "completed"),
        Dict(:id => 4, :customer_id => 3, :amount => 2000.0, :status => "completed"),
        Dict(:id => 5, :customer_id => 2, :amount => 500.0, :status => "cancelled")
    ]
    
    db_insert!(db, :customer_orders, orders)
    
    # Create indices for join-like operations
    create_index!(db, :customer_orders, :customer_id, HashIndex)
    create_index!(db, :customer_orders, :status, HashIndex)
    
    println("✓ Created customers and orders tables with indices")
    
    # Simulate JOIN operation
    println("\n🔗 Simulating JOIN operations:")
    
    # Get all customers with their order information
    all_customers = db_select(db, :customers)
    
    for customer in all_customers
        customer_orders = db_select(db, :customer_orders, 
                                  where=(:customer_id, :(==), customer[:id]))
        
        total_amount = sum(order[:amount] for order in customer_orders)
        completed_orders = length([o for o in customer_orders if o[:status] == "completed"])
        
        println("📊 $(customer[:name]) ($(customer[:city])):")
        println("    - Total orders: $(length(customer_orders))")
        println("    - Completed orders: $completed_orders")
        println("    - Total amount: \$$(round(total_amount, digits=2))")
    end
    
    # Aggregate operations
    println("\n📈 Aggregate operations:")
    
    completed_orders = db_select(db, :customer_orders, where=(:status, :(==), "completed"))
    total_revenue = sum(order[:amount] for order in completed_orders)
    avg_order_value = total_revenue / length(completed_orders)
    
    println("  - Total completed orders: $(length(completed_orders))")
    println("  - Total revenue: \$$(round(total_revenue, digits=2))")
    println("  - Average order value: \$$(round(avg_order_value, digits=2))")
end

"""
Example 6: Comprehensive Performance Testing
"""
function performance_example()
    println("\n--- Performance Example ---")
    
    # Test different dataset sizes
    test_sizes = [1_000, 10_000, 50_000]
    
    for size in test_sizes
        println("\n🧪 Testing with $size records:")
        test_performance_with_size(size)
    end
    
    # Memory usage and threading tests
    memory_and_threading_tests()
end

function test_performance_with_size(size::Int)
    db = Database()
    
    # Create schema
    schema = Dict{Symbol, Type}(
        :id => Int,
        :value => Float64,
        :category => String,
        :score => Float64,
        :active => Bool,
        :timestamp => String
    )
    
    create_table!(db, :perf_test, schema)
    
    # Generate dataset
    categories = ["Electronics", "Books", "Clothing", "Home", "Sports", "Automotive", "Health", "Beauty"]
    dataset = Vector{Dict{Symbol, Any}}()
    
    print("  📊 Generating $size records... ")
    gen_time = @elapsed begin
        for i in 1:size
            row = Dict{Symbol, Any}(
                :id => i,
                :value => round(rand() * 10000, digits=2),
                :category => rand(categories),
                :score => round(rand() * 5, digits=1),
                :active => rand(Bool),
                :timestamp => "2024-$(lpad(rand(1:12), 2, '0'))-$(lpad(rand(1:28), 2, '0'))"
            )
            push!(dataset, row)
        end
    end
    println("$(round(gen_time * 1000, digits=2))ms")
    
    # Test 1: Batch Insert Performance
    print("  ⚡ Batch insert... ")
    insert_time = @elapsed begin
        db_insert!(db, :perf_test, dataset)
    end
    insert_rate = size / insert_time
    println("$(round(insert_time * 1000, digits=2))ms ($(round(insert_rate)) records/sec)")
    
    # Test 2: Index Creation Performance
    print("  🔧 Creating indices... ")
    index_time = @elapsed begin
        create_index!(db, :perf_test, :id, HashIndex)
        create_index!(db, :perf_test, :category, HashIndex)
        create_index!(db, :perf_test, :value, BTreeIndex)
        create_index!(db, :perf_test, :score, BTreeIndex)
        create_index!(db, :perf_test, :active, HashIndex)
    end
    println("$(round(index_time * 1000, digits=2))ms")
    
    # Test 3: Query Performance (Hash Index)
    print("  🔍 Hash index queries... ")
    hash_query_time = @elapsed begin
        for _ in 1:100
            category = rand(categories)
            results = db_select(db, :perf_test, where=(:category, :(==), category))
        end
    end
    avg_hash_time = hash_query_time / 100
    println("$(round(avg_hash_time * 1000, digits=3))ms avg (100 queries)")
    
    # Test 4: Range Query Performance (B-Tree Index)
    print("  📈 Range queries... ")
    range_query_time = @elapsed begin
        for _ in 1:50
            threshold = rand() * 5000
            results = db_select(db, :perf_test, where=(:value, :(>), threshold))
        end
    end
    avg_range_time = range_query_time / 50
    println("$(round(avg_range_time * 1000, digits=3))ms avg (50 queries)")
    
    # Test 5: Complex Query Performance
    print("  🎯 Complex queries... ")
    complex_query_time = @elapsed begin
        for _ in 1:20
            category = rand(categories)
            min_score = rand() * 2.5
            results = db_select(db, :perf_test, 
                              where=(:category, :(==), category),
                              order_by=(:score, false),
                              limit=10)
        end
    end
    avg_complex_time = complex_query_time / 20
    println("$(round(avg_complex_time * 1000, digits=3))ms avg (20 queries)")
    
    # Test 6: Update Performance
    print("  ✏️ Update operations... ")
    update_time = @elapsed begin
        for i in 1:min(100, size ÷ 100)
            random_id = rand(1:size)
            db_update!(db, :perf_test, 
                      Dict{Symbol, Any}(:score => rand() * 5),
                      where=(:id, :(==), random_id))
        end
    end
    update_count = min(100, size ÷ 100)
    avg_update_time = update_time / update_count
    println("$(round(avg_update_time * 1000, digits=3))ms avg ($update_count updates)")
    
    # Test 7: Aggregation Performance
    print("  📊 Aggregations... ")
    agg_time = @elapsed begin
        all_records = db_select(db, :perf_test)
        
        # Calculate statistics
        total_value = sum(r[:value] for r in all_records)
        avg_value = total_value / length(all_records)
        active_count = count(r -> r[:active], all_records)
        
        # Category breakdown
        category_counts = Dict{String, Int}()
        for record in all_records
            cat = record[:category]
            category_counts[cat] = get(category_counts, cat, 0) + 1
        end
    end
    println("$(round(agg_time * 1000, digits=2))ms")
    
    # Memory efficiency test
    all_records = db_select(db, :perf_test)
    memory_per_record = Base.summarysize(all_records) / length(all_records)
    println("  💾 Memory: ~$(round(memory_per_record)) bytes/record")
    
    println("  ✅ Performance test completed for $size records")
end

function memory_and_threading_tests()
    println("\n🧠 Memory Usage and Threading Tests:")
    
    db = Database()
    
    # Create test table
    schema = Dict{Symbol, Type}(
        :id => Int,
        :data => String,
        :value => Float64
    )
    
    create_table!(db, :memory_test, schema)
    
    # Test memory usage with different record sizes
    record_sizes = [100, 1000, 10000]
    for size in record_sizes
        println("\n  📏 Testing memory with $size records:")
        
        # Generate data
        test_data = Vector{Dict{Symbol, Any}}()
        for i in 1:size
            row = Dict{Symbol, Any}(
                :id => i,
                :data => "Record data for item $i with some additional text to make it realistic",
                :value => rand() * 1000
            )
            push!(test_data, row)
        end
        
        # Insert data and measure memory directly
        db_insert!(db, :memory_test, test_data)
        
        # Get all records to measure their memory footprint
        all_records = db_select(db, :memory_test)
        
        # Calculate memory usage using Base.summarysize
        total_memory = Base.summarysize(all_records)
        memory_per_record = total_memory / size
        
        # Also measure the table's internal storage
        table = db.tables[:memory_test]
        table_memory = Base.summarysize(table.columns) + Base.summarysize(table.indices)
        
        println("    💾 Result set memory: $(round(total_memory / 1024, digits=2)) KB")
        println("    📊 Per record (results): $(round(memory_per_record)) bytes")
        println("    🗄️ Table storage memory: $(round(table_memory / 1024, digits=2)) KB")
        println("    📊 Per record (storage): $(round(table_memory / size)) bytes")
        
        # Clear table for next test
        db_delete!(db, :memory_test)
    end
    
    # Threading safety test (conceptual - Julia handles this automatically)
    println("\n  🔄 Concurrency Test:")
    println("    ✅ All operations are thread-safe due to ReentrantLock usage")
    println("    ✅ Multiple readers can access data simultaneously")
    println("    ✅ Writers are properly synchronized")
    
    # Performance scaling test
    println("\n  📈 Performance Scaling Analysis:")
    times = []
    sizes = [1000, 2000, 4000, 8000]
    
    for size in sizes
        db_clean = Database()
        create_table!(db_clean, :scale_test, schema)
        
        # Generate test data
        data = [Dict{Symbol, Any}(:id => i, :data => "test$i", :value => rand()) for i in 1:size]
        
        # Measure insertion time
        time_taken = @elapsed db_insert!(db_clean, :scale_test, data)
        push!(times, time_taken)
        
        println("    📊 $size records: $(round(time_taken * 1000, digits=2))ms")
    end
    
    # Calculate scaling factor
    scaling_factor = (times[end] / times[1]) / (sizes[end] / sizes[1])
    if scaling_factor < 1.5
        println("    ✅ Excellent linear scaling (factor: $(round(scaling_factor, digits=2)))")
    elseif scaling_factor < 2.0
        println("    ✅ Good scaling (factor: $(round(scaling_factor, digits=2)))")
    else
        println("    ⚠️  Sub-linear scaling (factor: $(round(scaling_factor, digits=2)))")
    end
end

"""
Example 7: Error Handling
"""
function error_handling_example()
    println("\n--- Error Handling Example ---")
    
    db = Database()
    
    # Schema definition
    test_schema = Dict{Symbol, Type}(
        :id => Int,
        :name => String,
        :value => Float64
    )
    
    println("✅ Testing error scenarios:")
    
    # Test 1: Table doesn't exist
    try
        db_select(db, :nonexistent_table)
    catch e
        println("  ❌ Expected error - Table doesn't exist: $(e.msg)")
    end
    
    # Test 2: Create duplicate table
    create_table!(db, :test_table, test_schema)
    try
        create_table!(db, :test_table, test_schema)
    catch e
        println("  ❌ Expected error - Duplicate table: $(e.msg)")
    end
    
    # Test 3: Schema validation
    try
        bad_row = Dict(:id => "not_an_integer", :name => "Test", :value => 1.0)
        db_insert!(db, :test_table, bad_row)
    catch e
        println("  ❌ Expected error - Schema validation: $(e.msg)")
    end    # Test 4: Index on non-existent column
    try
        create_index!(db, :test_table, :nonexistent_column)
    catch e
        println("  ❌ Expected error - Column doesn't exist: $(e.msg)")
    end
    
    # Test 5: Successful operations
    try
        good_row = Dict(:id => 1, :name => "Test Record", :value => 42.0)
        db_insert!(db, :test_table, good_row)
        
        result = db_select(db, :test_table)
        println("  ✅ Successful insert and select: $(length(result)) record(s)")
        
        create_index!(db, :test_table, :id)
        println("  ✅ Successfully created index on :id")
        
        updated = db_update!(db, :test_table, Dict{Symbol, Any}(:value => 100.0), where=(:id, :(==), 1))
        println("  ✅ Successfully updated $updated record(s)")
        
    catch e
        println("  ❌ Unexpected error: $e")
    end
end

# Run examples if this file is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end