#!/usr/bin/env bash
# Run the headless integration test in a throwaway project directory.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

printf 'return {}\n' > "$workdir/prova.lua"

cd "$workdir"
REPO_ROOT="$repo_root" nvim --headless -u NONE prova.lua \
	-c "luafile $repo_root/tests/integration.lua" \
	-c 'qa!'
