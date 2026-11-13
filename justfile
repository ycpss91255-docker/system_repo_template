# system repo 統一入口。部署目標只需要 just / docker / git。
set shell := ["bash", "-euo", "pipefail", "-c"]

# 映像倉庫位置、部署目標（可用環境變數覆蓋）
export REGISTRY := env_var_or_default("REGISTRY", "localhost:5555")
export TARGET   := env_var_or_default("TARGET", "target-01")

default:
    @just --list --unsorted

# ───────── 開發 / CI ─────────

# 依 versions/dev.env 啟動整套；若存在 override.env（只寫你要改的，例如 ALPHA_TAG=dev-local）則覆蓋
up:
    #!/usr/bin/env bash
    set -euo pipefail
    args=(--env-file versions/dev.env)
    [ -f override.env ] && args+=(--env-file override.env)
    docker compose "${args[@]}" up -d --remove-orphans --pull missing

down:
    docker compose --env-file versions/dev.env down

# bot 呼叫：更新某模組在 dev.env 的版本。例：just bump alpha 1.4.0
bump module tag:
    grep -q "^{{uppercase(module)}}_TAG=" versions/dev.env
    sed -i -E 's/^{{uppercase(module)}}_TAG=.*/{{uppercase(module)}}_TAG={{tag}}/' versions/dev.env
    @echo "dev.env: {{uppercase(module)}}_TAG={{tag}}"

# ───────── Release ─────────

# 把 dev.env 凍結成 versions/<版本>.env 並打 tag。既有 release 檔不可覆蓋；所有 tag 必須是 x.y.z
release version:
    test ! -f "versions/{{version}}.env" || { echo "拒絕：versions/{{version}}.env 已存在（release 不可改）" >&2; exit 1; }
    bad=$(grep -vE '^[A-Z]+_TAG=[0-9]+\.[0-9]+\.[0-9]+$' versions/dev.env || true); [ -z "$bad" ] || { echo "拒絕：dev.env 有非 x.y.z 的 tag：$bad" >&2; exit 1; }
    cp versions/dev.env "versions/{{version}}.env"
    git add "versions/{{version}}.env"
    git commit -q -m "release {{version}}"
    git tag "v{{version}}"
    @echo "已建立 tag v{{version}}（尚未 push）"

# ───────── 部署 ─────────

# 依 release 版本檔部署。先把全部映像 pull 成功，才會 up；任何一個 pull 失敗就不動現有容器
deploy release target="target-01":
    test -f "versions/{{release}}.env"
    TARGET={{target}} docker compose --env-file "versions/{{release}}.env" pull --quiet
    TARGET={{target}} docker compose --env-file "versions/{{release}}.env" up -d --remove-orphans --pull never
    echo "{{release}} {{target}} $(git describe --tags --always)" > .deployed-release
    @echo "已部署 {{release}} 到 {{target}}"

# 顯示目前部署的 release 與實際執行中的映像
version:
    #!/usr/bin/env bash
    set -euo pipefail
    read -r rel target desc < .deployed-release
    echo "release=$rel target=$target system=$desc"
    TARGET=$target docker compose --env-file "versions/$rel.env" images
