#!/usr/bin/env bash
# Per-machine setup for the openfoam-v14 skill. Works for Claude Code and
# GitHub Copilot (VS Code / CLI). Safe to re-run.
#
# What it does:
#   1. Writes <skill_dir>/local.env (git-ignored) with OPENFOAM_DIR and RUN_DIR,
#      so no machine-specific path is ever committed.
#   2. Symlinks the skill into ~/.copilot/skills and ~/.claude/skills (the
#      latter only if Claude Code is present) so each tool discovers it.
#   3. Claude Code: merges no-prompt permissions into ~/.claude/settings.json
#      (read-only on the OpenFOAM install, read/write on the skill and run dirs).
#   4. Copilot / VS Code: writes a git-ignored openfoam.code-workspace that
#      includes the three directories, so they are in-workspace (no
#      out-of-workspace read prompts) when opened.
#
# Usage:
#   setup.sh [openfoam_install_dir] [run_dir]
#
# Defaults: OpenFOAM dir from $WM_PROJECT_DIR, else the first existing of
# ~/OpenFOAM/OpenFOAM-14, /opt/openfoam14; run dir from $FOAM_RUN, else
# ~/OpenFOAM/$USER-14.

set -euo pipefail

SKILL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

OPENFOAM_DIR="${1:-${WM_PROJECT_DIR:-}}"
if [ -z "$OPENFOAM_DIR" ]; then
  for c in "$HOME/OpenFOAM/OpenFOAM-14" /opt/openfoam14; do
    if [ -d "$c" ]; then OPENFOAM_DIR=$c; break; fi
  done
fi
if [ -z "$OPENFOAM_DIR" ]; then
  echo "Error: could not detect the OpenFOAM install dir." >&2
  echo "Usage: $0 <openfoam_install_dir> [run_dir]" >&2
  exit 1
fi
RUN_DIR="${2:-${FOAM_RUN:-$HOME/OpenFOAM/$(whoami)-14}}"

OPENFOAM_DIR=$(realpath -m "$OPENFOAM_DIR")
RUN_DIR=$(realpath -m "$RUN_DIR")

for d in "$OPENFOAM_DIR" "$RUN_DIR"; do
  if [ ! -d "$d" ]; then
    echo "Warning: $d does not exist yet — using it anyway." >&2
  fi
done

# 1. Machine-local config (git-ignored)
cat > "$SKILL_DIR/local.env" <<EOF
OPENFOAM_DIR=$OPENFOAM_DIR
RUN_DIR=$RUN_DIR
EOF
echo "Wrote $SKILL_DIR/local.env"

# 2. Make the skill discoverable
link_skill() {
  local skills_dir=$1 link="$1/openfoam-v14"
  mkdir -p "$skills_dir"
  if [ -L "$link" ]; then
    if [ "$(readlink "$link")" != "$SKILL_DIR" ]; then
      ln -sfn "$SKILL_DIR" "$link"
      echo "Repointed $link -> $SKILL_DIR"
    fi
  elif [ -e "$link" ]; then
    echo "Warning: $link exists and is not a symlink — left untouched." >&2
  else
    ln -s "$SKILL_DIR" "$link"
    echo "Linked $link -> $SKILL_DIR"
  fi
}

link_skill "$HOME/.copilot/skills"
HAVE_CLAUDE=0
if [ -d "$HOME/.claude" ] || command -v claude >/dev/null 2>&1; then
  HAVE_CLAUDE=1
  link_skill "$HOME/.claude/skills"
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Warning: python3 not found — skipping Claude permissions and workspace file." >&2
  exit 0
fi

# 3. Claude Code permissions
if [ "$HAVE_CLAUDE" = 1 ]; then
SETTINGS_FILE="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$SETTINGS_FILE")"

python3 - "$SETTINGS_FILE" "$OPENFOAM_DIR" "$SKILL_DIR" "$RUN_DIR" <<'PYEOF'
import json
import sys
import os

settings_file, openfoam_dir, skill_dir, run_dir = sys.argv[1:5]

if os.path.exists(settings_file):
    with open(settings_file) as f:
        content = f.read().strip()
        settings = json.loads(content) if content else {}
else:
    settings = {}

perms = settings.setdefault("permissions", {})
allow = perms.setdefault("allow", [])
add_dirs = perms.setdefault("additionalDirectories", [])

def add_unique(lst, items):
    for item in items:
        if item not in lst:
            lst.append(item)

# Read-only rules for the OpenFOAM install directory
readonly_rules = [
    f"Read(//{openfoam_dir.lstrip('/')}/**)",
    f"Grep(//{openfoam_dir.lstrip('/')}/**)",
    f"Glob(//{openfoam_dir.lstrip('/')}/**)",
    f"Bash(cat {openfoam_dir}/*)",
    f"Bash(ls {openfoam_dir}/*)",
    f"Bash(ls -la {openfoam_dir}/*)",
    f"Bash(find {openfoam_dir}*)",
    f"Bash(head {openfoam_dir}/*)",
    f"Bash(tail {openfoam_dir}/*)",
    f"Bash(wc {openfoam_dir}/*)",
    f"Bash(file {openfoam_dir}/*)",
    f"Bash(grep -r * {openfoam_dir}*)",
    f"Bash(grep -rl * {openfoam_dir}*)",
    f"Bash(grep -rn * {openfoam_dir}*)",
]

# Full read/write rules for a working directory (skill dir, run dir)
def readwrite_rules(path):
    p = path.lstrip('/')
    return [
        f"Read(//{p}/**)",
        f"Grep(//{p}/**)",
        f"Glob(//{p}/**)",
        f"Edit(//{p}/**)",
        f"Write(//{p}/**)",
        f"Bash(cd {path} && *)",
    ]

add_unique(allow, readonly_rules)
add_unique(allow, readwrite_rules(skill_dir))
add_unique(allow, readwrite_rules(run_dir))
add_unique(add_dirs, [openfoam_dir, skill_dir, run_dir])

with open(settings_file, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print(f"Updated {settings_file}")
PYEOF
fi

# 4. VS Code workspace for Copilot (git-ignored)
python3 - "$SKILL_DIR/openfoam.code-workspace" "$SKILL_DIR" "$OPENFOAM_DIR" "$RUN_DIR" <<'PYEOF'
import json
import sys

out, skill_dir, openfoam_dir, run_dir = sys.argv[1:5]
ws = {"folders": [
    {"name": "openfoam-skill", "path": skill_dir},
    {"name": "OpenFOAM install (read-only)", "path": openfoam_dir},
    {"name": "OpenFOAM runs", "path": run_dir},
]}
with open(out, "w") as f:
    json.dump(ws, f, indent=2)
    f.write("\n")
print(f"Wrote {out}")
PYEOF

echo
echo "OpenFOAM install: $OPENFOAM_DIR (read-only)"
echo "Run directory:    $RUN_DIR"
echo "Copilot: open openfoam.code-workspace in VS Code (or use --add-dir with the Copilot CLI)"
echo "         so the OpenFOAM source is readable without per-file prompts."
