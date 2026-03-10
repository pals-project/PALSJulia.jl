using Test
import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
import pals_julia as pj

@testset "YAML Wrapper Tests" begin
    
    @testset "Node Creation" begin
        @testset "Create basic nodes" begin
            node = pj.create_node()
            @test node isa pj.YAMLNode
            @test node.handle != C_NULL
            
            map = pj.create_map()
            @test map isa pj.YAMLNode
            @test pj.is_map(map)
            
            seq = pj.create_sequence()
            @test seq isa pj.YAMLNode
            @test pj.is_sequence(seq)
            
            scalar = pj.create_scalar()
            @test scalar isa pj.YAMLNode
            @test pj.is_scalar(scalar)
        end
        
        @testset "Invalid handle errors" begin
            @test_throws ErrorException pj.YAMLNode(C_NULL)
        end
    end
    
    @testset "Parsing" begin
        @testset "Parse YAML string - scalar" begin
            node = pj.parse_yaml("hello")
            @test pj.is_scalar(node)
            @test String(node) == "hello"
        end
        
        @testset "Parse YAML string - map" begin
            yaml_str = """
            name: Alice
            age: 30
            active: true
            """
            node = pj.parse_yaml(yaml_str)
            @test pj.is_map(node)
            @test haskey(node, "name")
            @test haskey(node, "age")
            @test haskey(node, "active")
            @test String(node["name"]) == "Alice"
            @test Int(node["age"]) == 30
            @test Bool(node["active"]) == true
        end
        
        @testset "Parse YAML string - sequence" begin
            yaml_str = """
            - item1
            - item2
            - item3
            """
            node = pj.parse_yaml(yaml_str)
            @test pj.is_sequence(node)
            @test length(node) == 3
            @test String(node[1]) == "item1"
            @test String(node[2]) == "item2"
            @test String(node[3]) == "item3"
        end
        
        @testset "Parse YAML string - nested structure" begin
            yaml_str = """
            users:
              - name: Alice
                age: 30
              - name: Bob
                age: 25
            """
            node = pj.parse_yaml(yaml_str)
            @test pj.is_map(node)
            users = node["users"]
            @test pj.is_sequence(users)
            @test length(users) == 2
            @test String(users[1]["name"]) == "Alice"
            @test Int(users[1]["age"]) == 30
        end
    end
    
    @testset "Type Checks" begin
        scalar = pj.parse_yaml("42")
        map = pj.parse_yaml("key: value")
        seq = pj.parse_yaml("[1, 2, 3]")
        null_node = pj.parse_yaml("null")
        
        @test pj.is_scalar(scalar)
        @test !pj.is_map(scalar)
        @test !pj.is_sequence(scalar)
        
        @test pj.is_map(map)
        @test !pj.is_scalar(map)
        @test !pj.is_sequence(map)
        
        @test pj.is_sequence(seq)
        @test !pj.is_scalar(seq)
        @test !pj.is_map(seq)
        
        @test pj.is_null(null_node)
    end
    
    @testset "Access Operations" begin
        @testset "Map access with getindex" begin
            node = pj.parse_yaml("name: Alice\nage: 30")
            @test String(node["name"]) == "Alice"
            @test Int(node["age"]) == 30
        end
        
        @testset "Sequence access with getindex" begin
            node = pj.parse_yaml("[10, 20, 30]")
            @test Int(node[1]) == 10
            @test Int(node[2]) == 20
            @test Int(node[3]) == 30
        end
        
        @testset "Key not found error" begin
            node = pj.parse_yaml("name: Alice")
            @test_throws ErrorException node["nonexistent"]
        end
        
        @testset "Index out of bounds error" begin
            node = pj.parse_yaml("[1, 2, 3]")
            @test_throws ErrorException node[10]
        end
        
        @testset "haskey function" begin
            node = pj.parse_yaml("name: Alice\nage: 30")
            @test haskey(node, "name")
            @test haskey(node, "age")
            @test !haskey(node, "nonexistent")
        end
        
        @testset "length function" begin
            seq = pj.parse_yaml("[1, 2, 3, 4, 5]")
            @test length(seq) == 5
            
            map = pj.parse_yaml("a: 1\nb: 2\nc: 3")
            @test length(map) == 3
        end
    end
    
    @testset "Type Conversions" begin
        @testset "String conversion" begin
            node = pj.parse_yaml("hello world")
            @test String(node) == "hello world"
        end
        
        @testset "Int conversion" begin
            node = pj.parse_yaml("42")
            @test Int(node) == 42
            
            node = pj.parse_yaml("-100")
            @test Int(node) == -100
        end
        
        @testset "Float64 conversion" begin
            node = pj.parse_yaml("3.14159")
            @test Float64(node) ≈ 3.14159
            
            node = pj.parse_yaml("-2.5")
            @test Float64(node) ≈ -2.5
        end
        
        @testset "Bool conversion" begin
            node = pj.parse_yaml("true")
            @test Bool(node) == true
            
            node = pj.parse_yaml("false")
            @test Bool(node) == false
        end
    end
    
    @testset "Modification Operations" begin
        @testset "setvalue! for maps" begin
            map = pj.create_map()
            
            pj.setvalue!(map, "Alice", "name")
            @test String(map["name"]) == "Alice"
            
            pj.setvalue!(map, 30, "age")
            @test Int(map["age"]) == 30
            
            pj.setvalue!(map, 3.14, "pi")
            @test Float64(map["pi"]) ≈ 3.14
            
            pj.setvalue!(map, true, "active")
            @test Bool(map["active"]) == true
        end
        
        @testset "setvalue! with YAMLNode" begin
            parent = pj.create_map()
            child = pj.create_map()
            pj.setvalue!(child, "value", "key")
            pj.setvalue!(parent, child, "child")
            
            @test pj.is_map(parent["child"])
            @test String(parent["child"]["key"]) == "value"
        end
        
        @testset "set! for scalars" begin
            scalar = pj.create_scalar()
            
            pj.set!(scalar, "test string")
            @test String(scalar) == "test string"
            
            scalar = pj.create_scalar()
            pj.set!(scalar, 42)
            @test Int(scalar) == 42
            
            scalar = pj.create_scalar()
            pj.set!(scalar, 2.71828)
            @test Float64(scalar) ≈ 2.71828
            
            scalar = pj.create_scalar()
            pj.set!(scalar, false)
            @test Bool(scalar) == false
        end
        
        @testset "push! for sequences" begin
            seq = pj.create_sequence()
            
            push!(seq, "item1")
            push!(seq, "item2")
            @test length(seq) == 2
            @test String(seq[1]) == "item1"
            @test String(seq[2]) == "item2"
            
            seq = pj.create_sequence()
            push!(seq, 10)
            push!(seq, 20)
            @test Int(seq[1]) == 10
            @test Int(seq[2]) == 20
            
            seq = pj.create_sequence()
            push!(seq, 1.5)
            push!(seq, 2.5)
            @test Float64(seq[1]) ≈ 1.5
            @test Float64(seq[2]) ≈ 2.5
        end
        
        @testset "push! YAMLNode to sequence" begin
            seq = pj.create_sequence()
            child = pj.create_map()
            pj.setvalue!(child, "value", "key")
            push!(seq, child)
            
            @test length(seq) == 1
            @test pj.is_map(seq[1])
            @test String(seq[1]["key"]) == "value"
        end
        
        @testset "set_at_index!" begin
            seq = pj.create_sequence()
            push!(seq, "original")
            
            new_node = pj.create_scalar()
            pj.set!(new_node, "replaced")
            pj.set_at_index!(seq, 0, new_node)  # C uses 0-based indexing
            
            @test String(seq[1]) == "replaced"
        end
    end
    
    @testset "Write and Emit Operations" begin
        @testset "emit_yaml" begin
            node = pj.parse_yaml("name: Alice\nage: 30")
            yaml_str = pj.emit_yaml(node)
            @test occursin("name:", yaml_str)
            @test occursin("Alice", yaml_str)
            @test occursin("age:", yaml_str)
            @test occursin("30", yaml_str)
        end
        
        @testset "emit_yaml with custom indent" begin
            node = pj.parse_yaml("items:\n  - a\n  - b")
            yaml_str = pj.emit_yaml(node, indent=4)
            @test yaml_str isa String
        end
        
        @testset "to_yaml_string" begin
            node = pj.parse_yaml("key: value")
            yaml_str = pj.to_yaml_string(node)
            @test yaml_str isa String
            @test occursin("key", yaml_str)
            @test occursin("value", yaml_str)
        end
        
        @testset "write_yaml to file" begin
            node = pj.parse_yaml("test: data\nvalue: 123")
            filename = tempname() * ".yaml"
            
            try
                success = pj.write_yaml(node, filename)
                @test success
                @test isfile(filename)
                
                # Read it back and verify
                loaded = pj.parse_file(filename)
                @test String(loaded["test"]) == "data"
                @test Int(loaded["value"]) == 123
            finally
                isfile(filename) && rm(filename)
            end
        end
        
        @testset "write_yaml_advanced" begin
            node = pj.parse_yaml("active: true\nvalue: null\nname: test")
            filename = tempname() * ".yaml"
            
            try
                success = pj.write_yaml_advanced(
                    node, filename,
                    indent=2,
                    bool_format=:yesno,
                    null_format=:tilde,
                    string_format=:auto
                )
                @test success
                @test isfile(filename)
            finally
                isfile(filename) && rm(filename)
            end
        end
    end
    
    @testset "Utility Functions" begin
        @testset "clone" begin
            original = pj.parse_yaml("name: Alice\nage: 30")
            cloned = pj.clone(original)
            
            @test String(cloned["name"]) == "Alice"
            @test Int(cloned["age"]) == 30
            
            # Verify they're separate objects
            @test cloned.handle != original.handle
        end
        
        @testset "Base.show" begin
            node = pj.parse_yaml("test: value")
            io = IOBuffer()
            show(io, node)
            output = String(take!(io))
            @test output == "YAMLNode(...)"
        end
    end
    
    @testset "Complex Scenarios" begin
        @testset "Build complex nested structure" begin
            # Create: {users: [{name: Alice, scores: [90, 85, 92]}, {name: Bob, scores: [88, 91, 87]}]}
            root = pj.create_map()
            users = pj.create_sequence()
            
            # User 1
            user1 = pj.create_map()
            pj.setvalue!(user1, "Alice", "name")
            scores1 = pj.create_sequence()
            push!(scores1, 90)
            push!(scores1, 85)
            push!(scores1, 92)
            pj.setvalue!(user1, scores1, "scores")
            push!(users, user1)
            
            # User 2
            user2 = pj.create_map()
            pj.setvalue!(user2, "Bob", "name")
            scores2 = pj.create_sequence()
            push!(scores2, 88)
            push!(scores2, 91)
            push!(scores2, 87)
            pj.setvalue!(user2, scores2, "scores")
            push!(users, user2)
            
            pj.setvalue!(root, users, "users")
            
            # Verify structure
            @test pj.is_map(root)
            @test pj.is_sequence(root["users"])
            @test length(root["users"]) == 2
            @test String(root["users"][1]["name"]) == "Alice"
            @test length(root["users"][1]["scores"]) == 3
            @test Int(root["users"][1]["scores"][1]) == 90
        end
        
        @testset "Parse and modify existing YAML" begin
            yaml_str = """
            config:
              timeout: 30
              retries: 3
            """
            node = pj.parse_yaml(yaml_str)
            
            # Modify existing values
            config = node["config"]
            pj.setvalue!(config, 60, "timeout")
            pj.setvalue!(config, "enabled", "status")
            
            @test Int(node["config"]["timeout"]) == 60
            @test String(node["config"]["status"]) == "enabled"
        end
        
        @testset "Round-trip YAML through file" begin
            # Create complex structure
            original = pj.parse_yaml("""
            application:
              name: MyApp
              version: 1.0.0
              features:
                - authentication
                - logging
                - caching
              settings:
                debug: true
                port: 8080
            """)
            
            filename = tempname() * ".yaml"
            
            try
                # Write to file
                @test pj.write_yaml(original, filename)
                
                # Read back
                loaded = pj.parse_file(filename)
                
                # Verify structure preserved
                @test String(loaded["application"]["name"]) == "MyApp"
                @test String(loaded["application"]["version"]) == "1.0.0"
                @test length(loaded["application"]["features"]) == 3
                @test String(loaded["application"]["features"][1]) == "authentication"
                @test Bool(loaded["application"]["settings"]["debug"]) == true
                @test Int(loaded["application"]["settings"]["port"]) == 8080
            finally
                isfile(filename) && rm(filename)
            end
        end
    end
    
    @testset "Edge Cases" begin
        @testset "Empty structures" begin
            empty_map = pj.parse_yaml("{}")
            @test pj.is_map(empty_map)
            @test length(empty_map) == 0
            
            empty_seq = pj.parse_yaml("[]")
            @test pj.is_sequence(empty_seq)
            @test length(empty_seq) == 0
        end
        
        @testset "Special string values" begin
            node = pj.parse_yaml("text: \"true\"")  # String "true", not boolean
            @test String(node["text"]) == "true"
            
            node = pj.parse_yaml("number: \"123\"")  # String "123", not integer
            @test String(node["number"]) == "123"
        end
        
        @testset "Unicode strings" begin
            node = pj.parse_yaml("greeting: こんにちは")
            @test String(node["greeting"]) == "こんにちは"
            
            node = pj.parse_yaml("emoji: 🎉")
            @test String(node["emoji"]) == "🎉"
        end
        
        @testset "Multiline strings" begin
            yaml_str = """
            description: |
              This is a
              multiline
              string
            """
            node = pj.parse_yaml(yaml_str)
            desc = String(node["description"])
            @test occursin("multiline", desc)
        end
    end
end

println("\n✓ All tests completed!")