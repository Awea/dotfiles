#!/usr/bin/env bash
# SessionStart hook: replace files of an installed plugin with our own versions.
#
# An override lives at $CLAUDE_CONFIG_DIR/plugin-overrides/<plugin>/<path in the plugin>,
# for example plugin-overrides/superpowers/skills/using-superpowers/SKILL.md. The hook copies
# it over <path in the plugin> in each installed version of <plugin>. The plugin cache is a
# copy: an update brings back the plugin files, and the next session start copies the
# overrides again. Hooks of one session start run at the same time, so the session of that
# start can still read the plugin file. A rename swaps in the new file in one step, so a
# reader gets the old file or the new file, never a part of a file.
#
# Limits: it replaces only a file that the plugin has, never adds one. It writes only regular
# files whose real folder is under plugins/cache, never through a symlink.
#
# Output: none on stdout, because SessionStart stdout goes into the context.
# Runs on Linux and macOS (bash 3.2).

claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
overrides="$claude_dir/plugin-overrides"
installed="$claude_dir/plugins/installed_plugins.json"

[ -d "$overrides" ] && [ -f "$installed" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
cache_real=$(cd "$claude_dir/plugins/cache" 2>/dev/null && pwd -P) || exit 0

# One line per override: <plugin>/<path in the plugin>.
(cd "$overrides" && find -L . -type f) | sed 's|^\./||' |
  while IFS= read -r rel; do
    case "$rel" in */*) ;; *) continue ;; esac
    case "$rel" in *..*) continue ;; esac
    plugin=${rel%%/*}
    path=${rel#*/}
    jq -r --arg p "$plugin" '
      .plugins // {} | to_entries[] | select(.key | startswith($p + "@"))
      | (.value | if type == "array" then .[] else . end) | .installPath // empty
    ' "$installed" 2>/dev/null |
      while IFS= read -r root; do
        case "$root" in
          *..*) continue ;;
          "$claude_dir/plugins/cache/"*) ;;
          *) continue ;;
        esac
        target="$root/$path"
        [ -f "$target" ] && [ ! -L "$target" ] || continue
        # The real folder of the target, with each symlink resolved, is in the cache.
        dir_real=$(cd "${target%/*}" 2>/dev/null && pwd -P) || continue
        case "$dir_real/" in "$cache_real/"*) ;; *) continue ;; esac
        cmp -s "$overrides/$rel" "$target" && continue
        # cp -p gives the temp file the mode of the plugin file, then mv swaps it in.
        tmp=$(mktemp "$dir_real/.plugin-file-overrides.XXXXXX") || continue
        if cp -p "$target" "$tmp" && cat "$overrides/$rel" > "$tmp"; then
          mv -f "$tmp" "$dir_real/${target##*/}"
        fi
        rm -f "$tmp"
      done
  done

exit 0
