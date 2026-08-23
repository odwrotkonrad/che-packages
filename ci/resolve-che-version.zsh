#!/usr/bin/env zsh
##[>] 🤖🤖
# Resolves the che a merge-request pipeline should test against: the newest
# published 0.0.0-mr<iid> prerelease whose go-modules merge request is still
# open, else nothing. Writes a make-includable fragment to $1 (default
# .user/che-pin.resolved.env), setting CHE_VERSION and CHE_PACKAGES_SCHEMA_REF
# together: a binary and the schema its vocabulary comes from must be the same
# code, or validating proves nothing about installing. Nothing resolved means an
# empty file, leaving che-pin.env's values standing.
#
# Both halves are the same 0.0.0-mr<iid> string: go-modules publishes its
# schemas at the MR's prerelease version too, so no raw git ref survives here.
#
# Best-effort throughout, mirroring configs' 00-ci-deps.zsh: a prerelease is a
# convenience, never a reason to redden a pipeline that is not about che. Every
# lookup failure falls through to the pin.
set -eu

OUT="${1:-.user/che-pin.resolved.env}"
GO_MODULES_API='https://gitlab.com/api/v4/projects/konradodwrot%2Fgo-modules'
CURL=(curl -fsSL --connect-timeout 30 --retry 10 --retry-delay 30 --retry-all-errors)

mkdir -p "${OUT:h}"

#[why] the output is a make prerequisite: rewriting it unconditionally would advance its mtime on
#   every run and re-fetch the binary and schema each time. only a changed resolution touches it
TMP="${OUT}.tmp"
: > "$TMP"
fn_commit() {
  if { [[ -f $OUT ]] && cmp -s "$TMP" "$OUT" } {
    rm -f "$TMP"
  } else {
    mv -f "$TMP" "$OUT"
  }
}
trap fn_commit EXIT

#[why] the pin is what a default-branch or tag pipeline releases against: only a merge request,
#   which releases nothing, may test against unmerged che
if [[ ${CI_PIPELINE_SOURCE:-} != merge_request_event ]] {
  print 'resolve-che-version: not a merge-request pipeline, using che-pin.env'
  exit 0
}

#[why] a real json parser, never sed or tr on the raw response: an MR description is free text
#   carrying braces, quotes and newlines that any line-tool pass would split mid-record. python is
#   stdlib-only here and is present wherever this runs, unlike jq or yq
fn_json_field() {
  python3 -c "$1" 2> /dev/null
}

#[what] one open MR iid per line, newest first
#[why] the iid alone: it keys the che prerelease and the schema prereleases alike, so nothing here
#   needs the commit sha any more
fn_open_mrs() {
  $CURL "${GO_MODULES_API}/merge_requests?state=opened&per_page=100" 2> /dev/null |
    fn_json_field 'import json,sys
for m in json.load(sys.stdin): print(m["iid"])'
}

#[what] published che prerelease versions, newest first
fn_prerelease_versions() {
  $CURL "${GO_MODULES_API}/packages?package_name=che&order_by=created_at&sort=desc&per_page=100" 2> /dev/null |
    fn_json_field 'import json,re,sys
for p in json.load(sys.stdin):
    if re.fullmatch(r"0\.0\.0-mr[0-9]+", p["version"]): print(p["version"])'
}

#[why] a real array of whole iids, never the raw scalar: (Ie) on a scalar matches substrings, so
#   open MR !420 would wrongly claim !42's prerelease
typeset -a open_iids
open_iids=(${(f)"$(fn_open_mrs)"}) || open_iids=()
if (( ! ${#open_iids} )) {
  print 'resolve-che-version: no open go-modules merge requests, using che-pin.env'
  exit 0
}

#[why] created_at desc: the first match walking down is the newest published prerelease
for version in ${(f)"$(fn_prerelease_versions)"}; {
  iid=${version#0.0.0-mr}
  if (( ${open_iids[(Ie)$iid]} )) {
    print -r -- "CHE_VERSION=${version}" >> "$TMP"
    print -r -- "CHE_PACKAGES_SCHEMA_REF=${version}" >> "$TMP"
    print -r -- "CHE_SCHEMA_REF=${version}" >> "$TMP"
    print "resolve-che-version: using che prerelease ${version} (go-modules MR !${iid}), schema at the same version"
    exit 0
  }
}

print 'resolve-che-version: no open-MR che prerelease, using che-pin.env'
##[<] 🤖🤖
