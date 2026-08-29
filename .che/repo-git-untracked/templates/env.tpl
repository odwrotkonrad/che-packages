##[>] 🤖🤖
{{ localFile ".repo/upstream.env" | alwaysUpdate }}
ARTIFACT_REGISTRY={{ shell "glab variable get -g konradodwrot GRP_KO_VAR_ARTIFACT_REGISTRY" }}
ARTIFACT_REGISTRY_PROXY_DOCKERHUB={{ shell "glab variable get -g konradodwrot GRP_KO_VAR_ARTIFACT_REGISTRY_PROXY_DOCKERHUB" }}
##[<] 🤖🤖
