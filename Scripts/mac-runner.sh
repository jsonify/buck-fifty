#!/usr/bin/env bash
# Scripts/mac-runner.sh: set up (and take down) GitHub Actions self-hosted runners on this Mac, one per repository,
# the same way Buck Fifty's runner was set up (README, "Self-hosted Mac runner"). See docs/mac-runners.md.
#
#   Scripts/mac-runner.sh add    OWNER/REPO [--name NAME] [--labels a,b]   register a runner and start it as a service
#   Scripts/mac-runner.sh remove OWNER/REPO [--dir DIR]                    stop it, unregister it, delete its folder
#   Scripts/mac-runner.sh status OWNER/REPO [--dir DIR]                    the service's state
#   Scripts/mac-runner.sh list                                             every runner service on this Mac
#   Scripts/mac-runner.sh protect OWNER/REPO                               require approval for fork PR workflows
#   Scripts/mac-runner.sh workflow                                         print the runs-on / fork-skip lines to paste
#
# Each repository gets its own runner in its own folder, ~/actions-runners/OWNER-REPO (RUNNERS_HOME changes the
# parent), named "<this Mac>-REPO". Runners registered on a personal account belong to one repository each; only an
# organization can share one runner between repositories (docs/mac-runners.md explains the choice).
#
# Registration needs a short-lived token. With the GitHub CLI (`brew install gh`, then `gh auth login`) the script
# asks GitHub for it. Without gh, it asks you to paste the token from the repository's
# Settings › Actions › Runners › New self-hosted runner page (the value after --token). Nothing is stored except
# what the runner itself keeps in its folder; no secret goes in this script or in the repository.
#
# The service is a LaunchAgent (the runner's own svc.sh): it runs while you're logged in and comes back at login,
# so turn on automatic login and stop the Mac sleeping if it must survive a reboot unattended.

set -euo pipefail

RUNNERS_HOME="${RUNNERS_HOME:-$HOME/actions-runners}"

die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

have_gh() { command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; }

# "owner/repo" only: letters, digits, '.', '-' and '_', so it's safe in paths and URLs.
check_repo() {
  [[ "${1:-}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "expected OWNER/REPO, got '${1:-}'"
}

runner_dir() { printf '%s/%s\n' "$RUNNERS_HOME" "${1/\//-}"; }

# A registration or removal token (kind = registration-token | remove-token), from gh or pasted by you.
get_token() {
  local repo="$1" kind="$2" token=""
  if have_gh; then
    token="$(gh api -X POST "repos/$repo/actions/runners/$kind" --jq .token 2>/dev/null)" || token=""
    [[ -n "$token" ]] || warn "gh couldn't get a $kind for $repo (you need admin rights on it)."
  fi
  if [[ -z "$token" ]]; then
    {
      echo "Open https://github.com/$repo/settings/actions/runners"
      if [[ "$kind" == registration-token ]]; then
        echo "› New self-hosted runner › macOS, and copy the value after --token in the Configure step."
      else
        echo "› click the runner › Remove, and copy the value after --token."
      fi
      echo "It's single-use and expires in an hour."
    } >&2
    read -r -s -p "Token: " token </dev/tty; echo >&2
  fi
  [[ -n "$token" ]] || die "no token"
  printf '%s' "$token"
}

# The runner's architecture name for this Mac.
runner_arch() {
  case "$(uname -m)" in
    arm64)  echo osx-arm64 ;;
    x86_64) echo osx-x64 ;;
    *) die "unsupported CPU $(uname -m)" ;;
  esac
}

# Download and unpack the newest runner into $1, checking its SHA-256 against the release notes when they list it.
download_runner() {
  local dir="$1" arch release version url tarball expected actual
  arch="$(runner_arch)"
  release="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest)" \
    || die "couldn't reach api.github.com to find the latest runner"
  version="$(printf '%s' "$release" | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -1)"
  [[ -n "$version" ]] || die "couldn't read the latest runner version"
  url="https://github.com/actions/runner/releases/download/v$version/actions-runner-$arch-$version.tar.gz"
  tarball="$dir/runner.tar.gz"
  note "Downloading runner $version ($arch)"
  curl -fsSL -o "$tarball" "$url" || die "download failed: $url"
  # The release notes carry each package's hash between <!-- BEGIN SHA osx-arm64 --> and <!-- END SHA ... -->.
  expected="$(printf '%s' "$release" | grep -o "BEGIN SHA $arch -->[0-9a-f]*" | head -1 | sed 's/.*-->//')" || true
  actual="$(shasum -a 256 "$tarball" | cut -d' ' -f1)"
  if [[ -n "$expected" ]]; then
    [[ "$expected" == "$actual" ]] || { rm -f "$tarball"; die "checksum mismatch for $url"; }
    note "Checksum OK"
  else
    warn "the release notes don't list a checksum for $arch; skipping the check (sha256 $actual)"
  fi
  tar -xzf "$tarball" -C "$dir"
  rm -f "$tarball"
}

cmd_add() {
  local repo="$1"; shift
  local name labels="" dir token
  name="$(scutil --get LocalHostName 2>/dev/null || hostname -s)-${repo#*/}"
  while (($#)); do
    case "$1" in
      --name)   name="${2:?--name needs a value}"; shift 2 ;;
      --labels) labels="${2:?--labels needs a value}"; shift 2 ;;
      *) die "unknown option $1" ;;
    esac
  done
  [[ "$(uname -s)" == Darwin ]] || die "this sets up a macOS runner; run it on the Mac"
  dir="$(runner_dir "$repo")"
  [[ -e "$dir/.runner" ]] && die "$dir already holds a configured runner; '$0 remove $repo' first"

  command -v xcodebuild >/dev/null 2>&1 || warn "no Xcode found; iOS jobs need it (README, Self-hosted Mac runner, step 1)"

  mkdir -p "$dir"
  download_runner "$dir"

  token="$(get_token "$repo" registration-token)"
  note "Registering '$name' with $repo"
  # The runner adds the labels self-hosted, macOS and the architecture (ARM64 or X64) itself; --labels adds more.
  (cd "$dir" && ./config.sh --unattended --replace \
      --url "https://github.com/$repo" --token "$token" \
      --name "$name" --work _work ${labels:+--labels "$labels"})

  # The service starts with the PATH in .path. Give it this shell's PATH plus Homebrew's, so jobs find
  # xcodegen, brew and friends.
  local path="$PATH"
  for p in /opt/homebrew/bin /usr/local/bin; do
    [[ ":$path:" == *":$p:"* ]] || path="$p:$path"
  done
  printf '%s\n' "$path" > "$dir/.path"

  note "Installing and starting the service"
  (cd "$dir" && ./svc.sh install && ./svc.sh start && ./svc.sh status)

  cat <<EOF

Done. The runner should show Idle at https://github.com/$repo/settings/actions/runners
Next:
  - Point the workflows at it:      $0 workflow
  - If the repository is public:    $0 protect $repo
EOF
}

# Find a runner's folder: the one this script made, or --dir for one made by hand (Buck Fifty's is ~/actions-runner).
resolve_dir() {
  local repo="$1"; shift
  local dir; dir="$(runner_dir "$repo")"
  while (($#)); do
    case "$1" in
      --dir) dir="${2:?--dir needs a value}"; shift 2 ;;
      *) die "unknown option $1" ;;
    esac
  done
  [[ -x "$dir/config.sh" ]] || die "no runner in $dir (pass --dir for one set up elsewhere)"
  printf '%s\n' "$dir"
}

cmd_remove() {
  local repo="$1"; shift
  local dir token answer
  dir="$(resolve_dir "$repo" "$@")"
  note "Stopping and uninstalling the service in $dir"
  (cd "$dir" && { ./svc.sh stop || true; } && { ./svc.sh uninstall || true; })
  if [[ -e "$dir/.runner" ]]; then
    token="$(get_token "$repo" remove-token)"
    note "Unregistering from $repo"
    (cd "$dir" && ./config.sh remove --token "$token")
  fi
  read -r -p "Delete $dir and its work folder? [y/N] " answer </dev/tty
  if [[ "$answer" =~ ^[Yy] ]]; then rm -rf "$dir"; note "Deleted $dir"; fi
}

cmd_status() {
  local dir; dir="$(resolve_dir "$@")"
  (cd "$dir" && ./svc.sh status)
}

cmd_list() {
  local found=0 plist
  for plist in "$HOME"/Library/LaunchAgents/actions.runner.*.plist; do
    [[ -e "$plist" ]] || continue
    found=1
    local label; label="$(basename "$plist" .plist)"
    if launchctl list "$label" >/dev/null 2>&1; then echo "running  $label"; else echo "stopped  $label"; fi
  done
  ((found)) || echo "No runner services on this Mac."
}

# Require approval before workflows from outside contributors' forks run, the second lock after the workflow's
# fork check. Falls back to telling you where the setting is.
cmd_protect() {
  local repo="$1" visibility=""
  if have_gh; then
    visibility="$(gh api "repos/$repo" --jq .visibility 2>/dev/null || true)"
    [[ "$visibility" == private ]] && note "$repo is private: forks can't run on your runner unless you allow it. Setting approval anyway."
    if gh api -X PUT "repos/$repo/actions/permissions/fork-pr-contributor-approval" \
        -f approval_policy=all_external_contributors >/dev/null 2>&1; then
      note "$repo now requires approval for every fork pull request workflow from external contributors"
      return
    fi
    warn "gh couldn't change the setting (needs admin rights, or the API differs)"
  fi
  cat <<EOF
Set it by hand: https://github.com/$repo/settings/actions
  › "Approval for running fork pull request workflows from contributors"
  › Require approval for all external contributors › Save
EOF
}

cmd_workflow() {
  cat <<'EOF'
# In each job of .github/workflows/*.yml that should run on the Mac:
    # The self-hosted Mac. Set the repository variable MAC_RUNNER to "macos-latest" (quotes included) to go back
    # to GitHub's runners.
    runs-on: ${{ fromJSON(vars.MAC_RUNNER || '["self-hosted","macOS"]') }}
    # A self-hosted runner on a public repo: never run a fork's pull request on it.
    if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository

EOF
}

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    add|remove|status|protect) check_repo "${1:-}"; "cmd_$cmd" "$@" ;;
    list|workflow) "cmd_$cmd" ;;
    -h|--help|help|"") usage 0 ;;
    *) printf 'unknown command %s\n\n' "$cmd" >&2; usage 1 ;;
  esac
}

main "$@"
