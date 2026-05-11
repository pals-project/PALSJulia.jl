using Test
import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
import pals_julia as pj

@testset "YAML Wrapper Tests" begin

    @testset "Node Creation" begin
        @testset "create_empty_tree returns a MAP root" begin
            root = pj.create_empty_tree()
            @test root isa pj.YAMLNode
            @test root.tree.handle != C_NULL
            @test pj.is_map(root)
            @test length(root) == 0
        end

        @testset "add_map! and add_sequence! create typed children" begin
            root = pj.create_empty_tree()
            m = pj.add_map!(root, key="m")
            @test pj.is_map(m)

            s = pj.add_sequence!(root, key="s")
            @test pj.is_sequence(s)
        end

        @testset "add_scalar! creates a scalar child" begin
            # Sequence elements are pure VAL nodes; keyed map entries are KEYVAL
            # and ryml's is_val() returns false for those — use a seq element.
            root = pj.create_empty_tree()
            seq  = pj.add_sequence!(root, key="items")
            sc   = pj.add_scalar!(seq, "hello")
            @test pj.is_scalar(sc)
            @test String(sc) == "hello"
        end

        @testset "Invalid tree handle throws" begin
            @test_throws ErrorException pj.YAMLTree(C_NULL)
        end
    end

    @testset "Parsing" begin
        @testset "parse_string - map" begin
            yaml_str = """
            name: Alice
            age: 30
            active: true
            """
            node = pj.parse_string(yaml_str)
            @test pj.is_map(node)
            @test haskey(node, "name")
            @test haskey(node, "age")
            @test haskey(node, "active")
            @test String(node["name"]) == "Alice"
            @test Int(node["age"]) == 30
            @test Bool(node["active"]) == true
        end

        @testset "parse_string - sequence" begin
            yaml_str = "- item1\n- item2\n- item3\n"
            node = pj.parse_string(yaml_str)
            @test pj.is_sequence(node)
            @test length(node) == 3
            @test String(node[1]) == "item1"
            @test String(node[2]) == "item2"
            @test String(node[3]) == "item3"
        end

        @testset "parse_string - nested structure" begin
            yaml_str = """
            users:
              - name: Alice
                age: 30
              - name: Bob
                age: 25
            """
            node = pj.parse_string(yaml_str)
            @test pj.is_map(node)
            users = node["users"]
            @test pj.is_sequence(users)
            @test length(users) == 2
            @test String(users[1]["name"]) == "Alice"
            @test Int(users[1]["age"]) == 30
        end

        @testset "parse_file - round trip" begin
            filename = tempname() * ".yaml"
            try
                write(filename, "x: 1\ny: 2\n")
                node = pj.parse_file(filename)
                @test pj.is_map(node)
                @test Int(node["x"]) == 1
                @test Int(node["y"]) == 2
            finally
                isfile(filename) && rm(filename)
            end
        end

        @testset "parse_file - missing file throws" begin
            @test_throws ErrorException pj.parse_file("/nonexistent/path.yaml")
        end
    end

    @testset "Type Checks" begin
        root   = pj.parse_string("key: value")
        seq    = pj.parse_string("- 1\n- 2\n- 3\n")
        scalar = seq[1]   # pure VAL node; map entries (KEYVAL) fail is_scalar

        @test pj.is_scalar(scalar)
        @test !pj.is_map(scalar)
        @test !pj.is_sequence(scalar)

        @test pj.is_map(root)
        @test !pj.is_scalar(root)
        @test !pj.is_sequence(root)

        @test pj.is_sequence(seq)
        @test !pj.is_scalar(seq)
        @test !pj.is_map(seq)
    end

    @testset "Access Operations" begin
        @testset "Map access with getindex" begin
            node = pj.parse_string("name: Alice\nage: 30")
            @test String(node["name"]) == "Alice"
            @test Int(node["age"]) == 30
        end

        @testset "Sequence access with getindex" begin
            node = pj.parse_string("- 10\n- 20\n- 30\n")
            @test Int(node[1]) == 10
            @test Int(node[2]) == 20
            @test Int(node[3]) == 30
        end

        @testset "Key not found throws" begin
            node = pj.parse_string("name: Alice")
            @test_throws ErrorException node["nonexistent"]
        end

        @testset "Index out of bounds throws" begin
            node = pj.parse_string("- 1\n- 2\n- 3\n")
            @test_throws ErrorException node[10]
        end

        @testset "haskey" begin
            node = pj.parse_string("name: Alice\nage: 30")
            @test haskey(node, "name")
            @test haskey(node, "age")
            @test !haskey(node, "nonexistent")
        end

        @testset "length" begin
            seq = pj.parse_string("- 1\n- 2\n- 3\n- 4\n- 5\n")
            @test length(seq) == 5

            map = pj.parse_string("a: 1\nb: 2\nc: 3")
            @test length(map) == 3
        end
    end

    @testset "Type Conversions" begin
        @testset "String conversion" begin
            node = pj.parse_string("msg: hello world")
            @test String(node["msg"]) == "hello world"
        end

        @testset "Int conversion" begin
            node = pj.parse_string("a: 42\nb: -100")
            @test Int(node["a"]) == 42
            @test Int(node["b"]) == -100
        end

        @testset "Float64 conversion" begin
            node = pj.parse_string("x: 3.14159\ny: -2.5")
            @test Float64(node["x"]) ≈ 3.14159
            @test Float64(node["y"]) ≈ -2.5
        end

        @testset "Bool conversion" begin
            node = pj.parse_string("t: true\nf: false")
            @test Bool(node["t"]) == true
            @test Bool(node["f"]) == false
        end
    end

    @testset "Modification Operations" begin
        @testset "setindex! adds and updates MAP entries" begin
            root = pj.create_empty_tree()
            root["name"]   = "Alice"
            root["age"]    = "30"
            root["pi"]     = "3.14"
            root["active"] = "true"

            @test String(root["name"])   == "Alice"
            @test Int(root["age"])       == 30
            @test Float64(root["pi"])    ≈ 3.14
            @test Bool(root["active"])   == true

            # Update existing key
            root["age"] = "31"
            @test Int(root["age"]) == 31
        end

        @testset "add_map! as child of MAP" begin
            parent = pj.create_empty_tree()
            child  = pj.add_map!(parent, key="child")
            child["key"] = "value"

            @test pj.is_map(parent["child"])
            @test String(parent["child"]["key"]) == "value"
        end

        @testset "set_scalar! updates an existing scalar" begin
            root = pj.create_empty_tree()
            sc   = pj.add_scalar!(root, "initial", key="val")
            pj.set_scalar!(sc, "updated")
            @test String(sc) == "updated"

            pj.set_scalar!(sc, "42")
            @test Int(sc) == 42

            pj.set_scalar!(sc, "2.71828")
            @test Float64(sc) ≈ 2.71828

            pj.set_scalar!(sc, "false")
            @test Bool(sc) == false
        end

        @testset "add_scalar! appends to sequences" begin
            root = pj.create_empty_tree()
            seq  = pj.add_sequence!(root, key="items")

            pj.add_scalar!(seq, "item1")
            pj.add_scalar!(seq, "item2")
            @test length(seq) == 2
            @test String(seq[1]) == "item1"
            @test String(seq[2]) == "item2"

            pj.add_scalar!(seq, "10", index=1)   # insert at front
            @test String(seq[1]) == "10"
            @test length(seq) == 3
        end

        @testset "add_scalar! with numeric values (as strings)" begin
            root = pj.create_empty_tree()
            seq  = pj.add_sequence!(root, key="nums")

            pj.add_scalar!(seq, "10")
            pj.add_scalar!(seq, "20")
            @test Int(seq[1]) == 10
            @test Int(seq[2]) == 20

            pj.add_scalar!(seq, "1.5")
            pj.add_scalar!(seq, "2.5")
            @test Float64(seq[3]) ≈ 1.5
            @test Float64(seq[4]) ≈ 2.5
        end

        @testset "add_map! as sequence element" begin
            root = pj.create_empty_tree()
            seq  = pj.add_sequence!(root, key="records")
            elem = pj.add_map!(seq)
            elem["key"] = "value"

            @test length(seq) == 1
            @test pj.is_map(seq[1])
            @test String(seq[1]["key"]) == "value"
        end

        @testset "remove!" begin
            root = pj.create_empty_tree()
            root["keep"]   = "yes"
            root["delete"] = "no"
            @test length(root) == 2

            pj.remove!(root["delete"])
            @test length(root) == 1
            @test !haskey(root, "delete")
            @test haskey(root, "keep")
        end
    end

    @testset "Write and Emit Operations" begin
        @testset "to_yaml_string" begin
            node = pj.parse_string("name: Alice\nage: 30")
            yaml_str = pj.to_yaml_string(node)
            @test yaml_str isa String
            @test occursin("name", yaml_str)
            @test occursin("Alice", yaml_str)
            @test occursin("age", yaml_str)
            @test occursin("30", yaml_str)
        end

        @testset "write_yaml to file and read back" begin
            root = pj.create_empty_tree()
            root["test"]  = "data"
            root["value"] = "123"
            filename = tempname() * ".yaml"

            try
                @test pj.write_yaml(root, filename)
                @test isfile(filename)

                loaded = pj.parse_file(filename)
                @test String(loaded["test"])  == "data"
                @test Int(loaded["value"]) == 123
            finally
                isfile(filename) && rm(filename)
            end
        end
    end

    @testset "Deep Copy" begin
        @testset "copy produces an independent duplicate" begin
            original = pj.parse_string("name: Alice\nage: 30")
            cloned   = copy(original)

            @test String(cloned["name"]) == "Alice"
            @test Int(cloned["age"])     == 30

            # Mutating the clone must not affect the original
            cloned["name"] = "Bob"
            @test String(cloned["name"])   == "Bob"
            @test String(original["name"]) == "Alice"

            # Trees are independent objects
            @test cloned.tree.handle != original.tree.handle
        end

        @testset "deep_copy_node! copies content into existing node" begin
            src = pj.parse_string("x: 10\ny: 20")
            dst = pj.create_empty_tree()
            pj.deep_copy_node!(dst, src)

            @test Int(dst["x"]) == 10
            @test Int(dst["y"]) == 20
        end

        @testset "deep_copy_children! copies children into existing node" begin
            src = pj.parse_string("a: 1\nb: 2")
            dst = pj.create_empty_tree()
            dst["existing"] = "yes"

            pj.deep_copy_children!(dst, src)
            @test haskey(dst, "existing")
            @test haskey(dst, "a")
            @test haskey(dst, "b")
            @test Int(dst["a"]) == 1
        end
    end

    @testset "Base.show" begin
        map_node = pj.parse_string("a: 1\nb: 2")
        seq_node = pj.parse_string("- x\n- y\n")
        scalar   = seq_node[1]   # pure VAL node

        io = IOBuffer()
        show(io, map_node); @test occursin("map",      String(take!(io)))
        show(io, seq_node); @test occursin("sequence", String(take!(io)))
        show(io, scalar);   @test occursin("scalar",   String(take!(io)))
    end

    @testset "Complex Scenarios" begin
        @testset "Build nested structure programmatically" begin
            # {users: [{name: Alice, scores: [90, 85, 92]},
            #          {name: Bob,   scores: [88, 91, 87]}]}
            root  = pj.create_empty_tree()
            users = pj.add_sequence!(root, key="users")

            user1 = pj.add_map!(users)
            user1["name"] = "Alice"
            s1 = pj.add_sequence!(user1, key="scores")
            foreach(v -> pj.add_scalar!(s1, v), ["90", "85", "92"])

            user2 = pj.add_map!(users)
            user2["name"] = "Bob"
            s2 = pj.add_sequence!(user2, key="scores")
            foreach(v -> pj.add_scalar!(s2, v), ["88", "91", "87"])

            @test pj.is_map(root)
            @test pj.is_sequence(root["users"])
            @test length(root["users"]) == 2
            @test String(root["users"][1]["name"])     == "Alice"
            @test length(root["users"][1]["scores"])   == 3
            @test Int(root["users"][1]["scores"][1])   == 90
        end

        @testset "Parse and modify existing YAML" begin
            yaml_str = """
            config:
              timeout: 30
              retries: 3
            """
            node   = pj.parse_string(yaml_str)
            config = node["config"]

            config["timeout"] = "60"
            config["status"]  = "enabled"

            @test Int(node["config"]["timeout"])    == 60
            @test String(node["config"]["status"])  == "enabled"
            @test Int(node["config"]["retries"])    == 3   # unchanged
        end

        @testset "Round-trip YAML through file" begin
            original = pj.parse_string("""
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
                @test pj.write_yaml(original, filename)
                loaded = pj.parse_file(filename)

                @test String(loaded["application"]["name"])        == "MyApp"
                @test String(loaded["application"]["version"])     == "1.0.0"
                @test length(loaded["application"]["features"])    == 3
                @test String(loaded["application"]["features"][1]) == "authentication"
                @test Bool(loaded["application"]["settings"]["debug"]) == true
                @test Int(loaded["application"]["settings"]["port"])   == 8080
            finally
                isfile(filename) && rm(filename)
            end
        end
    end

    @testset "Edge Cases" begin
        @testset "Empty structures" begin
            empty_map = pj.parse_string("{}")
            @test pj.is_map(empty_map)
            @test length(empty_map) == 0

            empty_seq = pj.parse_string("[]")
            @test pj.is_sequence(empty_seq)
            @test length(empty_seq) == 0
        end

        @testset "Special string values" begin
            node = pj.parse_string("text: \"true\"")   # quoted — stays a string
            @test String(node["text"]) == "true"

            node = pj.parse_string("number: \"123\"")
            @test String(node["number"]) == "123"
        end

        @testset "Unicode strings" begin
            node = pj.parse_string("greeting: こんにちは")
            @test String(node["greeting"]) == "こんにちは"

            node = pj.parse_string("emoji: 🎉")
            @test String(node["emoji"]) == "🎉"
        end

        @testset "Multiline strings" begin
            yaml_str = """
            description: |
              This is a
              multiline
              string
            """
            node = pj.parse_string(yaml_str)
            @test occursin("multiline", String(node["description"]))
        end
    end

end

println("\n✓ All tests completed!")