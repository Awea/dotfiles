#!/usr/bin/env bash
# SessionStart hook: make "user-invocable-only" in skillOverrides work for plugin entries.
#
# Claude Code 2.1.326 applies skillOverrides to bundled and user skills, but not to the
# commands and skills of a plugin: they stay in the skill listing of each session. The
# frontmatter line `disable-model-invocation: true` hides them and keeps the /command.
# This hook adds that line to each plugin entry set to "user-invocable-only", in each
# installed version. The plugin cache is a copy: an update brings back the plugin files,
# and the next session start patches them again. The session of that start still lists
# them. Other values ("off", "name-only") are not handled.
#
# Limits: it reads only $CLAUDE_CONFIG_DIR/settings.json (not settings.local.json). It looks
# only in the default places commands/<name>.md, skills/<name>/SKILL.md and the root
# SKILL.md, not in custom paths of a plugin.json. It writes only regular files under
# plugins/cache, never through a symlink. It skips a file with CRLF line ends.
#
# Output: none on stdout, because SessionStart stdout goes into the context.
# Runs on Linux and macOS (bash 3.2, no GNU-only sed or stat).

claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
settings="$claude_dir/settings.json"
installed="$claude_dir/plugins/installed_plugins.json"

[ -f "$settings" ] && [ -f "$installed" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Exit 0 when the file has frontmatter with no disable-model-invocation key.
needs_patch() {
  awk '
    NR == 1 { if ($0 != "---") exit 1; next }
    $0 == "---" { exit 0 }
    /^disable-model-invocation:/ { exit 1 }
    END { if (NR < 2) exit 1 }
  ' "$1"
}

# Print the name: value of the frontmatter.
front_name() {
  awk 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit }
    /^name:/ { sub(/^name:[ \t]*/, ""); gsub(/^["\047]|["\047 \t]+$/, ""); print; exit }' "$1"
}

patch() {
  local file=$1 tmp
  [ -L "$file" ] && return 0
  needs_patch "$file" || return 0
  tmp=$(mktemp "${TMPDIR:-/tmp}/plugin-skill-overrides.XXXXXX") || return 0
  # Write back only a full copy: one line more than the file. cat > file keeps the mode
  # and the owner of the file.
  if awk 'NR == 1 { print; print "disable-model-invocation: true"; next } { print }' "$file" > "$tmp" &&
    [ "$(awk 'END { print NR }' "$tmp")" -eq $(($(awk 'END { print NR }' "$file") + 1)) ]; then
    cat "$tmp" > "$file"
  fi
  rm -f "$tmp"
}

# One line per entry: <install path> TAB <entry name>.
jq -r --slurpfile inst "$installed" '
  (.skillOverrides // {}) | to_entries[]
  | select(.value == "user-invocable-only" and (.key | test("^[A-Za-z0-9._-]+:[A-Za-z0-9._-]+$")))
  | select(.key | test("\\.\\.") | not)
  | (.key | split(":")) as [$plugin, $name]
  | $inst[0].plugins // {} | to_entries[]
  | select(.key | startswith($plugin + "@"))
  | (.value | if type == "array" then .[] else . end) | select(.installPath) | "\(.installPath)\t\($name)"
' "$settings" 2>/dev/null |
  while IFS="$(printf '\t')" read -r path name; do
    case "$path" in
      *..*) continue ;;
      "$claude_dir/plugins/cache/"*) ;;
      *) continue ;;
    esac
    [ -d "$path" ] || continue
    for file in "$path/commands/$name.md" "$path/skills/$name/SKILL.md"; do
      [ -f "$file" ] && patch "$file"
    done
    root="$path/SKILL.md"
    if [ -f "$root" ] && [ "$(front_name "$root")" = "$name" ]; then
      patch "$root"
    fi
  done

exit 0
