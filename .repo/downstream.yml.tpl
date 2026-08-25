##[>] 🤖
downstream:
  - uri: gitlab.com/konradodwrot/che-packages
    type: gitRepository
    versionEnvVar: CHE_PACKAGES_REF
    version: {{ env.Getenv "CHE_PACKAGES_REF" }}
##[<] 🤖
