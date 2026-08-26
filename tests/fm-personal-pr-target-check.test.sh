#!/usr/bin/env bash
# Executable-interface tests for the personal Firstmate PR target preflight.
set -eu

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CHECK="$ROOT/bin/fm-personal-pr-target-check.sh"
TMP_ROOT=$(fm_test_tmproot fm-personal-pr-target-check)
FAKEBIN=$(fm_fakebin "$TMP_ROOT")

cat > "$FAKEBIN/git" <<'SH'
#!/usr/bin/env bash
case "$*" in
  'symbolic-ref --quiet --short HEAD')
    printf '%s\n' "${FM_TEST_BRANCH:-feature/personal-work}"
    ;;
  'remote get-url origin')
    printf '%s\n' "${FM_TEST_ORIGIN_FETCH:-git@github.com:NathanAW24/firstmate.git}"
    ;;
  'remote get-url --push origin')
    printf '%s\n' "${FM_TEST_ORIGIN_PUSH:-git@github.com:NathanAW24/firstmate.git}"
    ;;
  'remote get-url upstream')
    [ "${FM_TEST_UPSTREAM_MISSING:-0}" -eq 0 ] || exit 2
    printf '%s\n' "${FM_TEST_UPSTREAM_FETCH:-git@github.com:kunchenguid/firstmate.git}"
    ;;
  'remote get-url --push upstream')
    [ "${FM_TEST_UPSTREAM_MISSING:-0}" -eq 0 ] || exit 2
    printf '%s\n' "${FM_TEST_UPSTREAM_PUSH:-DISABLED}"
    ;;
  'ls-remote --symref origin HEAD')
    [ "${FM_TEST_LS_REMOTE_FAIL:-0}" -eq 0 ] || exit 2
    printf 'ref: refs/heads/%s\tHEAD\n' "${FM_TEST_ADVERTISED_BASE:-nathan-main}"
    printf '%s\tHEAD\n' '0123456789abcdef0123456789abcdef01234567'
    ;;
  *)
    printf 'unexpected git invocation: %s\n' "$*" >&2
    exit 64
    ;;
esac
SH
chmod +x "$FAKEBIN/git"

cat > "$FAKEBIN/no-mistakes" <<'SH'
#!/usr/bin/env bash
[ "$*" = status ] || {
  printf 'unexpected no-mistakes invocation: %s\n' "$*" >&2
  exit 64
}
[ "${FM_TEST_NO_MISTAKES_FAIL:-0}" -eq 0 ] || exit 2
printf '    repo:  /fixture/firstmate\n'
printf '  remote:  %s\n' "${FM_TEST_GATE_REMOTE:-git@github.com:NathanAW24/firstmate.git}"
printf '    fork:  %s\n' "${FM_TEST_GATE_FORK:-git@github.com:NathanAW24/firstmate.git}"
printf '    gate:  /fixture/.no-mistakes/repos/repo.git\n'
printf '  daemon:  running\n'
SH
chmod +x "$FAKEBIN/no-mistakes"

reset_fixture() {
  export FM_TEST_BRANCH=feature/personal-work
  export FM_TEST_ORIGIN_FETCH=git@github.com:NathanAW24/firstmate.git
  export FM_TEST_ORIGIN_PUSH=https://builder@github.com/NathanAW24/firstmate.git
  export FM_TEST_UPSTREAM_FETCH=https://github.com/kunchenguid/firstmate.git
  export FM_TEST_UPSTREAM_PUSH=DISABLED
  export FM_TEST_UPSTREAM_MISSING=0
  export FM_TEST_ADVERTISED_BASE=nathan-main
  export FM_TEST_LS_REMOTE_FAIL=0
  export FM_TEST_NO_MISTAKES_FAIL=0
  export FM_TEST_GATE_REMOTE=ssh://git@github.com/NathanAW24/firstmate.git
  export FM_TEST_GATE_FORK=https://github.com/NathanAW24/firstmate.git
  unset FM_TEST_REQUESTED_REPOSITORY FM_TEST_REQUESTED_BASE FM_TEST_DELIVERY
  unset FM_TEST_GATE_ARG NO_MISTAKES_GATE
}

run_check() {
  PATH="$FAKEBIN:$PATH" "$CHECK" \
    --repository "${FM_TEST_REQUESTED_REPOSITORY:-NathanAW24/firstmate}" \
    --base "${FM_TEST_REQUESTED_BASE:-nathan-main}" \
    --delivery "${FM_TEST_DELIVERY:-no-mistakes}" \
    ${FM_TEST_GATE_ARG:-}
}

expect_ok() {
  local label=$1 out
  out=$(run_check 2>&1) || fail "$label: valid target was refused: $out"
  assert_contains "$out" 'repository=NathanAW24/firstmate base=nathan-main' \
    "$label: success did not name the verified target"
  pass "$label"
}

expect_refusal() {
  local label=$1 expected=$2 out
  if out=$(run_check 2>&1); then
    fail "$label: unsafe target was accepted: $out"
  fi
  assert_contains "$out" "REFUSED: personal Firstmate PR target:" \
    "$label: refusal did not use the stable refusal prefix"
  assert_contains "$out" "$expected" "$label: refusal did not explain the mismatch"
  pass "$label"
}

reset_fixture
expect_ok 'ordinary no-mistakes worktree accepts only the personal repository and base'

reset_fixture
export FM_TEST_DELIVERY=direct-PR FM_TEST_NO_MISTAKES_FAIL=1
expect_ok 'direct PR preflight does not depend on an initialized no-mistakes gate'

reset_fixture
export FM_TEST_GATE_ARG=--gate-worktree NO_MISTAKES_GATE=1 FM_TEST_UPSTREAM_MISSING=1
expect_ok 'managed no-mistakes worktree verifies its target without inventing an upstream remote'

reset_fixture
export FM_TEST_REQUESTED_REPOSITORY=kunchenguid/firstmate
expect_refusal 'upstream repository request is refused' 'repository must be NathanAW24/firstmate'

reset_fixture
export FM_TEST_REQUESTED_BASE=main
expect_refusal 'upstream base request is refused' 'base must be nathan-main'

reset_fixture
export FM_TEST_BRANCH=nathan-main
expect_refusal 'protected base cannot be used as the task branch' 'task branch must not be the protected base nathan-main'

reset_fixture
export FM_TEST_ORIGIN_FETCH=git@github.com:kunchenguid/firstmate.git
expect_refusal 'wrong origin fetch repository is refused' 'origin fetch must identify NathanAW24/firstmate'

reset_fixture
export FM_TEST_ORIGIN_PUSH=git@github.com:kunchenguid/firstmate.git
expect_refusal 'wrong origin push repository is refused' 'origin push must identify NathanAW24/firstmate'

reset_fixture
export FM_TEST_UPSTREAM_FETCH=git@github.com:NathanAW24/firstmate.git
expect_refusal 'upstream fetch must remain the canonical upstream repository' 'upstream fetch must identify kunchenguid/firstmate'

reset_fixture
export FM_TEST_UPSTREAM_PUSH=git@github.com:kunchenguid/firstmate.git
expect_refusal 'enabled upstream push URL is refused' 'upstream push URL must be disabled'

reset_fixture
export FM_TEST_ADVERTISED_BASE=main
expect_refusal 'wrong advertised default branch is refused' "origin's advertised default branch must be nathan-main"

reset_fixture
export FM_TEST_GATE_REMOTE=git@github.com:kunchenguid/firstmate.git
expect_refusal 'wrong no-mistakes PR repository is refused' 'no-mistakes PR repository must be NathanAW24/firstmate'

reset_fixture
export FM_TEST_GATE_FORK=git@github.com:kunchenguid/firstmate.git
expect_refusal 'wrong no-mistakes push target is refused' 'no-mistakes push target must be NathanAW24/firstmate'

reset_fixture
export FM_TEST_GATE_ARG=--gate-worktree
expect_refusal 'gate-only upstream exemption requires the gate marker' '--gate-worktree is reserved for a no-mistakes gate worktree'

reset_fixture
export FM_TEST_LS_REMOTE_FAIL=1
expect_refusal 'unreadable advertised base is refused' "cannot read origin's advertised default branch"

reset_fixture
export FM_TEST_NO_MISTAKES_FAIL=1
expect_refusal 'unreadable no-mistakes target is refused' 'no-mistakes status could not verify its PR target'

echo 'ALL TESTS PASSED'
