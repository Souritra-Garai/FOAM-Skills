---
name: openfoam-v14
description: Helps set up, smoke-test, and validate OpenFOAM v14 cases and dictionary entries, and navigate the OpenFOAM v14 source tree (installed at /opt/openfoam14). Use when the user is working with OpenFOAM case files (controlDict, fvSchemes, fvSolution, boundary conditions, fvModels), wants to quickly check that a solver/option/dictionary entry works before a full run, or asks about OpenFOAM source structure.
---

# OpenFOAM v14 Skill

Local install: `/opt/openfoam14`. User run directory: `~/OpenFOAM/sgarai-14`.

## Setup on a new machine

Run `scripts/setup-permissions.sh <openfoam_install_dir> <skill_dir> <run_dir>`
once to merge no-prompt Claude Code permissions into `~/.claude/settings.json`:
read-only on the OpenFOAM install dir, full read/write on the skill dir and
the run dir. Safe to re-run; merges without touching unrelated settings.

This skill is a pointer index, not a copy of OpenFOAM's docs or source. Read the
relevant reference file below only when the task needs it — don't load all of them.

## Reference files (load on demand)

- `reference/smoke_test.md` — run 1-2 timesteps of a case to sanity-check that
  settings/options work, without committing to a full run. Covers both a
  full-pipeline smoke test (patch controlDict, run, restore) and a narrower
  single-entry check (validate one dictionary entry in isolation).
- `reference/source_index.md` — map of `/opt/openfoam14/src` and `applications`
  modules: what's where, key header files, how to search the source for a class
  or boundary condition.
- `reference/case_setup.md` — case directory structure (0/, constant/, system/),
  what each file controls, minimal viable case checklist.
- `reference/fv_models.md` — fvModel source terms (`semiImplicitSource`
  math/dimensions, Su-only vs. Sp-relaxation forcing behavior) and the v14
  `cellZone`/zoneGenerator mechanism.
- `reference/amr.md` — `fvMeshTopoChangers::refiner` (hexRef8) AMR dict
  shape, toggling it off without losing the config, the `empty`-patch
  corruption gotcha and its `cyclic`-patch workaround, and why AMR + a
  decomposed (parallel) run crashes when that workaround is in play.
- `reference/learnings.md` — scratch pad of things learned mid-session, not
  yet triaged into the files above.

## Workflow

1. Identify which reference file(s) the current task needs; read only those.
2. For smoke-test / "does this option work" requests, follow `smoke_test.md`
   exactly — it includes the restore step so the user's real case isn't left
   in a patched state.
3. For source-structure questions, use `source_index.md` as a map, then grep
   the actual source under `/opt/openfoam14` rather than guessing class names.
4. When new, reusable knowledge is learned during a session (a gotcha, a class
   location, a working pattern), propose appending it to `reference/learnings.md`
   with today's date rather than losing it — don't stop to figure out which
   module doc it belongs in. That triage happens later, separately.
5. When triaging `learnings.md`: if an entry is substantial and self-contained
   enough to be its own topic (like `fv_models.md`), give it a new reference
   file rather than forcing it into an existing one — then list it above.
