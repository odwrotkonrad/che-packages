##[>] 🤖
consumes:
  - uri: gitlab.com/konradodwrot/cross-repo/misc
    type: gitRepository
    version: {{ env.Getenv "MISC_REF" }}
  - uri: gitlab.com/konradodwrot/cross-repo/prose/assets
    type: gitRepository
    version: {{ env.Getenv "PROSE_ASSETS_REF" }}
  - uri: gitlab.com/konradodwrot/cross-repo/prose/spec
    type: gitRepository
    version: {{ env.Getenv "PROSE_SPEC_REF" }}
  - uri: gitlab.com/konradodwrot/go-modules/che
    type: goModule
    version: {{ env.Getenv "GO_MODULES_CHE_REF" }}
  - uri: gitlab.com/konradodwrot/go-modules/che-schema
    type: file
    version: {{ env.Getenv "CHE_SCHEMA_REF" }}
  - uri: gitlab.com/konradodwrot/go-modules/che-packages-schema
    type: file
    version: {{ env.Getenv "CHE_PACKAGES_SCHEMA_REF" }}
  - uri: us-central1-docker.pkg.dev/staging-499418/ci/ci-linux
    type: ociImage
    version: {{ env.Getenv "OCI_IMAGES_CI_LINUX_REF" }}
  - uri: us-central1-docker.pkg.dev/staging-499418/ci/ci-linux-dind
    type: ociImage
    version: {{ env.Getenv "OCI_IMAGES_CI_LINUX_DIND_REF" }}
##[<] 🤖
