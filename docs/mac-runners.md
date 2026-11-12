# Running other repos' CI on the Mac

Buck Fifty's jobs run on a self-hosted runner on Jason's always-on Mac (README, "Self-hosted Mac runner").
`Scripts/mac-runner.sh` sets up the same thing for any other repository, so its Actions minutes come off the Mac too.

## One runner per repo, or one shared?

A runner registered on a **personal account's** repository serves only that repository. GitHub has no account-wide
runners for personal accounts. That leaves two ways:

- **One runner per repo (recommended).** The script registers a separate runner, in its own folder
  (`~/actions-runners/OWNER-REPO`) with its own name and service, for each repository. Nothing else changes: the repos
  stay where they are, and adding or removing one doesn't touch the others. Several runners on one Mac can run jobs
  at the same time, which is usually fine; if two iOS builds fighting over the simulator becomes a problem, see
  "Clashing jobs" below.
- **One shared runner, through an organization.** Create a free GitHub organization, transfer the repos into it, and
  register a single runner at the organization (Organization › Settings › Actions › Runners). Every repo in it can
  use that runner, one job at a time. The cost is moving the repos: their URLs change (GitHub redirects the old
  ones), and anything that names `jsonify/...` (App Store Connect, other tooling, clones) has to follow. Only worth
  it for many repos.

Stick with one per repo unless there are more than a handful.

## Before the first one

On the Mac, once (the README's steps 1 and 2 for Buck Fifty): Xcode selected and its license accepted, Homebrew,
whatever tools the repo's jobs need (`brew install xcodegen`, …), and optionally the GitHub CLI (`brew install gh`,
then `gh auth login`) so the script can fetch registration tokens itself. Keep the Mac awake and logged in
(automatic login and "Prevent automatic sleeping" if it must come back from a reboot by itself); the runners are
LaunchAgents, so they run while that user is logged in.

## Adding a repo

```sh
cd ~/path/to/buck-fifty           # or copy Scripts/mac-runner.sh anywhere and run it from there
Scripts/mac-runner.sh add jsonify/other-app
Scripts/mac-runner.sh protect jsonify/other-app   # public repos: require approval for fork PRs
Scripts/mac-runner.sh workflow                    # prints the workflow lines to paste
```

`add` downloads the newest runner (checking its SHA-256 against the release notes), gets a registration token,
registers a runner named `<Mac name>-other-app` with the labels `self-hosted`, `macOS` and the architecture, saves your
`PATH` (plus Homebrew's) for the service, and installs and starts it as a LaunchAgent. It should show **Idle** under
the repo's Settings › Actions › Runners. Options: `--name NAME`, `--labels extra,labels`.

Without `gh`, the script asks you to paste a token: the repo's Settings › Actions › Runners › **New self-hosted
runner** › macOS shows a Configure command; copy the value after `--token`. It's single-use and expires in an hour.
No token or secret is saved anywhere except the runner's own folder.

Other commands:

| Command | Does |
| --- | --- |
| `list` | every runner service on this Mac, running or stopped |
| `status OWNER/REPO` | that runner's service state |
| `remove OWNER/REPO` | stops and uninstalls the service, unregisters the runner (another token), and offers to delete its folder |

Buck Fifty's own runner predates the script and lives in `~/actions-runner`; pass `--dir ~/actions-runner` to
`status` or `remove` for it.

## The workflow change

In each job that should run on the Mac (this is what Buck Fifty's `ci.yml` does):

```yaml
jobs:
  build:
    # The self-hosted Mac. Set the repository variable MAC_RUNNER to "macos-latest" (quotes included) to go back to
    # GitHub's runners.
    runs-on: ${{ fromJSON(vars.MAC_RUNNER || '["self-hosted","macOS"]') }}
    # A self-hosted runner on a public repo: never run a fork's pull request on it.
    if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository
```

A plain `runs-on: [self-hosted, macOS]` works too; the `MAC_RUNNER` form just gives a switch back to GitHub's
runners without editing the workflow.

## Public repos: keep strangers off the Mac

A self-hosted runner runs whatever the workflow tells it to, as you, on your Mac. On a public repo anyone can open a
pull request from a fork, and that PR can change the workflow. Two locks, both needed:

1. **The `if:` line above**, so fork PRs never schedule a job on the Mac.
2. **Require approval for fork PR workflows**: `Scripts/mac-runner.sh protect OWNER/REPO`, or by hand in the repo's
   Settings › Actions › General › "Approval for running fork pull request workflows from contributors" ›
   **Require approval for all external contributors**.

Also avoid `pull_request_target` workflows on the Mac (they run with the base repo's secrets on fork PRs). Private
repos are safer by default, since only people you invite can push or fork, but the same settings do no harm.

## Clashing jobs

Every runner on the Mac shares one Xcode and one set of simulators, and runners from different repos don't know
about each other, so two repos can build at once. That's usually fine, just slower. If it causes flaky screenshots,
the fix is the shared organization runner above (one runner runs one job at a time), or giving each repo's
screenshot step its own simulator (Buck Fifty's `Scripts/screenshots.sh` reuses whichever one is booted). Each
runner's logs are in `~/Library/Logs/actions.runner.*`.
