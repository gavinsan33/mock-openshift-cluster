# Sourced by up.sh/down.sh/patch-gpu-node.sh. Auto-detects whether kind
# should use podman instead of docker, so you don't have to remember to set
# KIND_EXPERIMENTAL_PROVIDER=podman by hand every time (kind defaults to
# docker regardless of which one actually has your cluster/works on this
# machine, and silently fails against the wrong one instead of falling
# back).
if [ -z "${KIND_EXPERIMENTAL_PROVIDER:-}" ]; then
  if ! docker info >/dev/null 2>&1 && command -v podman >/dev/null 2>&1; then
    export KIND_EXPERIMENTAL_PROVIDER=podman
  fi
fi
