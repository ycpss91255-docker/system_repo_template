#!/usr/bin/env bash
# 端到端示範：本機 registry + 小映像，模擬「sub-repo 發布映像 → bot 升級 → release → 部署 / 回滾」。
# 需要：docker（含 compose 外掛）、just、git、curl。不會動到你的 docker 既有資源，結束時自動清除。
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${DEMO_REGISTRY_PORT:-5555}"; REG="localhost:$PORT"; export REGISTRY="$REG"
W="$(mktemp -d)"; fails=0

ok()      { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 | 預期=[$2] 實際=[$3]"; fails=$((fails+1)); fi; }
running() { docker ps --filter label=com.docker.compose.project=demo-system --filter "label=com.docker.compose.service=$1" --format '{{.Image}}'; }
cid()     { docker ps -q --filter label=com.docker.compose.project=demo-system --filter "label=com.docker.compose.service=$1"; }
build()   { docker build -q --build-arg "NAME=$1" --build-arg "VERSION=$2" -t "$REG/$1:$2" "$ROOT/demo" >/dev/null; }
cleanup() {
  docker ps -aq --filter label=com.docker.compose.project=demo-system | xargs -r docker rm -f >/dev/null 2>&1
  docker rm -f demo-registry >/dev/null 2>&1
  for t in alpha:1.0.0 alpha:1.1.0 alpha:1.2.0 alpha:dev-local beta:2.0.0 gamma:0.9.0; do docker rmi "$REG/$t" >/dev/null 2>&1; done
  rm -rf "$W"
}
trap cleanup EXIT
export GIT_AUTHOR_NAME=demo GIT_AUTHOR_EMAIL=demo@example.invalid GIT_COMMITTER_NAME=demo GIT_COMMITTER_EMAIL=demo@example.invalid

echo "== 0 準備：本機 registry + 5 個小映像（模擬各 sub-repo CI 的產出）"
docker run -d --name demo-registry -p "127.0.0.1:$PORT:5000" registry:2 >/dev/null
for _ in $(seq 20); do curl -fs "http://localhost:$PORT/v2/" >/dev/null && break; sleep 0.5; done
for m in alpha:1.0.0 alpha:1.1.0 alpha:1.2.0 beta:2.0.0 gamma:0.9.0; do build "${m%%:*}" "${m##*:}"; docker push -q "$REG/$m" >/dev/null; done

echo "== 1 開發端：just up（依 versions/dev.env）"
cp -r "$ROOT"/{compose.yaml,justfile,versions,configs,.gitignore} "$W/" && mkdir "$W/dev" && mv "$W"/{compose.yaml,justfile,versions,configs,.gitignore} "$W/dev/"
cd "$W/dev" && git init -q -b main && git add . && git commit -qm init
just up >/dev/null 2>&1
ok 1.alpha "$REG/alpha:1.0.0" "$(running alpha)"; ok 1.beta "$REG/beta:2.0.0" "$(running beta)"; ok 1.gamma "$REG/gamma:0.9.0" "$(running gamma)"

echo "== 2 bot：just bump alpha 1.1.0，再 just up"
just bump alpha 1.1.0 >/dev/null 2>&1; just up >/dev/null 2>&1
ok 2.alpha-升級 "$REG/alpha:1.1.0" "$(running alpha)"; ok 2.beta-不受影響 "$REG/beta:2.0.0" "$(running beta)"
git commit -qam "bump alpha 1.1.0"
just bump nosuch 1.0.0 >/dev/null 2>&1; ok 2.不存在的模組應失敗 "1" "$?"

echo "== 3 開發者 override：只替換自己正在改的模組"
build alpha dev-local; echo "ALPHA_TAG=dev-local" > override.env; just up >/dev/null 2>&1
ok 3.alpha-本機版 "$REG/alpha:dev-local" "$(running alpha)"; ok 3.beta-沿用dev.env "$REG/beta:2.0.0" "$(running beta)"; rm override.env

echo "== 4 release 規則"
sed -i 's/^ALPHA_TAG=.*/ALPHA_TAG=dev-local/' versions/dev.env
just release 1.0.0 >/dev/null 2>&1; ok 4.含非x.y.z的tag時拒絕release "1" "$?"; git checkout -q versions/dev.env
just release 1.0.0 >/dev/null 2>&1; ok 4.release成功 "0" "$?"; ok 4.tag存在 "v1.0.0" "$(git tag)"
just release 1.0.0 >/dev/null 2>&1; ok 4.重複release同版本被拒 "1" "$?"
git clone -q --bare "$W/dev" "$W/origin.git"

echo "== 5 部署目標（只有 git + just + docker）：clone 到 tag，就地部署"
just down >/dev/null 2>&1; docker rmi "$REG/alpha:1.1.0" "$REG/alpha:dev-local" "$REG/beta:2.0.0" "$REG/gamma:0.9.0" >/dev/null 2>&1
git -c advice.detachedHead=false clone -q --branch v1.0.0 "$W/origin.git" "$W/target"; cd "$W/target"
just deploy 1.0.0 target-01 >/dev/null 2>&1
ok 5.alpha "$REG/alpha:1.1.0" "$(running alpha)"; ok 5.beta "$REG/beta:2.0.0" "$(running beta)"; ok 5.gamma "$REG/gamma:0.9.0" "$(running gamma)"
ok 5.部署目標設定生效 "alpha 1.1.0 target=target-01 ip=10.0.0.11" "$(docker logs "$(cid alpha)" 2>&1 | tail -1)"
just version

echo "== 6 升級到 1.1.0，再回滾到 1.0.0"
cd "$W/dev"; just bump alpha 1.2.0 >/dev/null 2>&1; just release 1.1.0 >/dev/null 2>&1; git push -q "$W/origin.git" HEAD:main --tags
cd "$W/target"; git fetch -q --tags; git -c advice.detachedHead=false checkout -q v1.1.0
just deploy 1.1.0 target-01 >/dev/null 2>&1; ok 6.升級 "$REG/alpha:1.2.0" "$(running alpha)"
just deploy 1.0.0 target-01 >/dev/null 2>&1; ok 6.回滾 "$REG/alpha:1.1.0" "$(running alpha)"

echo "== 7 失敗保護：新版本有映像不存在時，現有容器不得被動到"
printf 'ALPHA_TAG=9.9.9\nBETA_TAG=2.0.0\nGAMMA_TAG=0.9.0\n' > versions/9.9.9.env
before="$(cid alpha)$(cid beta)$(cid gamma)"
just deploy 9.9.9 target-01 >/dev/null 2>&1; ok 7.deploy應失敗 "1" "$?"
ok 7.容器未被重建 "$before" "$(cid alpha)$(cid beta)$(cid gamma)"; ok 7.版本未變 "$REG/alpha:1.1.0" "$(running alpha)"

echo "== 8 另一個部署目標（不同設定）"
just deploy 1.0.0 target-02 >/dev/null 2>&1
ok 8.target-02設定 "alpha 1.1.0 target=target-02 ip=10.0.0.12" "$(docker logs "$(cid alpha)" 2>&1 | tail -1)"

echo; if [ "$fails" -eq 0 ]; then echo "全部通過"; else echo "失敗 $fails 項"; exit 1; fi
