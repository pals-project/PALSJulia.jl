# Installation

PALSParserJ is a Julia wrapper around the C library built by
[PALSParserCpp](https://github.com/pals-project/PALSParserCpp). That library is
compiled from that repository rather than shipped with this package, so
PALSParserJ has to be told where it is. By default it looks for a PALSParserCpp
checkout beside its own, which is the layout below; if you keep PALSParserCpp
somewhere else, see [Pointing at a PALSParserCpp
elsewhere](#pointing-at-a-palsparsercpp-elsewhere) instead.

macOS, Linux, and Windows are all supported — the correct library extension for
the platform (`.dylib`, `.so`, `.dll`) is worked out at load time.

## 1. Clone the repositories

```console
git clone https://github.com/pals-project/PALSParserCpp.git
git clone https://github.com/pals-project/PALSParserJ.jl.git
```

The default layout looks like this — PALSParserJ locates the compiled library
relative to its own source tree, at `../PALSParserCpp/build/`:

```text
some-directory/
├── PALSParserCpp/
│   └── build/
│       └── libPALSParserCpp.dylib   (or .so / .dll)
└── PALSParserJ/
```

## 2. Build the C library

From the `PALSParserCpp` directory, configure and build with CMake (this needs
CMake and a C++17 compiler — Apple Clang on macOS, GCC or Clang on Linux, MSVC
on Windows):

```console
cmake -S . -B build
cmake --build build
```

CMake fetches the [rapidyaml](https://github.com/biojppm/rapidyaml) backend
automatically. The result is the shared library `libPALSParserCpp.dylib`
(macOS), `.so` (Linux), or `.dll` (Windows) under `PALSParserCpp/build/`.
Rebuild with `cmake --build build` after changing any PALSParserCpp source. See
the PALSParserCpp `README` for more detail.

## 3. Activate the Julia project

From the `PALSParserJ` directory:

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()

import PALSParserJ as pj
```

## Check the installation

```julia
import PALSParserJ as pj

root = pj.create_empty_tree()
root["hello"] = "world"
println(pj.to_yaml_string(root))
```

If that prints `hello: world`, the Julia package and the underlying C library
are wired up correctly.

## Pointing at a PALSParserCpp elsewhere

The side-by-side layout is only the default. Two environment variables override
it, read the first time PALSParserJ calls into the library — so setting either
one any time before that first call works, including after `using PALSParserJ`:

| Variable | Meaning |
|---|---|
| `PALS_PARSER_CPP_DIR` | Path to a PALSParserCpp checkout; its `build/` directory is searched. |
| `PALS_PARSER_CPP_LIB` | Full path to the shared library itself, wherever it lives. |

```julia
ENV["PALS_PARSER_CPP_DIR"] = "/opt/src/PALSParserCpp"
using PALSParserJ
```

`PALS_PARSER_CPP_LIB` wins if both are set. `PALSParserJ.libparser()` returns
the resolved path, which is worth checking first if calls behave unexpectedly —
it is resolved per session rather than baked in when the package is precompiled,
so a stale precompile cache is never the cause.

If the library cannot be found, the first call fails with an error listing every
path that was tried, which is usually enough to spot a missing build or a typo
in the variable. Note that `using PALSParserJ` itself always succeeds: the
library is looked up lazily so that tooling which only reads the package — building
these docs, for one — does not need a C++ toolchain.
