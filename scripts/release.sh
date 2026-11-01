#!/usr/bin/env bash
#
# Releases a new version of Bank Tracker: sets the app version, commits, tags vVERSION and
# pushes. The tag starts the Release workflow on GitHub Actions, which tests and builds the
# app and publishes it as a GitHub release.
# Run with --help for options.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PBXPROJ="$ROOT/BankTracker.xcodeproj/project.pbxproj"
BRANCH="main"
REMOTE="origin"

dry_run=false
build_first=true
version=""

usage() {
    cat <<EOF
Usage: scripts/release.sh [options] VERSION

Releases Bank Tracker VERSION, for example 0.2.0 or 1.0.0-beta.1:
  1. checks that $BRANCH is checked out, clean, and the same as $REMOTE/$BRANCH
  2. runs the tests and a Release build on this Mac
  3. sets the app version to VERSION and bumps the build number, then commits
     (skipped when the app already has VERSION and it hasn't been released yet)
  4. tags the commit vVERSION and pushes the commit and the tag

GitHub Actions then builds the app and publishes the release with the app attached.
A version with a suffix, like 1.0.0-beta.1, is published as a pre-release.

Options:
  -n, --dry-run     Run the checks and show what would happen, without changing anything
      --skip-build  Don't run the tests and build on this Mac first
  -h, --help        Show this help
EOF
}

fail() {
    echo "error: $*" >&2
    exit 1
}

step() {
    echo "==> $*"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run) dry_run=true; shift ;;
        --skip-build) build_first=false; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) fail "unknown option '$1' (see --help)" ;;
        *)
            [[ -z "$version" ]] || fail "give one version, not '$version' and '$1'"
            version="${1#v}"
            shift
            ;;
    esac
done

[[ -n "$version" ]] || { usage >&2; exit 1; }
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] ||
    fail "'$version' isn't a version like 1.2.3 or 1.2.3-beta.1"
tag="v$version"

cd "$ROOT"

# The project has a Debug and a Release configuration; both must agree.
setting() {
    local values
    values="$(sed -n -E "s/.*[[:<:]]$1 = ([^;]+);.*/\1/p" "$PBXPROJ" | sort -u)"
    [[ -n "$values" ]] || fail "$1 not found in ${PBXPROJ#"$ROOT"/}"
    [[ "$(wc -l <<<"$values" | tr -d ' ')" == 1 ]] ||
        fail "the configurations have different $1 values: $(tr '\n' ' ' <<<"$values")"
    echo "$values"
}

current_version="$(setting MARKETING_VERSION)"
current_build="$(setting CURRENT_PROJECT_VERSION)"
[[ "$current_build" =~ ^[0-9]+$ ]] || fail "the build number '$current_build' isn't a whole number"
next_build=$((current_build + 1))

step "Checking the repository"
[[ "$(git rev-parse --abbrev-ref HEAD)" == "$BRANCH" ]] ||
    fail "check out $BRANCH first (you're on $(git rev-parse --abbrev-ref HEAD))"
[[ -z "$(git status --porcelain)" ]] ||
    fail "commit or stash your changes first"
git fetch --quiet --tags "$REMOTE" "$BRANCH"
[[ "$(git rev-parse HEAD)" == "$(git rev-parse "$REMOTE/$BRANCH")" ]] ||
    fail "$BRANCH and $REMOTE/$BRANCH differ; pull or push first"
# A tag can leave out trailing zeros (v0.1 is 0.1.0), so check those spellings too.
candidates=("$tag")
short="$version"
while [[ "$short" =~ ^[0-9.]+\.0$ ]]; do
    short="${short%.0}"
    candidates+=("v$short")
done
for candidate in "${candidates[@]}"; do
    if git rev-parse --quiet --verify "refs/tags/$candidate" >/dev/null ||
        git ls-remote --exit-code --tags "$REMOTE" "refs/tags/$candidate" >/dev/null; then
        fail "$version is already released as $candidate"
    fi
done

# The numbers before any suffix can't go down: 1.0.0-beta.1 → 1.0.0 is fine, 1.2.0 → 1.1.0 isn't.
# Releasing the version the app already has (because it was never released) needs no new commit.
core() { echo "${1%%-*}"; }
bump=true
if [[ "$version" == "$current_version" ]]; then
    bump=false
else
    lowest="$(printf '%s\n%s\n' "$(core "$current_version")" "$(core "$version")" | sort -V | head -n 1)"
    [[ "$lowest" == "$(core "$current_version")" ]] ||
        fail "$version is lower than the current version, $current_version"
fi

if $build_first; then
    "$ROOT/scripts/build-mac.sh" --test
fi

# Where to watch the release happen, from the remote's URL.
remote_url="$(git remote get-url "$REMOTE")"
repo="$(sed -E 's#^(git@|ssh://git@|https://)github\.com[:/]##; s#\.git$##' <<<"$remote_url")"
web="https://github.com/$repo"

if $dry_run; then
    step "Dry run; nothing was changed. A release would:"
    if $bump; then
        echo "    set the version $current_version → $version and the build number $current_build → $next_build"
        echo "    commit \"Release $version\", tag it $tag, and push both to $REMOTE"
    else
        echo "    tag the current commit $tag (the app is already version $version) and push the tag to $REMOTE"
    fi
    echo "    then GitHub Actions would publish $web/releases/tag/$tag"
    exit 0
fi

if $bump; then
    step "Setting the version to $version (build $next_build)"
    sed -i '' -E \
        -e "s/([[:<:]]MARKETING_VERSION = )[^;]+;/\1$version;/" \
        -e "s/([[:<:]]CURRENT_PROJECT_VERSION = )[^;]+;/\1$next_build;/" \
        "$PBXPROJ"
    [[ "$(setting MARKETING_VERSION)" == "$version" && "$(setting CURRENT_PROJECT_VERSION)" == "$next_build" ]] ||
        fail "couldn't update the version in ${PBXPROJ#"$ROOT"/}; check it with git diff"
    git add "$PBXPROJ"
    git commit --quiet -m "Release $version"
    refs=("$BRANCH" "$tag")
    undo="git tag -d $tag && git reset --hard HEAD~1"
else
    refs=("$tag")
    undo="git tag -d $tag"
fi
git tag -a "$tag" -m "Bank Tracker $version"

step "Pushing ${refs[*]} to $REMOTE"
if ! git push --atomic "$REMOTE" "${refs[@]}"; then
    echo "error: the push failed. Nothing was published. To undo locally:" >&2
    echo "    $undo" >&2
    exit 1
fi

step "Released $tag. GitHub Actions is building it now:"
echo "    $web/actions/workflows/release.yml"
echo "    The release will appear at $web/releases/tag/$tag"
