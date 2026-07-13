# Installation

PALSJulia is a Julia wrapper around the `yaml_c_wrapper` C library that ships
with [pals-cpp](https://github.com/pals-project/pals-cpp), so both repositories
must be cloned side by side under the same parent directory.

## 1. Clone the repositories

```console
git clone https://github.com/pals-project/pals-cpp.git
git clone https://github.com/pals-project/PALSJulia.git
```

The resulting layout must look like this — PALSJulia locates the compiled
library relative to its own source tree, at `../pals-cpp/build/`:

```text
some-directory/
├── pals-cpp/
│   └── build/
│       └── libyaml_c_wrapper.dylib   (or .so / .dll)
└── PALSJulia/
```

## 2. Build the C library

From the `pals-cpp` directory, configure and build with CMake (this needs CMake
and a C++17 compiler — Apple Clang on macOS, GCC or Clang on Linux):

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
