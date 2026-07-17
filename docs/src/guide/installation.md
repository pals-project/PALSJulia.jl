# Installation

PALSJulia is a Julia wrapper around the `yaml_c_wrapper` C library that ships
with [pals-cpp](https://github.com/pals-project/pals-cpp). The library is built
from that repository rather than shipped with this package, so PALSJulia has to
be told where it is. By default it looks for a pals-cpp checkout beside its own,
which is the layout below; if you keep pals-cpp somewhere else, see
[Pointing at a pals-cpp elsewhere](#pointing-at-a-pals-cpp-elsewhere) instead.

macOS, Linux, and Windows are all supported — the correct library extension for
the platform (`.dylib`, `.so`, `.dll`) is worked out at load time.

## 1. Clone the repositories

```console
git clone https://github.com/pals-project/pals-cpp.git
git clone https://github.com/pals-project/PALSJulia.git
```

The default layout looks like this — PALSJulia locates the compiled library
relative to its own source tree, at `../pals-cpp/build/`:

```text
some-directory/
├── pals-cpp/
│   └── build/
│       └── libyaml_c_wrapper.dylib   (or .so / .dll)
└── PALSJulia/
```

## 2. Build the C library

From the `pals-cpp` directory, configure and build with CMake (this needs CMake
and a C++17 compiler — Apple Clang on macOS, GCC or Clang on Linux, MSVC on
Windows):

```console
cmake -S . -B build
cmake --build build
```

CMake fetches the [rapidyaml](https://github.com/biojppm/rapidyaml) backend
automatically. The result is the shared library `libyaml_c_wrapper.dylib`
(macOS), `.so` (Linux), or `.dll` (Windows) under `pals-cpp/build/`. Rebuild
with `cmake --build build` after changing any pals-cpp source. See the pals-cpp
`README` for more detail.

## 3. Activate the Julia project

From the `PALSJulia` directory:

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()

import PALSJulia as pj
```

## Check the installation

```julia
import PALSJulia as pj

root = pj.create_empty_tree()
root["hello"] = "world"
println(pj.to_yaml_string(root))
```

If that prints `hello: world`, the Julia package and the underlying C library
are wired up correctly.

## Pointing at a pals-cpp elsewhere

The side-by-side layout is only the default. Two environment variables override
it, read when PALSJulia is loaded — set either one *before* `using PALSJulia`:

| Variable | Meaning |
|---|---|
| `PALS_CPP_DIR` | Path to a pals-cpp checkout; its `build/` directory is searched. |
| `PALS_CPP_LIB` | Full path to the shared library itself, wherever it lives. |

```julia
ENV["PALS_CPP_DIR"] = "/opt/src/pals-cpp"
using PALSJulia
```

`PALS_CPP_LIB` wins if both are set. The resolved path is available as
`PALSJulia.LIBYAML[]`, which is worth checking first if calls behave unexpectedly
— it is resolved per session rather than baked in when the package is
precompiled, so a stale precompile cache is never the cause.

If the library cannot be found, loading fails with an error listing every path
that was tried, which is usually enough to spot a missing build or a typo in the
variable.
