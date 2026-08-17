#!/usr/bin/env zsh
##[>] 🤖🤖
# Tag-pipeline publish for the catalog. Derives the version from $CI_COMMIT_TAG
# (v<version>), tars packages.yml + scripts/ into
# che-packages_<version>.tar.gz with a sha256 checksums.txt, uploads both to the
# generic package registry at packages/generic/che-packages/<version>/ and links
# them as release assets, then refreshes the moving latest/ alias: a de-versioned
# tarball plus version.txt, which `che packages update` reads to resolve the
# newest version.
set -eu

TAG="${CI_COMMIT_TAG:?}"
MODULE="che-packages"
MODULE_VERSION="${TAG#v}"

NAME="${MODULE}_${MODULE_VERSION}.tar.gz"
mkdir -p dist
tar -czf "dist/${NAME}" packages.yml scripts
( cd dist && sha256sum -- "$NAME" > checksums.txt )

PKG="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/${MODULE}/${MODULE_VERSION}"
TAG_ENC="${TAG//\//%2F}"

#[why] the asset links below attach to a release, and nothing else creates one here: without this
#   every link POST 404s, and since curl -f makes that fatal the job dies before uploading
#   checksums.txt and the latest/ alias, which are what consumers actually read
echo "creating release ${TAG}"
curl -fsSL --connect-timeout 30 --retry 5 --retry-delay 10 --request POST --header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
  --data-urlencode "tag_name=${TAG}" \
  --data-urlencode "name=${MODULE} ${MODULE_VERSION}" \
  --data-urlencode "description=Package catalog ${MODULE_VERSION}: packages.yml and its install scripts." \
  "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/releases" ||
  echo "release ${TAG} already exists or could not be created, continuing"
echo

for f in "dist/${NAME}" dist/checksums.txt; do
  FILE_NAME="${f:t}"
  TYPE=other
  if [[ "$FILE_NAME" == *.tar.gz ]] TYPE=package
  echo "uploading ${FILE_NAME} (${TYPE})"
  curl -fsSL --connect-timeout 30 --retry 10 --retry-delay 30 --header "JOB-TOKEN: ${CI_JOB_TOKEN}" --upload-file "$f" "${PKG}/${FILE_NAME}"
  echo
  #[why] never fatal: the artifact is already in the registry, which is where che reads it from.
  #   a failed release link must not cost us checksums.txt and the latest/ alias below
  curl -fsSL --connect-timeout 30 --retry 10 --retry-delay 30 --request POST --header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
    --data-urlencode "name=${FILE_NAME}" \
    --data-urlencode "url=${PKG}/${FILE_NAME}" \
    --data-urlencode "link_type=${TYPE}" \
    "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/releases/${TAG_ENC}/assets/links" ||
    echo "could not link ${FILE_NAME} to release ${TAG}, artifact is in the registry regardless"
  echo
done

ALIAS="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/${MODULE}/latest"
echo "aliasing ${NAME} -> latest"
curl -fsSL --connect-timeout 30 --retry 10 --retry-delay 30 --header "JOB-TOKEN: ${CI_JOB_TOKEN}" --upload-file "dist/${NAME}" "${ALIAS}/${MODULE}_latest.tar.gz"
echo
print -r -- "$MODULE_VERSION" > dist/version.txt
echo "uploading latest/version.txt (${MODULE_VERSION})"
curl -fsSL --connect-timeout 30 --retry 10 --retry-delay 30 --header "JOB-TOKEN: ${CI_JOB_TOKEN}" --upload-file dist/version.txt "${ALIAS}/version.txt"
echo
##[<] 🤖🤖
