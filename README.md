# openfoam-v14 — an agent skill (Claude Code + GitHub Copilot)

An [Agent Skill](https://agentskills.io) (works with Claude Code and GitHub
Copilot in VS Code / CLI, in any chat mode that loads skills) for
working with an OpenFOAM v14 installation: setting up cases, smoke-testing
options before a full run, navigating the source tree, and building up
fvModel/case-setup knowledge over time instead of losing it at the end of
each chat.

It's a **pointer index, not a copy** of OpenFOAM's docs or source — `SKILL.md`
stays small and loads first; the `reference/*.md` files load only when a task
actually needs them, and always point back at the real source under the
OpenFOAM install rather than re-explaining it.

## Contents

| Path | Purpose |
|---|---|
| `SKILL.md` | The skill itself — trigger description + index, read by the agent |
| `reference/smoke_test.md` | Run 1–2 timesteps to sanity-check settings before a full run |
| `reference/source_index.md` | Map of the OpenFOAM v14 source tree (`src/`, `applications/`) |
| `reference/case_setup.md` | Case directory structure (`0/`, `constant/`, `system/`) |
| `reference/fv_models.md` | fvModel source terms (`semiImplicitSource`), `cellZone`/zoneGenerator |
| `reference/amr.md` | AMR (`fvMeshTopoChangers::refiner`/`hexRef8`) dict shape, the `empty`-patch corruption gotcha, and AMR-vs-parallel breakage |
| `reference/learnings.md` | Scratch pad — mid-session findings not yet triaged into a proper doc |
| `scripts/setup.sh` | One-shot setup for a new machine (see below) |
| `local.env`, `openfoam.code-workspace` | Generated per machine by `setup.sh`; git-ignored |

## Setup on a machine

Requires an OpenFOAM v14 install and `python3`. No machine-specific paths are
committed: docs use `<OPENFOAM_DIR>` / `<RUN_DIR>` placeholders, which the agent
resolves from the git-ignored `local.env` (or `$WM_PROJECT_DIR` / `$FOAM_RUN`).

```bash
git clone https://github.com/Souritra-Garai/FOAM-Skills.git openfoam-skill
cd openfoam-skill
./scripts/setup.sh [openfoam_install_dir] [run_dir]
```

Both arguments are optional: the install dir defaults to `$WM_PROJECT_DIR`
(or `~/OpenFOAM/OpenFOAM-14`, `/opt/openfoam14`) and the run dir to `$FOAM_RUN`
(or `~/OpenFOAM/$USER-14`). The script is safe to re-run and:

1. Writes `local.env` with the resolved paths.
2. Symlinks the skill into `~/.copilot/skills/openfoam-v14` (Copilot) and, if
   Claude Code is present, `~/.claude/skills/openfoam-v14`. VS Code Copilot
   reads both locations.
3. **Claude Code:** merges no-prompt permissions into `~/.claude/settings.json`
   (read-only on the OpenFOAM install, read/write on the skill and run dirs),
   leaving other settings untouched.
4. **Copilot:** writes `openfoam.code-workspace` (skill dir + OpenFOAM install +
   run dir). Open it in VS Code (`code openfoam.code-workspace`) and the OpenFOAM
   source counts as in-workspace, so Copilot can read it in any mode without
   out-of-workspace prompts. For the Copilot CLI, pass
   `--add-dir <OPENFOAM_DIR>` instead. Terminal commands (`grep`, `find`) are
   still governed by Copilot's `chat.tools.terminal.autoApprove` setting.

If your skill folder isn't picked up, make sure `chat.useAgentSkills` is
enabled in VS Code.

## Keeping it up to date

Mid-session, propose new findings into `reference/learnings.md` rather than
letting them evaporate at the end of the chat. Periodically triage that file:
fold small notes into the relevant existing reference doc, or — if an entry
is substantial and self-contained — give it its own reference file (see
`fv_models.md` for an example) and list it in `SKILL.md`.

Since this is a normal git repo, running `scripts/setup.sh` (or just a
plain `git pull`) on another machine picks up everything learned elsewhere.
