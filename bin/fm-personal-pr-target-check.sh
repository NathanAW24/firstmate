#!/usr/bin/env bash
# Refuse a personal Firstmate PR delivery whose repository or base is not the
# personal fork target.
#
# Usage:
#   fm-personal-pr-target-check.sh \
#     --repository NathanAW24/firstmate \
#     --base nathan-main \
#     --delivery no-mistakes [--gate-worktree]
#
# This is the executable preflight at the personal Firstmate PR-delivery seam.
# It verifies the caller's intended repository and base, the local origin,
# origin's advertised default branch, and the gate's recorded PR repository and
# push target. Ordinary worktrees must also keep upstream as
# a fetch-only kunchenguid/firstmate remote whose push URL is literally
# DISABLED. A no-mistakes gate worktree has only its managed origin, so the
# trusted .no-mistakes.yaml invocation passes --gate-worktree; that option is
# accepted only when NO_MISTAKES_GATE is present.
#
# The check is read-only. It performs git ls-remote and no-mistakes status
# probes, but it never creates, edits, comments on, closes, or merges a PR.
set -eu

EXPECTED_REPOSITORY=NathanAW24/firstmate
EXPECTED_BASE=nathan-main
EXPECTED_UPSTREAM=kunchenguid/firstmate
REPOSITORY=
BASE=
DELIVERY=
GATE_WORKTREE=0

usage() {
  awk '
    NR == 1 { next }
    /^#/ { sub(/^# ?/, ""); print; next }
    { exit }
  ' "$0"
}

refuse() {
  echo "REFUSED: personal Firstmate PR target: $*" >&2
  exit 1
}

github_repository() { # <remote-url>; prints OWNER/REPO for accepted GitHub spellings
  local raw=$1 rest authority path
  case "$raw" in
    git@github.com:*)
      path=${raw#git@github.com:}
      ;;
    ssh://git@github.com/*)
      path=${raw#ssh://git@github.com/}
      ;;
    ssh://git@github.com:22/*)
      path=${raw#ssh://git@github.com:22/}
      ;;
    https://*)
      rest=${raw#https://}
      authority=${rest%%/*}
      case "$authority" in
        github.com|?*@github.com) ;;
        *) return 1 ;;
      esac
      path=${rest#*/}
      ;;
    *) return 1 ;;
  esac

  case "$path" in
    *'?'*|*'#'*|'') return 1 ;;
  esac
  path=${path%/}
  path=${path%.git}
  case "$path" in
    */*) ;;
    *) return 1 ;;
  esac
  printf '%s\n' "$path"
}

remote_repository() { # <remote> <fetch|push>
  local remote=$1 direction=$2 url repository
  if [ "$direction" = push ]; then
    url=$(git remote get-url --push "$remote" 2>/dev/null) \
      || refuse "cannot read the $remote push URL"
  else
    url=$(git remote get-url "$remote" 2>/dev/null) \
      || refuse "cannot read the $remote fetch URL"
  fi
  repository=$(github_repository "$url") \
    || refuse "$remote $direction URL does not identify an accepted GitHub repository"
  printf '%s\n' "$repository"
}

status_repository() { # <no-mistakes-status> <remote:|fork:>
  local status=$1 key=$2 url repository
  url=$(printf '%s\n' "$status" | awk -v key="$key" '$1 == key { print $2; exit }')
  [ -n "$url" ] || refuse "no-mistakes status did not report $key"
  repository=$(github_repository "$url") \
    || refuse "no-mistakes $key does not identify an accepted GitHub repository"
  printf '%s\n' "$repository"
}

want=
for arg in "$@"; do
  if [ -n "$want" ]; then
    case "$arg" in
      --*) refuse "--$want requires a value" ;;
    esac
    case "$want" in
      repository) REPOSITORY=$arg ;;
      base) BASE=$arg ;;
      delivery) DELIVERY=$arg ;;
      *) refuse "internal parser state for --$want" ;;
    esac
    want=
    continue
  fi
  case "$arg" in
    --repository) want=repository ;;
    --repository=*) REPOSITORY=${arg#--repository=} ;;
    --base) want=base ;;
    --base=*) BASE=${arg#--base=} ;;
    --delivery) want=delivery ;;
    --delivery=*) DELIVERY=${arg#--delivery=} ;;
    --gate-worktree) GATE_WORKTREE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) refuse "unknown argument: $arg" ;;
  esac
done
[ -z "$want" ] || refuse "--$want requires a value"

[ "$REPOSITORY" = "$EXPECTED_REPOSITORY" ] \
  || refuse "repository must be $EXPECTED_REPOSITORY, not ${REPOSITORY:-<missing>}"
[ "$BASE" = "$EXPECTED_BASE" ] \
  || refuse "base must be $EXPECTED_BASE, not ${BASE:-<missing>}"
[ "$DELIVERY" = no-mistakes ] \
  || refuse "personal Firstmate PR delivery must use no-mistakes"
if [ "$GATE_WORKTREE" -eq 1 ] && [ -z "${NO_MISTAKES_GATE:-}" ]; then
  refuse "--gate-worktree is reserved for a no-mistakes gate worktree"
fi

branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null) \
  || refuse "the worktree must be on a branch before PR delivery"
[ "$branch" != "$EXPECTED_BASE" ] \
  || refuse "the task branch must not be the protected base $EXPECTED_BASE"

origin_fetch=$(remote_repository origin fetch)
[ "$origin_fetch" = "$EXPECTED_REPOSITORY" ] \
  || refuse "origin fetch must identify $EXPECTED_REPOSITORY"
origin_push=$(remote_repository origin push)
[ "$origin_push" = "$EXPECTED_REPOSITORY" ] \
  || refuse "origin push must identify $EXPECTED_REPOSITORY"

if [ "$GATE_WORKTREE" -eq 0 ]; then
  upstream_fetch=$(remote_repository upstream fetch)
  [ "$upstream_fetch" = "$EXPECTED_UPSTREAM" ] \
    || refuse "upstream fetch must identify $EXPECTED_UPSTREAM"
  upstream_push=$(git remote get-url --push upstream 2>/dev/null) \
    || refuse "cannot read the upstream push URL"
  [ "$upstream_push" = DISABLED ] \
    || refuse "upstream push URL must be disabled"
fi

advertised=$(git ls-remote --symref origin HEAD 2>/dev/null) \
  || refuse "cannot read origin's advertised default branch"
advertised_head=$(printf '%s\n' "$advertised" | awk '$1 == "ref:" && $3 == "HEAD" { print $2; exit }')
[ "$advertised_head" = "refs/heads/$EXPECTED_BASE" ] \
  || refuse "origin's advertised default branch must be $EXPECTED_BASE"

status=$(NO_MISTAKES_NO_UPDATE_CHECK=1 no-mistakes status 2>/dev/null) \
  || refuse "no-mistakes status could not verify its PR target"
gate_remote=$(status_repository "$status" 'remote:')
[ "$gate_remote" = "$EXPECTED_REPOSITORY" ] \
  || refuse "no-mistakes PR repository must be $EXPECTED_REPOSITORY"
gate_fork=$(status_repository "$status" 'fork:')
[ "$gate_fork" = "$EXPECTED_REPOSITORY" ] \
  || refuse "no-mistakes push target must be $EXPECTED_REPOSITORY"

printf 'personal Firstmate PR target verified: repository=%s base=%s delivery=%s\n' \
  "$EXPECTED_REPOSITORY" "$EXPECTED_BASE" "$DELIVERY"
