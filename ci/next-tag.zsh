#!/usr/bin/env zsh
##[>] 🤖🤖
# Compute the next release tag for the catalog: the highest existing vX.Y.Z with
# its patch raised, or v0.0.1 when the repo carries no version tag yet. Prints
# the tag to stdout.
#
# Tags here are bare vX.Y.Z, not <module>/vX.Y.Z: this repo publishes one thing.
emulate -LR zsh
setopt errexit pipefail

API="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/repository/tags?per_page=100&order_by=version&sort=desc&search=^v"

fetch() {
  curl -fsSL --connect-timeout 30 --retry 10 --retry-delay 30 --retry-all-errors \
    --header "JOB-TOKEN: ${CI_JOB_TOKEN}" "$1"
}

#[why] sorted numerically per field, not by the API's version order: a lexical or partial
#   ordering puts v0.0.9 above v0.0.10 and the next release would collide with an existing tag
LATEST=$(
  fetch "$API" \
    | grep -oE '"name":"v[0-9]+\.[0-9]+\.[0-9]+"' \
    | sed -E 's|.*"v([0-9]+\.[0-9]+\.[0-9]+)"|\1|' \
    | sort -t. -k1,1n -k2,2n -k3,3n \
    | tail -1
)

if [[ -z "$LATEST" ]] {
  print -r -- "v0.0.1"
  exit 0
}

MAJOR=${LATEST%%.*}
REST=${LATEST#*.}
MINOR=${REST%%.*}
PATCH=${REST#*.}
print -r -- "v${MAJOR}.${MINOR}.$((PATCH + 1))"
##[<] 🤖🤖
