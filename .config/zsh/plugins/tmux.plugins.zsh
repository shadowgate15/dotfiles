# Start a tmux session named after the current directory.
# Attach to the session if it already exists.
function tmux-dirname {
  # Get the base name of the current directory.
  # The ':t' modifier gets the tail of the path.
  local name="${PWD:t}"

  # Tmux rejects session names with periods or colons.
  # The '//[.:]/_' expansion replaces them with underscores.
  name="${name//[.:]/_}"

  # Pass -A to attach to an existing session or create a new one.
  # Pass -s to set the session name.
  # The '${name:-root}' syntax uses 'root' if the name is empty.
  # Pass -c to set the starting directory to $PWD.
  tmux new-session -A -s "${name:-root}" -c "$PWD"
}
