#!/usr/bin/env zsh
##[>] 🤖🤖
# Cut the next catalog release at a commit. Computes the tag via next-tag.zsh,
# builds notes from the git log since the previous tag, then calls
# glab release create.
#
# glab release create, not git tag: it mints the tag and the release object in
# one call. The publish job links its artifacts to that release, and a tag
# without one makes every link 404.
#
# Args: $1 ref/SHA (default: HEAD).
emulate -LR zsh
setopt errexit pipefail

REF="${1:-$(git rev-parse HEAD)}"
ROOT=$(git rev-parse --show-toplevel)

TAG=$("${ROOT}/ci/next-tag.zsh")
VERSION="${TAG#v}"

PREV=$(git tag --list 'v*' --sort=-version:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)
if [[ -n "$PREV" ]] {
  NOTES=$(git log --no-merges --format='- %s' "${PREV}..${REF}" 2>/dev/null || true)
} else {
  NOTES=$(git log --no-merges --format='- %s' "$REF" 2>/dev/null || true)
}
NOTES="che-packages ${VERSION}"$'\n\n'"${NOTES:-}"

print -r -- "tagging ${TAG} at ${REF}"
glab release create "$TAG" \
  --name "che-packages ${VERSION}" \
  --ref "$REF" \
  --notes "$NOTES"
##[<] 🤖🤖
