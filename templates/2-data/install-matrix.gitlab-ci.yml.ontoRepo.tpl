##[>] 🤖🤖
.install-package-list: &packages
{{- range $name, $_ := (file.Read "packages.yml" | data.YAML).packages }}
  - {{ $name }}
{{- end }}

#[what] one optional manual job per catalog package per arch: every method that package declares
#[why] the automatic tier already proves each method works; the full catalog is opt-in because these
#   dind matrix jobs flood the shared runner queue and starve every other repo's pipeline
.install-manual:
  extends: .install-base
  stage: test-install-manual
  variables:
    CHE_E2E_TIER: all
    METHOD: all
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event" || $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
      when: manual
      allow_failure: true
  #[why] the same make target a local run drives, differing only in the values passed: a matrix job
  #   carrying test logic of its own would let CI and a maintainer's machine prove different things
  script:
    - make test-install PACKAGE="$PACKAGE" METHOD="$METHOD" TARGET_OS=$TARGET_OS TARGET_ARCH=$TARGET_ARCH

test-install-package-amd64:
  extends: .install-manual
  image: $CI_IMAGE_DIND
  variables:
    TARGET_OS: linux
    TARGET_ARCH: amd64
  parallel:
    matrix:
      - PACKAGE: *packages

test-install-package-arm64:
  extends: .install-manual
  image: $CI_IMAGE_DIND_ARM64
  tags:
    - gke-linux-arm64-small
  variables:
    TARGET_OS: linux
    TARGET_ARCH: arm64
  parallel:
    matrix:
      - PACKAGE: *packages
##[<] 🤖🤖
