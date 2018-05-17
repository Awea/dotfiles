#!/usr/bin/env bash
getDir () {
  fname=$1
  while [ -h "$fname" ]; do
    dir=$(cd -P "$(dirname "$fname")" && pwd)
    fname=$(readlink $fname)
    [[ $fname != /* ]] && fname="$dir/$fname"
  done
  echo "$(cd "$(dirname $fname)" && pwd -P)"
}
# used by loader to find core/ and stdlib/
BORK_SOURCE_DIR="$(cd $(getDir ${BASH_SOURCE[0]})/.. && pwd -P)"
BORK_SCRIPT_DIR=$PWD
BORK_WORKING_DIR=$PWD
operation="satisfy"
case "$1" in
  status) operation="$1"
esac
is_compiled () { return 0; }
arguments () {
  op=$1
  shift
  case $op in
    get)
      key=$1
      shift
      value=
      while [ -n "$1" ] && [ -z "$value" ]; do
        this=$1
        shift
        if [ ${this:0:2} = '--' ]; then
          tmp=${this:2}       # strip off leading --
          echo "$tmp" | grep -E '=' > /dev/null
          if [ "$?" -eq 0 ]; then
            param=${tmp%%=*}    # everything before =
            val=${tmp##*=}      # everything after =
          else
            param=$tmp
            val="true"
          fi
        if [ "$param" = $key ]; then value=$val; fi
        fi
      done
      [ -n $value ] && echo "$value"
      ;;
    *) return 1 ;;
  esac
}
# a bag is a combination of a stack, array and dict
# ## like a stack, you can
# - **push** a value onto the top
# - **pop** a value off of the top
# - **read** the topmost value
# - get the **size** of the stack
# ## like an array, you can
# - **filter** for values matching a pattern
# - **find** the first value matching a pattern
# - get the **index** of the first value matching a pattern
# ## like a dict, you can
# - **set** a key to a value.  This is stored as "$key=$value".  It will
#   overwrite any previous value for $key.
# - **get** the value for a key.
# - **print** outputs the contents of the bag, one line at a time.
bag () {
  action=$1
  varname=$2
  shift 2
  if [ "$action" != "init" ]; then
    length=$(eval "echo \${#$varname[*]}")
    last=$(( length - 1 ))
  fi
  case "$action" in
    init) eval "$varname=( )" ;;
    push) eval "$varname[$length]=\"$1\"" ;;
    pop) eval "unset $varname[$last]" ;;
    read)
      [ "$length" -gt 0 ] && echo $(eval "echo \${$varname[$last]}") ;;
    size) echo $length ;;
    filter)
      index=0
      (( limit=$2 ))
      [ "$limit" -eq 0 ] && limit=-1
      while [ "$index" -lt $length ]; do
        line=$(eval "echo \${$varname[$index]}")
        if str_matches "$line" "$1"; then
          [ -n "$3" ] && echo $index || echo $line
          [ "$limit" -ge $index ] && return
        fi
        (( index++ ))
      done ;;
    find) echo $(bag filter $varname $1 1) ;;
    index) echo $(bag filter $varname $1 1 1) ;;
    set)
      idx=$(bag index $varname "^$1=")
      [ -z "$idx" ] && idx=$length
      eval "$varname[$idx]=\"$1=$2\""
      ;;
    get)
      line=$(bag filter $varname "^$1=" 1)
      echo "${line##*=}" ;;
    print)
      index=0
      while [ "$index" -lt $length ]; do
        eval "echo \"\${$varname[$index]}\""
        (( index++ ))
      done
      ;;
    *) return 1 ;;
  esac
}
bake () { eval "$*"; }
has_curl () {
    needs_exec "curl"
}
http_head_cmd () {
    url=$1
    shift 1
    has_curl
    if [ "$?" -eq 0 ]; then
        echo "curl -sI \"$url\""
    else
        echo "curl not found; wget support not implemented yet"
        return 1
    fi
}
http_header () {
    header=$1
    headers=$2
    echo "$headers" | grep "$header" | tr -s ' ' | cut -d' ' -f2
}
http_get_cmd () {
    url=$1
    target=$2
    has_curl
    if [ "$?" -eq 0 ]; then
        echo "curl -so \"$target\" \"$url\" &> /dev/null"
    else
        echo "curl not found; wget support not implemented yet"
        return 1
    fi
}
md5cmd () {
  case $1 in
    Darwin)
      [ -z "$2" ] && echo "md5" || echo "md5 -q $2"
      ;;
    Linux)
      [ -z "$2" ] && arg="" || arg="$2 "
      echo "md5sum $arg| awk '{print \$1}'"
      ;;
    *) return 1 ;;
  esac
}
satisfying () { [ "$operation" == "satisfy" ]; }
permission_cmd () {
  case $1 in
    Linux) echo "stat --printf '%a'" ;;
    Darwin) echo "stat -f '%Lp'" ;;
    *) return 1 ;;
  esac
}
STATUS_OK=0
STATUS_FAILED=1
STATUS_MISSING=10
STATUS_OUTDATED=11
STATUS_PARTIAL=12
STATUS_MISMATCH_UPGRADE=13
STATUS_MISMATCH_CLOBBER=14
STATUS_CONFLICT_UPGRADE=20
STATUS_CONFLICT_CLOBBER=21
STATUS_CONFLICT_HALT=25
STATUS_BAD_ARGUMENTS=30
STATUS_FAILED_ARGUMENTS=31
STATUS_FAILED_ARGUMENT_PRECONDITION=32
STATUS_FAILED_PRECONDITION=33
STATUS_UNSUPPORTED_PLATFORM=34
_status_for () {
  case "$1" in
    $STATUS_OK) echo "ok" ;;
    $STATUS_FAILED) echo "failed" ;;
    $STATUS_MISSING) echo "missing" ;;
    $STATUS_OUTDATED) echo "outdated" ;;
    $STATUS_PARTIAL) echo "partial" ;;
    $STATUS_MISMATCH_UPGRADE) echo "mismatch (upgradable)" ;;
    $STATUS_MISMATCH_CLOBBER) echo "mismatch (clobber required)" ;;
    $STATUS_CONFLICT_UPGRADE) echo "conflict (upgradable)" ;;
    $STATUS_CONFLICT_CLOBBER) echo "conflict (clobber required)" ;;
    $STATUS_CONFLICT_HALT) echo "conflict (unresolvable)" ;;
    $STATUS_BAD_ARGUMENT) echo "error (bad arguments)" ;;
    $STATUS_FAILED_ARGUMENTS) echo "error (failed arguments)" ;;
    $STATUS_FAILED_ARGUMENT_PRECONDITION) echo "error (failed argument precondition)" ;;
    $STATUS_FAILED_PRECONDITION) echo "error (failed precondition)" ;;
    $STATUS_UNSUPPORTED_PLATFORM) echo "error (unsupported platform)" ;;
    *)    echo "unknown status: $1" ;;
  esac
}
# to be called from an assertions's "status" action, to determine is the target
# system has a necessary exec.  Returns 0 if found, $2 + 1 if not.
#
# arguments
# $1: exec to test against.  Will be provided to `which`.
#     required
# $2: running status.  Allows you to "chain" needs exec calls, to easily test
#     multiple `needs_exec` calls and know if any failed.
#     optional, default: 0
needs_exec () {
  [ -z "$1" ] && return 1
  [ -z "$2" ] && running_status=0 || running_status=$2
  # was seeing some weirdness on this where $1 would have carraige returns sometimes, so it's quoted.
  path=$(bake "which $1")
  if [ "$?" -gt 0 ]; then
    echo "missing required exec: $1"
    retval=$((running_status+1))
    return $retval
  else return $running_status
  fi
}
platform=$(uname -s)
# TODO: deprecated in favor of platform_is
is_platform () {
  [ "$platform" = $1 ]
  return $?
}
platform_is () {
  [ "$platform" = $1 ]
  return $?
}
baking_platform=
baking_platform_is () {
  # this is done lazily, to allow time for bake to be reconfigured.
  [ -z "$baking_platform" ] && baking_platform=$(bake uname -s)
  [ "$baking_platform" = $1 ]
  return $?
}
# Checks a list for a complete match
# pass: "foo bar bee" "foo"
# fail: "foo bar bee" "oo"
str_contains () {
  str_matches "$1" "^$2\$"
}
# retrieves the space-seperated field from a string
# str_get_field "foo bar bee" 2 -> "bar"
str_get_field () {
  echo $(echo "$1" | awk '{print $'"$2"'}')
}
# Counts the number of iteratable items in a string.
# Note that if the string is the output of a shell command, f.e:
#   dir_listing=$(ls)
# That you *must* quote the variable when passing it to the function:
#   str_item_count "$dir_listing"
# If you do not it will simply return '1'
str_item_count () {
  accum=0
  for item in $1; do
    ((accum++))
  done
  echo $accum
}
# Checks a string for any match. Accepts a regexp
# pass: "foo bar bee" "o{2,}\s+"
# fail: "foo bar bee" "ee\s+"
str_matches () {
  $(echo "$1" | grep -E "$2" > /dev/null)
  return $?
}
# Takes a string, replaces matches with a replacement
# "foo bar" "b\w+" "oo" -> "foo boo"
str_replace () {
  echo $(echo "$1" | sed -E 's|'"$2"'|'"$3"'|g')
}
# Removes blank or comment-only lines from stdin
strip_blanks () {
  awk '!/^($|[[:space:]]*#)/{print $0}' <&0
}
bork_performed_install=0
bork_performed_upgrade=0
bork_performed_error=0
bork_any_updated=0
did_install () { [ "$bork_performed_install" -eq 1 ] && return 0 || return 1; }
did_upgrade () { [ "$bork_performed_upgrade" -eq 1 ] && return 0 || return 1; }
did_update () {
  if did_install; then return 0
  elif did_upgrade; then return 0
  else return 1
  fi
}
did_error () { [ "$bork_performed_error" -gt 0 ] && return 0 || return 1; }
any_updated () { [ "$bork_any_updated" -gt 0 ] && return 0 || return 1; }
_changes_reset () {
  bork_performed_install=0
  bork_performed_upgrade=0
  bork_performed_error=0
  last_change_type=
}
_changes_complete () {
  status=$1
  action=$2
  if [ "$status" -gt 0 ]; then bork_performed_error=1
  elif [ "$action" = "install" ]; then bork_performed_install=1
  elif [ "$action" = "upgrade" ]; then bork_performed_upgrade=1
  fi
  if did_update; then bork_any_updated=1 ;fi
  [ "$status" -gt 0 ] && echo "* failure"
}
destination () {
  echo "deprecation warning: 'destination' utility will be removed in a future version - use 'cd' instead" 1>&2
  cd $1
}
# keeps track of where we've come from
bag init include_directories
bag push include_directories "$BORK_SCRIPT_DIR"
include () {
    incl_script="$(bag read include_directories)/$1"
    if [ -e $incl_script ]; then
        target_dir=$(dirname $incl_script)
        bag push include_directories "$target_dir"
        case $operation in
            compile) compile_file "$incl_script" ;;
            *) . $incl_script ;;
        esac
        bag pop include_directories
    else
        echo "include: $incl_script: No such file" 1>&2
        exit 1
    fi
    return 0
}
_source_runner () {
  if is_compiled; then echo "$1"
  else echo ". $1"
  fi
}
_bork_check_failed=0
check_failed () { [ "$_bork_check_failed" -gt 0 ] && return 0 || return 1; }
_checked_len=0
_checking () {
  type=$1
  shift
  check_str="$type: $*"
  _checked_len=${#check_str}
  echo -n "$check_str"$'\r'
}
_checked () {
  report="$*"
  (( pad=$_checked_len - ${#report} ))
  i=1
  while [ "$i" -le $pad ]; do
    report+=" "
    (( i++ ))
  done
  echo "$report"
}
_conflict_approve () {
  if [ -n "$BORK_CONFLICT_RESOLVE" ]; then
    return $BORK_CONFLICT_RESOLVE
  fi
  echo
  echo "== Warning! Assertion: $*"
  echo "Attempting to satisfy has resulted in a conflict.  Satisfying this may overwrite data."
  _yesno "Do you want to continue?"
  return $?
}
_yesno () {
  answered=0
  answer=
  while [ "$answered" -eq 0 ]; do
    read -p "$* (yes/no) " answer
    if [[ "$answer" == 'y' || "$answer" == "yes" || "$answer" == "n" || "$answer" == "no" ]]; then
      answered=1
    else
      echo "Valid answers are: yes y no n" >&2
    fi
  done
  [[ "$answer" == 'y' || "$answer" == 'yes' ]]
}
ok () {
  assertion=$1
  shift
  _bork_check_failed=0
  _changes_reset
  fn=$(_lookup_type $assertion)
  if [ -z "$fn" ]; then
    echo "not found: $assertion" 1>&2
    return 1
  fi
  argstr=$*
  quoted_argstr=
  while [ -n "$1" ]; do
    quoted_argstr=$(echo "$quoted_argstr '$1'")
    shift
  done
  case $operation in
    echo) echo "$fn $argstr" ;;
    status)
      _checking "checking" $assertion $argstr
      output=$(eval "$(_source_runner $fn) status $quoted_argstr")
      status=$?
      _checked "$(_status_for $status): $assertion $argstr"
      [ "$status" -eq 1 ] && _bork_check_failed=1
      [ "$status" -ne 0 ] && [ -n "$output" ] && echo "$output"
      return $status ;;
    satisfy)
      _checking "checking" $assertion $argstr
      status_output=$(eval "$(_source_runner $fn) status $quoted_argstr")
      status=$?
      _checked "$(_status_for $status): $assertion $argstr"
      case $status in
        0) : ;;
        1)
          _bork_check_failed=1
          echo "$status_output"
          ;;
        10)
          eval "$(_source_runner $fn) install $quoted_argstr"
          _changes_complete $? 'install'
          ;;
        11|12|13)
          echo "$status_output"
          eval "$(_source_runner $fn) upgrade $quoted_argstr"
          _changes_complete $? 'upgrade'
          ;;
        20)
          echo "$status_output"
          _conflict_approve $assertion $argstr
          if [ "$?" -eq 0 ]; then
            echo "Resolving conflict..."
            eval "$(_source_runner $fn) upgrade $quoted_argstr"
            _changes_complete $? 'upgrade'
          else
            echo "Conflict unresolved."
          fi
          ;;
        *)
          echo "-- sorry, bork doesn't handle this response yet"
          echo "$status_output"
          ;;
      esac
      if did_update; then
        echo "verifying $last_change_type: $assertion $argstr"
        output=$(eval "$(_source_runner $fn) status $quoted_argstr")
        status=$?
        if [ "$status" -gt 0 ]; then
          echo "* $last_change_type failed"
          _checked "$(_status_for $status)"
          echo "$output"
        else
          echo "* success"
        fi
        return 1
      fi
      ;;
  esac
}
# manages assertion types
# is a bag that keeps track of assertion types their locations
bag init bork_assertion_types
# register a local assertion type
# register $filename
# - $filename: path to a local file to register
#   basename of file is the asertion type.
#
#     register helpers/pip.sh
#     ok pip pygments
#
# exits with status 1 if the file doesn't exist
register () {
  file=$1
  type=$(basename $file '.sh')
  if [ -e "$BORK_SCRIPT_DIR/$file" ]; then
    file="$BORK_SCRIPT_DIR/$file"
  else
    exit 1
  fi
  bag set bork_assertion_types $type $file
}
# lookup assertion function
# yes, this could have been done in fewer lines with a gnarly nested IF/ELSE
# type statement.  I have no interest in saving lines at the cost of clarity.
_lookup_type () {
  assertion=$1
  if is_compiled; then
    echo "type_$assertion"
    return
  fi
  fn=$(bag get bork_assertion_types $assertion)
  if [ -n "$fn" ]; then
    echo "$fn"
    return
  fi
  bork_official="$BORK_SOURCE_DIR/types/$(echo $assertion).sh"
  if [ -e "$bork_official" ]; then
    echo "$bork_official"
    return
  fi
  local_script="$BORK_SCRIPT_DIR/$assertion"
  if [ -e "$local_script" ]; then
    echo "$local_script"
    return
  fi
  return 1
}
# Vars
APP_DIR=$HOME/.apps
WORKSPACE_DIR=$HOME/.workspace

# Setup
## Directories
# /home/awea/.apps/bork/types/directory.sh
type_directory () {
  # TODO add --permissions flag, perhaps copy/extract from file?
  action=$1
  dir=$2
  shift 2
  owner=$(arguments get owner $*)
  group=$(arguments get group $*)
  mode=$(arguments get mode $*)
  case "$action" in
    desc)
      printf '%s\n' \
        'asserts presence of a directory' \
        '* directory path [options]' \
        '--owner=user-name' \
        '--group=group-name' \
        '--mode=mode' \
        '> directory ~/.ssh --mode=700'
      ;;
    status)
      bake [ -e "${dir}" ] || return $STATUS_MISSING
      bake [ -d "${dir}" ] || {
        echo "target exists as non-directory"
        return $STATUS_CONFLICT_CLOBBER
      }
      mismatch=false
      if [[ -n ${owner} || -n ${group} || -n ${mode} ]]; then
        readarray -t dir_stat < <(bake stat --printf '%U\\n%G\\n%a' "${dir}")
        if [[ -n ${owner} && ${dir_stat[0]} != ${owner} ]]; then
          printf '%s owner: %s\n' \
            'expected' "${owner}" \
            'received' "${dir_stat[0]}"
          mismatch=true
        fi
        if [[ -n ${group} && ${dir_stat[1]} != ${group} ]]; then
          printf '%s group: %s\n' \
            'expected' "${group}" \
            'received' "${dir_stat[1]}"
          mismatch=true
        fi
        if [[ -n ${mode} && ${dir_stat[2]} != ${mode} ]]; then
          printf '%s mode: %s\n' \
            'expected' "${mode}" \
            'received' "${dir_stat[2]}"
          mismatch=true
        fi
      fi
      if ${mismatch}; then
        return "${STATUS_MISMATCH_UPGRADE}"
      fi
      return "${STATUS_OK}"
      ;;
    install|upgrade)
      inst_cmd=( install -C -d )
      [[ -z ${owner} && -z ${group} ]] || inst_cmd=( sudo "${inst_cmd[@]}" )
      [[ -z ${owner} ]] || inst_cmd+=( -o "${owner}" )
      [[ -z ${group} ]] || inst_cmd+=( -g "${group}" )
      [[ -z ${mode} ]] || inst_cmd+=( -m "${mode}" )
      bake "${inst_cmd[@]}" "${dir}"
      ;;
    *) return 1 ;;
  esac
}
ok directory $APP_DIR
ok directory $WORKSPACE_DIR

## Package Cloud: https://packagecloud.io/
# /home/awea/.apps/bork/types/download.sh
type_download () {
  action=$1
  targetfile=$2
  sourceurl=$3
  shift 3
  size=$(arguments get size $*)
  case "$action" in
      desc)
          echo "assert the presence & comparisons of a file to a URL"
          echo "> download ~/file.zip \"http://example.com/file.zip\""
          echo "--size                (compare size to Content-Length at URL)"
          ;;
      status)
          bake [ -f "\"$targetfile\"" ] || return $STATUS_MISSING
          if [ -n "$size" ]; then
              fileinfo=$(bake ls -al "\"$targetfile\"")
              sourcesize=$(echo "$fileinfo" | tr -s ' ' | cut -d' ' -f5)
              remoteinfo=$(bake $(http_head_cmd "$sourceurl"))
              remotesize=$(http_header "Content-Length" "$remoteinfo")
              remotesize=${remotesize%%[^0-9]*}
              if [ "$sourcesize" != "$remotesize" ]; then
                  echo "expected size: $remotesize bytes"
                  echo "received size: $localsize bytes"
                  return $STATUS_CONFLICT_UPGRADE
              fi
          fi
          return $STATUS_OK
      ;;
      install|upgrade)
          bake $(http_get_cmd "$sourceurl" "$targetfile")
      ;;
      *) return 1 ;;
  esac
}
ok download /tmp/script.deb.sh https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh

if did_update; then
sudo bash /tmp/script.deb.sh
fi

## Dotfiles: https://github.com/awea/dotfiles
# /home/awea/.apps/bork/types/github.sh
type_github () {
  # TODO some flag for git:// urls
  if [ -z "$git_call" ]; then
    git_call=". $BORK_SOURCE_DIR/types/git.sh"
    is_compiled && git_call="type_git"
  fi
  action=$1
  repo=$2
  shift 2
  case $action in
    desc)
      echo "front-end for git type, uses github urls"
      echo "passes arguments to git type"
      echo "> ok github mattly/bork"
      echo "> ok github ~/code/bork mattly/bork"
      echo "--ssh                    (clones via ssh instead of https)"
      ;;
    compile)
      include_assertion git $BORK_SOURCE_DIR/types/git.sh
      ;;
    status|install|upgrade)
      next=$1
      target_dir=
      if [ -n "$next" ] && [ ${next:0:1} != '-' ]; then
        target_dir="$repo"
        repo=$1
        shift
      fi
      args="$*"
      if [ -n  "$(arguments get ssh $*)" ]; then
        url="git@github.com:$(echo $repo).git"
        args=$(echo "$args" | sed -E 's|--ssh||')
      else
        url="https://github.com/$(echo $repo).git"
      fi
      eval "$git_call $action $target_dir $url $args"
      ;;
    *) return 1 ;;
  esac
}
# /home/awea/.apps/bork/types/git.sh
type_git () {
  # TODO compare origins to ensure correct, provide fix for
  # TODO provide flag for refspec name, ensure status/install/upgrade use it properly
  # TODO perhaps do --depth=0 by default (quicker) & provide flag for --full ?
  # TODO submodules?
  # TODO anything here we can extract and re-use for an hg or darcs type?
  # TODO use merge instead of pull
  # TODO specify alternate refs instead of "master"; maybe change branch?
  action=$1
  git_url=$2
  shift 2
  next=$1
  if [ -n "$next" ] && [ ${next:0:1} != '-' ]; then
    target_dir=$git_url
    git_url=$1
    shift
  else
    git_name=$(basename $git_url .git)
    target_dir="$git_name"
  fi
  branch=$(arguments get branch $*)
  if [[ ! -z $branch ]]; then
    git_branch=$branch
  else
    git_branch="master"
  fi
  case $action in
    desc)
      echo "asserts presence and state of a git repository"
      echo "> git git@github.com:mattly/bork"
      echo "> git ~/code/bork git@github.com:mattly/bork"
      echo "--ref=gh-pages                (specify branch, tag, or ref)"
      ;;
    status)
      needs_exec "git" || return $STATUS_FAILED_PRECONDITION
      # if the directory is missing, it's missing
      bake [ ! -d $target_dir ] && return $STATUS_MISSING
      # if the directory is present but empty, it's missing
      target_dir_contents=$(str_item_count "$(bake ls -A $target_dir)")
      [ "$target_dir_contents" -eq 0 ] && return $STATUS_MISSING
      bake cd $target_dir
      # fetch from the remote without fast-forwarding
      # this *does* change the local repository's pointers and takes longer
      # up front, but I believe in the grand scheme is the right thing to do.
      git_fetch="$(bake git fetch 2>&1)"
      git_fetch_status=$?
      # If the directory isn't a git repo, conflict
      if [ $git_fetch_status -gt 0 ]; then
        echo "destination directory $target_dir exists, not a git repository (exit status $git_fetch_status)"
        return $STATUS_CONFLICT_CLOBBER
      elif str_matches "$git_fetch" '"^fatal"'; then
        echo "destination directory exists, not a git repository"
        echo "$git_fetch"
        return $STATUS_CONFLICT_CLOBBER
      fi
      git_stat=$(bake git status -uno -b --porcelain)
      git_first_line=$(echo "$git_stat" | head -n 1)
      git_divergence=$(str_get_field "$git_first_line" 3)
      if str_matches "$git_divergence" 'ahead'; then
        echo "local git repository is ahead of remote"
        return $STATUS_CONFLICT_UPGRADE
      fi
      # are there changes?
      if str_matches "$git_stat" "^\\s?\\w"; then
        echo "local git repository has uncommitted changes"
        return $STATUS_CONFLICT_UPGRADE
      fi
      str_matches "$(str_get_field "$git_first_line" 2)" "$git_branch"
      if [ "$?" -ne 0 ]; then
        echo "local git repository is on incorrect branch"
        return $STATUS_MISMATCH_UPGRADE
      fi
      # If it's known to be behind, outdated
      if str_matches "$git_divergence" 'behind'; then return $STATUS_OUTDATED; fi
      # guess we're clean, so things are OK
      return $STATUS_OK ;;
    install)
      bake mkdir -p $target_dir
      bake git clone -b $git_branch $git_url $target_dir
      ;;
    upgrade)
      bake cd $target_dir
      bake git reset --hard
      bake git pull
      bake git checkout $git_branch
      bake git log HEAD@{2}..
      printf "\n"
      ;;
    *) return 1 ;;
  esac
}
ok github $WORKSPACE_DIR/dotfiles awea/dotfiles

if did_update; then
cd $WORKSPACE_DIR/dotfiles && make all_install
fi

# ZSH
# /home/awea/.apps/bork/types/apt.sh
type_apt () {
  # TODO
  # - cache output of apt-get upgrade, only needs to be done once per run
  # - perhaps move the apt-get upgrade command out to a separate call without
  #   a package name, similar to how the "brew" type does it.
  # - specify versions to install with --version flag (ie, ruby=2.0.0)
  # - specify distribution to install from with --dist flag (ie ruby/unstable)
  action=$1
  name=$2
  shift 2
  case $action in
    desc)
      echo "asserts packages installed via apt-get on debian or ubuntu linux"
      echo "* apt package-name"
      ;;
    status)
      baking_platform_is "Linux" || return $STATUS_UNSUPPORTED_PLATFORM
      needs_exec "apt-get" 0
      needs_exec "dpkg" $?
      [ "$?" -gt 0 ] && return $STATUS_FAILED_PRECONDITION
      echo "$(bake dpkg --get-selections)" | grep -E "^$name\\s+install$"
      [ "$?" -gt 0 ] && return $STATUS_MISSING
      outdated=$(bake sudo apt-get upgrade --dry-run \
                  | grep "^Inst" | awk '{print $2}')
      $(str_contains "$outdated" "$name")
      [ "$?" -eq 0 ] && return $STATUS_OUTDATED
      return $STATUS_OK
      ;;
    install|upgrade)
      bake sudo apt-get --yes install $name
      ;;
    *) return 1 ;;
  esac
}
ok apt zsh

if did_install; then
chsh -s /bin/zsh
fi

# Prezto: https://github.com/sorin-ionescu/prezto/
ok github $HOME/.zprezto sorin-ionescu/prezto --recursive

# Wont work
# if did_install; then
#   zsh
#   setopt EXTENDED_GLOB
#   for rcfile in "${ZDOTDIR:-$HOME}"/.zprezto/runcoms/^README.md(.N); do
#     ln -s "$rcfile" "${ZDOTDIR:-$HOME}/.${rcfile:t}"
#   done
# fi

# SublimeText: https://www.sublimetext.com/
ok download /tmp/sublimehq-pub.gpg https://download.sublimetext.com/sublimehq-pub.gpg

if did_install; then
sudo apt-key add /tmp/sublimehq-pub.gpg
echo "deb https://download.sublimetext.com/ apt/stable/" | sudo tee /etc/apt/sources.list.d/sublime-text.list
sudo apt update
fi

ok apt apt-transport-https
ok apt sublime-text

# Pass
ok apt pass
ok download $HOME/.zsh/completion/_pass https://raw.githubusercontent.com/zx2c4/password-store/master/src/completion/pass.zsh-completion

# Z
ok download $APP_DIR/z.sh https://raw.githubusercontent.com/rupa/z/master/z.sh

# Git
## LFS: https://git-lfs.github.com/
ok apt git-lfs

# WebUI
ok download /tmp/git-webui/installer.sh https://raw.githubusercontent.com/alberthier/git-webui/master/install/installer.sh

if did_install; then
bash /tmp/git-webui/installer.sh
fi

# Dropbox
ok download /tmp/dropbox_2015.10.28_amd64.deb https://www.dropbox.com/download?dl=packages/ubuntu/dropbox_2015.10.28_amd64.deb

if did_update; then
sudo dpkg -i /tmp/dropbox_2015.10.28_amd64.deb
fi

# Chrome
ok download /tmp/chrome-key.pub https://dl-ssl.google.com/linux/linux_signing_key.pub

if did_update; then
sudo apt-key add /tmp/chrome-key.pub
echo 'deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main' | sudo tee /etc/apt/sources.list.d/google-chrome.list
sudo apt update
fi

ok apt google-chrome-stable

# ASDF: https://github.com/asdf-vm/asdf
ok github ~/.asdf https://github.com/asdf-vm/asdf.git --branch v0.4.3
ok apt automake
ok apt autoconf
ok apt libreadline-dev
ok apt libncurses-dev
ok apt libssl-dev
ok apt libyaml-dev
ok apt libxslt-dev
ok apt libffi-dev
ok apt libtool
ok apt unixodbc-dev

## Ruby
check asdf plugin-add ruby https://github.com/asdf-vm/asdf-ruby.git

## Nodejs
check asdf plugin-add nodejs https://github.com/asdf-vm/asdf-nodejs.git
check bash ~/.asdf/plugins/nodejs/bin/import-release-team-keyring

## Elixir
check asdf plugin-add elixir https://github.com/asdf-vm/asdf-elixir.git

## Rust
check asdf plugin-add rust https://github.com/code-lever/asdf-rust.git

# Yarn
ok download /tmp/asdf-key.gpg https://dl.yarnpkg.com/debian/pubkey.gpg

if did_update; then
sudo apt-key add /tmp/asdf-key.gpg
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
sudo apt update
fi

ok apt yarn

# Docker
ok apt apt-transport-https
ok apt ca-certificates
ok apt curl
ok apt software-properties-common
ok download /tmp/docker-key.gpg https://download.docker.com/linux/ubuntu/gpg

if did_update; then
sudo apt-key add /tmp/docker-key.gpg
sudo add-apt-repository      "deb [arch=amd64] https://download.docker.com/linux/ubuntu      $(lsb_release -cs)      stable"
sudo apt update
fi

ok apt docker-ce
# /home/awea/.apps/bork/types/group.sh
type_group () {
  # TODO doesn't work on Darwin, is groupadd a GNU thing?
  action=$1
  groupname=$2
  shift 2
  case $action in
    desc)
      echo "asserts presence of a unix group (linux only, for now)"
      echo "> group admin"
      ;;
    status)
      needs_exec groupadd || return $STATUS_FAILED_PRECONDITION
      bake cat /etc/group | grep -E "^$groupname:"
      [ "$?" -gt 0 ] && return $STATUS_MISSING
      return $STATUS_OK ;;
    install)
      bake groupadd $groupname ;;
    *) return 1 ;;
  esac
}
ok group docker
check sudo usermod -aG docker awea

## Compose
DOCKER_COMPOSE_VERSION=docker-compose-`uname -s`-`uname -m`

ok download /usr/local/bin/docker-compose https://github.com/docker/compose/releases/download/1.20.1/$DOCKER_COMPOSE_VERSION
check sudo chmod +x /usr/local/bin/docker-compose
ok download ~/.zsh/completion/_docker-compose https://raw.githubusercontent.com/docker/compose/1.20.1/contrib/completion/zsh/_docker-compose

# Skype
ok download /tmp/skypeforlinux-64.deb https://go.skype.com/skypeforlinux-64.deb

if did_update; then
sudo dpkg -i /tmp/skypeforlinux-64.deb
fi

# Virtualbox
ok apt virtualbox

# Ansible
ok apt python-setuptools
ok apt python-dev
check sudo easy_install pip
# /home/awea/.apps/bork/types/pip.sh
type_pip () {
  # TODO --sudo flag
  # TODO versions
  # TODO update
  action=$1
  name=$2
  shift 2
  case $action in
    desc)
      echo "asserts presence of packages installed via pip"
      echo "> pip pygments"
      ;;
    status)
      needs_exec "pip" || return $STATUS_FAILED_PRECONDITION
      pkgs=$(PIP_FORMAT=legacy bake pip list)
      if ! str_matches "$pkgs" "^$name"; then
        return $STATUS_MISSING
      fi
      return 0 ;;
    install)
      bake pip install "$name"
      ;;
  esac
}
ok pip ansible

# Tools
ok apt tmux
ok apt apache2-utils
