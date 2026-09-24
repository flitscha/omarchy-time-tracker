#!/usr/bin/env bash
# Links this checkout into the Omarchy plugin folder and puts the widget on
# the bar. Safe to run again.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="$HOME/.config/omarchy/plugins/felix.punchcard"

if [[ -e $target && ! -L $target ]]; then
  echo "$target exists and is not a link; move it away first." >&2
  exit 1
fi

mkdir -p "$(dirname "$target")"
ln -sfn "$repo" "$target"
echo "linked $target -> $repo"

omarchy-shell shell rescanPlugins >/dev/null
sleep 1
omarchy plugin enable felix.punchcard "$@"
omarchy restart shell >/dev/null 2>&1 &
echo "restarting the shell"
