using Test
using PALSJulia

# yaml_wrapper.jl symbols are not exported, so bring the ones used here into scope.
using PALSJulia: YAMLTree, YAMLNode, create_empty_tree,
  is_map, is_sequence, is_scalar,
  parse_string, parse_file,
  add_map!, add_sequence!, add_scalar!,
  set_scalar!, remove!,
  to_yaml_string, write_yaml,
  deep_copy_node!, deep_copy_children!

@testset "YAML Wrapper Tests" begin

  @testset "Node Creation" begin
    @testset "create_empty_tree returns a MAP root" begin
      root = create_empty_tree()
      @test root isa YAMLNode
      @test root.tree.handle != C_NULL
      @test is_map(root)
      @test length(root) == 0
    end

    @testset "add_map! and add_sequence! create typed children" begin
      root = create_empty_tree()
      m = add_map!(root, key="m")
      @test is_map(m)

      s = add_sequence!(root, key="s")
      @test is_sequence(s)
    end

    @testset "add_scalar! creates a scalar child" begin
      # Sequence elements are pure VAL nodes; keyed map entries are KEYVAL
      # and ryml's is_val() returns false for those — use a seq element.
      root = create_empty_tree()
      seq  = add_sequence!(root, key="items")
      sc   = add_scalar!(seq, "hello")
      @test is_scalar(sc)
      @test String(sc) == "hello"
    end

    @testset "Invalid tree handle throws" begin
      @test_throws ErrorException YAMLTree(C_NULL)
    end
  end

  @testset "Parsing" begin
    @testset "parse_string - map" begin
      yaml_str = """
            name: Alice
            age: 30
            active: true
            """
      node = parse_string(yaml_str)
      @test is_map(node)
      @test haskey(node, "name")
      @test haskey(node, "age")
      @test haskey(node, "active")
      @test String(node["name"]) == "Alice"
      @test Int(node["age"]) == 30
      @test Bool(node["active"]) == true
    end

    @testset "parse_string - sequence" begin
      yaml_str = "- item1\n- item2\n- item3\n"
      node = parse_string(yaml_str)
      @test is_sequence(node)
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
      node = parse_string(yaml_str)
      @test is_map(node)
      users = node["users"]
      @test is_sequence(users)
      @test length(users) == 2
      @test String(users[1]["name"]) == "Alice"
      @test Int(users[1]["age"]) == 30
    end

    @testset "parse_file - round trip" begin
      filename = tempname() * ".yaml"
      try
        write(filename, "x: 1\ny: 2\n")
        node = parse_file(filename)
        @test is_map(node)
        @test Int(node["x"]) == 1
        @test Int(node["y"]) == 2
      finally
        isfile(filename) && rm(filename)
      end
    end

    @testset "parse_file - missing file throws" begin
      @test_throws ErrorException parse_file("/nonexistent/path.yaml")
    end

    @testset "malformed YAML throws a pinpointed error, not a crash" begin
      # A sequence item missing its ':' is a syntax error. The C library used to
      # abort the whole process; it must now raise a catchable error whose
      # message names the offending line.
      err = try
        parse_string("- cav\n    kind: RFCavity\n"); nothing
      catch e
        sprint(showerror, e)
      end
      @test err !== nothing
      @test occursin("line", err)

      filename = tempname() * ".yaml"
      try
        write(filename, "a: 1\n  b: 2\n")
        @test_throws ErrorException parse_file(filename)
      finally
        isfile(filename) && rm(filename)
      end
    end
  end

  @testset "Type Checks" begin
    root   = parse_string("key: value")
    seq    = parse_string("- 1\n- 2\n- 3\n")
    scalar = seq[1]   # pure VAL node; map entries (KEYVAL) fail is_scalar

    @test is_scalar(scalar)
    @test !is_map(scalar)
    @test !is_sequence(scalar)

    @test is_map(root)
    @test !is_scalar(root)
    @test !is_sequence(root)

    @test is_sequence(seq)
    @test !is_scalar(seq)
    @test !is_map(seq)
  end

  @testset "Access Operations" begin
    @testset "Map access with getindex" begin
      node = parse_string("name: Alice\nage: 30")
      @test String(node["name"]) == "Alice"
      @test Int(node["age"]) == 30
    end

    @testset "Sequence access with getindex" begin
      node = parse_string("- 10\n- 20\n- 30\n")
      @test Int(node[1]) == 10
      @test Int(node[2]) == 20
      @test Int(node[3]) == 30
    end

    @testset "Key not found throws" begin
      node = parse_string("name: Alice")
      @test_throws ErrorException node["nonexistent"]
    end

    @testset "Index out of bounds throws" begin
      node = parse_string("- 1\n- 2\n- 3\n")
      @test_throws ErrorException node[10]
    end

    @testset "haskey" begin
      node = parse_string("name: Alice\nage: 30")
      @test haskey(node, "name")
      @test haskey(node, "age")
      @test !haskey(node, "nonexistent")
    end

    @testset "length" begin
      seq = parse_string("- 1\n- 2\n- 3\n- 4\n- 5\n")
      @test length(seq) == 5

      map = parse_string("a: 1\nb: 2\nc: 3")
      @test length(map) == 3
    end
  end

  @testset "Type Conversions" begin
    @testset "String conversion" begin
      node = parse_string("msg: hello world")
      @test String(node["msg"]) == "hello world"
    end

    @testset "Int conversion" begin
      node = parse_string("a: 42\nb: -100")
      @test Int(node["a"]) == 42
      @test Int(node["b"]) == -100
    end

    @testset "Float64 conversion" begin
      node = parse_string("x: 3.14159\ny: -2.5")
      @test Float64(node["x"]) ≈ 3.14159
      @test Float64(node["y"]) ≈ -2.5
    end

    @testset "Bool conversion" begin
      node = parse_string("t: true\nf: false")
      @test Bool(node["t"]) == true
      @test Bool(node["f"]) == false
    end
  end

  @testset "Modification Operations" begin
    @testset "setindex! adds and updates MAP entries" begin
      root = create_empty_tree()
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
      parent = create_empty_tree()
      child  = add_map!(parent, key="child")
      child["key"] = "value"

      @test is_map(parent["child"])
      @test String(parent["child"]["key"]) == "value"
    end

    @testset "set_scalar! updates an existing scalar" begin
      root = create_empty_tree()
      sc   = add_scalar!(root, "initial", key="val")
      set_scalar!(sc, "updated")
      @test String(sc) == "updated"

      set_scalar!(sc, "42")
      @test Int(sc) == 42

      set_scalar!(sc, "2.71828")
      @test Float64(sc) ≈ 2.71828

      set_scalar!(sc, "false")
      @test Bool(sc) == false
    end

    @testset "add_scalar! appends to sequences" begin
      root = create_empty_tree()
      seq  = add_sequence!(root, key="items")

      add_scalar!(seq, "item1")
      add_scalar!(seq, "item2")
      @test length(seq) == 2
      @test String(seq[1]) == "item1"
      @test String(seq[2]) == "item2"

      add_scalar!(seq, "10", index=1)   # insert at front
      @test String(seq[1]) == "10"
      @test length(seq) == 3
    end

    @testset "add_scalar! with numeric values (as strings)" begin
      root = create_empty_tree()
      seq  = add_sequence!(root, key="nums")

      add_scalar!(seq, "10")
      add_scalar!(seq, "20")
      @test Int(seq[1]) == 10
      @test Int(seq[2]) == 20

      add_scalar!(seq, "1.5")
      add_scalar!(seq, "2.5")
      @test Float64(seq[3]) ≈ 1.5
      @test Float64(seq[4]) ≈ 2.5
    end

    @testset "add_map! as sequence element" begin
      root = create_empty_tree()
      seq  = add_sequence!(root, key="records")
      elem = add_map!(seq)
      elem["key"] = "value"

      @test length(seq) == 1
      @test is_map(seq[1])
      @test String(seq[1]["key"]) == "value"
    end

    @testset "remove!" begin
      root = create_empty_tree()
      root["keep"]   = "yes"
      root["delete"] = "no"
      @test length(root) == 2

      remove!(root["delete"])
      @test length(root) == 1
      @test !haskey(root, "delete")
      @test haskey(root, "keep")
    end
  end

  @testset "Write and Emit Operations" begin
    @testset "to_yaml_string" begin
      node = parse_string("name: Alice\nage: 30")
      yaml_str = to_yaml_string(node)
      @test yaml_str isa String
      @test occursin("name", yaml_str)
      @test occursin("Alice", yaml_str)
      @test occursin("age", yaml_str)
      @test occursin("30", yaml_str)
    end

    @testset "to_yaml_string with exclude" begin
      node = parse_string("""
        lat:
          elements:
            - name: q1
              FloorP: {r: [1, 2, 3]}
              L: 0.5
              ReferenceP: {species: electron}
          ReferenceP: {pc: 1e9}
        """)

      yaml_str = to_yaml_string(node, exclude = ["FloorP", "ReferenceP"])
      @test !occursin("FloorP", yaml_str)
      @test !occursin("ReferenceP", yaml_str)
      @test !occursin("electron", yaml_str)   # the excluded subtrees go too
      @test occursin("q1", yaml_str)
      @test occursin("L", yaml_str)

      # A single key may be given as a bare string.
      yaml_str = to_yaml_string(node, exclude = "FloorP")
      @test !occursin("FloorP", yaml_str)
      @test occursin("ReferenceP", yaml_str)

      # The default and an empty exclude list are the unfiltered output, and the
      # node itself is never modified.
      @test to_yaml_string(node, exclude = String[]) == to_yaml_string(node)
      @test occursin("FloorP", to_yaml_string(node))
    end

    @testset "write_yaml with exclude" begin
      root = parse_string("""
        lat:
          elements:
            - name: q1
              FloorP: {r: [1, 2, 3]}
              L: 0.5
          ReferenceP: {pc: 1e9}
        other: stuff
        """)
      filename = tempname() * ".yaml"

      try
        # Writing from a non-root node still writes the whole tree.
        @test write_yaml(root["lat"], filename, exclude = ["FloorP", "ReferenceP"])
        text = read(filename, String)
        @test !occursin("FloorP", text)
        @test !occursin("ReferenceP", text)
        @test occursin("q1", text)
        @test occursin("other", text)

        # The tree in memory keeps everything.
        @test occursin("FloorP", to_yaml_string(root))
      finally
        isfile(filename) && rm(filename)
      end
    end

    @testset "write_yaml to file and read back" begin
      root = create_empty_tree()
      root["test"]  = "data"
      root["value"] = "123"
      filename = tempname() * ".yaml"

      try
        @test write_yaml(root, filename)
        @test isfile(filename)

        loaded = parse_file(filename)
        @test String(loaded["test"])  == "data"
        @test Int(loaded["value"]) == 123
      finally
        isfile(filename) && rm(filename)
      end
    end
  end

  @testset "Deep Copy" begin
    @testset "copy produces an independent duplicate" begin
      original = parse_string("name: Alice\nage: 30")
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
      src = parse_string("x: 10\ny: 20")
      dst = create_empty_tree()
      deep_copy_node!(dst, src)

      @test Int(dst["x"]) == 10
      @test Int(dst["y"]) == 20
    end

    @testset "deep_copy_children! copies children into existing node" begin
      src = parse_string("a: 1\nb: 2")
      dst = create_empty_tree()
      dst["existing"] = "yes"

      deep_copy_children!(dst, src)
      @test haskey(dst, "existing")
      @test haskey(dst, "a")
      @test haskey(dst, "b")
      @test Int(dst["a"]) == 1
    end

    @testset "deep_copy_children! honors an explicit index" begin
      src = parse_string("- a\n- b\n")          # children to graft in
      dst = parse_string("- x\n- y\n")          # existing sequence
      @test is_sequence(dst)

      deep_copy_children!(dst, src, index=1)    # insert at the front
      @test length(dst) == 4
      @test String(dst[1]) == "a"
      @test String(dst[2]) == "b"
      @test String(dst[3]) == "x"
      @test String(dst[4]) == "y"
    end
  end

  @testset "Base.show" begin
    map_node = parse_string("a: 1\nb: 2")
    seq_node = parse_string("- x\n- y\n")
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
      root  = create_empty_tree()
      users = add_sequence!(root, key="users")

      user1 = add_map!(users)
      user1["name"] = "Alice"
      s1 = add_sequence!(user1, key="scores")
      foreach(v -> add_scalar!(s1, v), ["90", "85", "92"])

      user2 = add_map!(users)
      user2["name"] = "Bob"
      s2 = add_sequence!(user2, key="scores")
      foreach(v -> add_scalar!(s2, v), ["88", "91", "87"])

      @test is_map(root)
      @test is_sequence(root["users"])
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
      node   = parse_string(yaml_str)
      config = node["config"]

      config["timeout"] = "60"
      config["status"]  = "enabled"

      @test Int(node["config"]["timeout"])    == 60
      @test String(node["config"]["status"])  == "enabled"
      @test Int(node["config"]["retries"])    == 3   # unchanged
    end

    @testset "Round-trip YAML through file" begin
      original = parse_string("""
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
        @test write_yaml(original, filename)
        loaded = parse_file(filename)

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
      empty_map = parse_string("{}")
      @test is_map(empty_map)
      @test length(empty_map) == 0

      empty_seq = parse_string("[]")
      @test is_sequence(empty_seq)
      @test length(empty_seq) == 0
    end

    @testset "Special string values" begin
      node = parse_string("text: \"true\"")   # quoted — stays a string
      @test String(node["text"]) == "true"

      node = parse_string("number: \"123\"")
      @test String(node["number"]) == "123"
    end

    @testset "Unicode strings" begin
      node = parse_string("greeting: こんにちは")
      @test String(node["greeting"]) == "こんにちは"

      node = parse_string("emoji: 🎉")
      @test String(node["emoji"]) == "🎉"
    end

    @testset "Multiline strings" begin
      yaml_str = """
            description: |
              This is a
              multiline
              string
            """
      node = parse_string(yaml_str)
      @test occursin("multiline", String(node["description"]))
    end
  end

end

println("\n✓ All tests completed!")