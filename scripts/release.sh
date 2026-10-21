#!/usr/bin/env bash
# Tests, bumps the version, commits, tags, pushes, publishes a GitHub Release and installs.
#
#   scripts/release.sh [patch|minor|major] ["release notes summary"]
#
# The first release (no v* tag yet) ships the version already in project.yml (0.1.0).
set -euo pipefail
cd "$(dirname "$0")/.."

PART="${1:-patch}"
SUMMARY="${2:-}"
case "$PART" in patch | minor | major) ;; *) echo "usage: $0 [patch|minor|major] [summary]" >&2; exit 2 ;; esac

command -v gh >/dev/null || { echo "gh is required (brew install gh)" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh is not authenticated; run: gh auth login" >&2; exit 1; }

echo "Running tests…" >&2
swift test --package-path Packages/SwitchesCore

current="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([0-9.]*\)"\{0,1\}.*/\1/p' project.yml | head -1)"
build="$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *\([0-9]*\).*/\1/p' project.yml | head -1)"
previous_tag="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"

if [[ -z "$previous_tag" ]]; then
  version="$current"
else
  IFS=. read -r major minor patch <<<"$current"
  case "$PART" in
    major) version="$((major + 1)).0.0" ;;
    minor) version="$major.$((minor + 1)).0" ;;
    patch) version="$major.$minor.$((patch + 1))" ;;
  esac
  build=$((build + 1))
fi
tag="v$version"
git rev-parse "$tag" >/dev/null 2>&1 && { echo "Tag $tag already exists" >&2; exit 1; }

sed -i '' -E "s/^( *MARKETING_VERSION: *)\"?[0-9.]+\"?/\1\"$version\"/" project.yml
sed -i '' -E "s/^( *CURRENT_PROJECT_VERSION: *)[0-9]+/\1$build/" project.yml

echo "Building $tag…" >&2
scripts/build_release.sh

git add -A
git commit -m "Release $tag${SUMMARY:+: $SUMMARY}" || true
git tag -a "$tag" -m "Switches $version"
git push origin HEAD --tags

mkdir -p dist
zip="dist/Switches-$version.zip"
rm -f "$zip"
ditto -c -k --keepParent build/Switches.app "$zip"

if [[ -z "$previous_tag" ]]; then
  gh release create "$tag" "$zip" --title "Switches $version" --generate-notes
else
  notes="$(git log "$previous_tag..HEAD" --pretty='- %s' --no-merges | grep -v '^- Release v' || true)"
  [[ -n "$SUMMARY" ]] && notes="$SUMMARY"$'\n\n'"$notes"
  gh release create "$tag" "$zip" --title "Switches $version" --notes "${notes:-Maintenance release.}"
fi

scripts/install_local.sh
echo "Released $tag"
