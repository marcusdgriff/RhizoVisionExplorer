# Reproducible Release Build

This pipeline forces the same dependency stack and release CMake flags across macOS, Linux, and Windows.

## Pinned stack

- OpenCV `4.11.*`
- Qt `6.9.*` (`qt6-main`, `qt6-charts`)
- C++ standard `17`
- CMake build type `Release`
- `ENABLE_AVX512=OFF`
- `ENABLE_AVX2_FMA=ON` (automatically gated for non-x86 in CMake)

## Scripts

- macOS/Linux: `scripts/repro_release_build.sh`
- Windows: `scripts/repro_release_build.ps1`
- Shared conda environment: `scripts/repro-conda-env.yml`

## macOS/Linux example

```bash
bash scripts/repro_release_build.sh --clean
```

For strict parity with Windows/Linux numeric outputs on Apple Silicon, build macOS as `x86_64`:

```bash
bash scripts/repro_release_build.sh \
  --clean \
  --env-prefix "$HOME/.conda/envs/rhizovision-repro-x64" \
  --mac-arch x86_64
```

Notes:
- This mode uses `CONDA_SUBDIR=osx-64` and `CMAKE_OSX_ARCHITECTURES=x86_64`.
- Run the resulting binaries with Rosetta on Apple Silicon.

## Windows example

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\repro_release_build.ps1 -Clean
```

## Outputs

- Install prefix: `../_install/repro` (default)
- Build dirs: `build/repro/*`
- Repro manifest: `../_install/repro/repro-manifest.txt`
