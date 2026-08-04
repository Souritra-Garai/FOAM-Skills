# OpenFOAM v14 case directory structure

Verified against `/opt/openfoam14/tutorials/incompressibleFluid/planarCouette`
(a minimal v14 case). Structure may vary by module — cross-check against a
tutorial under `applications/modules/<name>`'s matching `tutorials/<name>`
directory before assuming a file is required/optional for a given solver.

## Minimal viable case

```
caseDir/
├── 0/                          # initial field values (time = 0 directory)
│   ├── U                       # velocity field + boundary conditions
│   ├── p                       # pressure field + boundary conditions
│   └── ...                     # one file per solved field
├── constant/
│   ├── physicalProperties      # transport model, viscosity, density
│   └── momentumTransport       # laminar/RAS/LES selection (replaces
│                                # older `turbulenceProperties`)
└── system/
    ├── controlDict              # application/solver, time control, write control
    ├── blockMeshDict             # base mesh definition (if not using an external mesh)
    ├── fvSchemes                 # discretization schemes (ddt, grad, div, laplacian)
    └── fvSolution                 # linear solvers, algorithm control (SIMPLE/PIMPLE), relaxation
```

## Per-file responsibility

| File | Controls |
|---|---|
| `0/<field>` | Initial value + per-patch boundary condition type/value for that field |
| `constant/physicalProperties` | Fluid/solid properties: viscosity, density, transport model type |
| `constant/momentumTransport` | Turbulence modeling choice (`laminar`, `RAS`, `LES`) and model-specific coefficients |
| `constant/polyMesh` | Written by `blockMesh`/mesh converters — not hand-edited directly |
| `system/controlDict` | Which solver (`application`) or module (`foamRun -solver <module>`), `startTime`/`endTime`/`deltaT`, `writeInterval`, function objects |
| `system/blockMeshDict` | Vertices/blocks/edges defining the base hex mesh, or the source geometry for `snappyHexMesh` |
| `system/snappyHexMeshDict` | Surface refinement/snapping settings when meshing from an STL/geometry |
| `system/fvSchemes` | Numerical scheme choice per term (time derivative, gradient, divergence, Laplacian, interpolation) |
| `system/fvSolution` | Linear solver + tolerance per field, SIMPLE/PIMPLE algorithm settings, under-relaxation factors |

## Checklist for a new case

1. Pick the module/solver: check `applications/modules` (v14's `foamRun`
   modules) or `applications/solvers` for legacy standalone binaries — see
   `source_index.md`.
2. Find the closest matching tutorial under `tutorials/<moduleName>/` and
   copy its structure rather than building from scratch.
3. Confirm every field referenced in `constant/` and `system/` has a matching
   `0/<field>` file with boundary conditions for every mesh patch.
4. Before a full run, smoke-test per `smoke_test.md`.
