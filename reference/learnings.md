# Learnings scratch pad

Low-friction dump for anything discovered mid-session that's worth keeping —
a gotcha, a working pattern, a class/file location, something that turned out
wrong in another reference file. Append here first; don't stop to figure out
which module doc it "really" belongs in.

Periodically (not every session) review this file and fold entries into the
right place in `smoke_test.md` / `source_index.md` / `case_setup.md`, then
delete them from here. An entry sitting here for a while isn't a problem.

Format: one entry per finding, dated, terse.

---

<!-- Example:
## 2026-08-04
Boundary condition `fixedFluxPressure` requires a companion velocity BC that
sets a flux-consistent value — using plain `zeroGradient` for U alongside it
silently gives wrong pressure at inflow/outflow patches in incompressible
solvers. Caught during pitzDaily smoke test.
-->
