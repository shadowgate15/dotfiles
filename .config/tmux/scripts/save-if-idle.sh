#!/usr/bin/env bash
# Save tmux-resurrect state unless a restore is still pending or running,
# so half-built (still-in-$HOME) panes never overwrite the good save.
[ "$(tmux show -gv @restoring 2>/dev/null)" = "1" ] && exit 0
exec "$HOME/.config/tmux/plugins/tmux-resurrect/scripts/save.sh" quiet
