#!/bin/bash
# Runs as root on the SSM target. Inputs are validated again here.
set -euo pipefail
image=${1:?Supply an ECR image digest}
region=${2:?Supply the AWS region}
[[ "$image" =~ ^[0-9]{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com/[a-z0-9/_-]+@sha256:[a-f0-9]{64}$ ]]
[[ "$region" =~ ^[a-z]{2}-[a-z]+-[0-9]+$ ]]
test -f /var/lib/incident-host-ready
exec 9>/var/lock/incident-release.lock
flock -n 9 || { echo 'Another release is running'; exit 1; }
registry=${image%%/*}
auth_dir=$(mktemp -d)
export DOCKER_CONFIG="$auth_dir"
switched=false
had_previous=false
finished=false
cleanup() {
  result=$?
  trap - EXIT
  docker rm -f incident-candidate >/dev/null 2>&1 || true
  if [[ "$switched" == true && "$finished" == false ]]; then
    docker rm -f incident-api >/dev/null 2>&1 || true
    if [[ "$had_previous" == true ]]; then
      docker rename incident-previous incident-api
      docker start incident-api
      if ! healthy incident-api; then
        echo 'ROLLBACK FAILED: investigate container logs immediately' >&2
      else
        echo 'Previous container restored' >&2
      fi
    fi
  fi
  rm -rf "$auth_dir"
  exit "$result"
}
trap cleanup EXIT
healthy() {
  for attempt in {1..30}; do
    if [[ $(docker inspect --format '{{.State.Health.Status}}' "$1" 2>/dev/null || true) == healthy ]]; then
      return 0
    fi
    sleep 2
  done
  docker logs --tail=30 "$1" >&2 || true
  return 1
}
launch() {
  docker run -d --name "$1" --restart unless-stopped \
    -p "127.0.0.1:$2:8080" -v incident-data:/data \
    --read-only --tmpfs /tmp --cap-drop ALL \
    --security-opt no-new-privileges:true --memory 256m --cpus 0.5 \
    --log-opt max-size=10m --log-opt max-file=3 \
    -e "APP_VERSION=${image##*@}" "$image"
}
aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$registry"
docker pull "$image"
# Only one release owns these names. A leftover previous container requires review.
if docker inspect incident-previous >/dev/null 2>&1; then
  echo 'Previous release residue found: inspect incident-previous before proceeding' >&2
  exit 1
fi
docker rm -f incident-candidate >/dev/null 2>&1 || true
launch incident-candidate 18080
healthy incident-candidate
docker rm -f incident-candidate
if docker inspect incident-api >/dev/null 2>&1; then
  docker rename incident-api incident-previous
  had_previous=true
  switched=true
  docker stop incident-previous
fi
switched=true
launch incident-api 8080
healthy incident-api
finished=true
if [[ "$had_previous" == true ]]; then docker rm incident-previous; fi
mkdir -p /var/lib/incident-deploy
printf '%s %s\n' "$(date -u +%FT%TZ)" "$image" >> /var/lib/incident-deploy/history.log
echo "Release healthy: $image"
