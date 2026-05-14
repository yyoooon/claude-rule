#!/usr/bin/env bash
# playwright-verify-gate.sh
# Stop hook: git diff에 검증 대상 코드 변경이 있으면 verification 사이클을 트리거.
# 이미 검증 완료된 상태(sentinel 일치)면 스킵.

set -euo pipefail

# git 저장소 밖이면 즉시 종료
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
SENTINEL_DIR="$PROJECT_ROOT/.claude"
SENTINEL="$SENTINEL_DIR/.last-verified-hash"

# 1) 현재 diff 해시 계산 (tracked diff + untracked file contents)
{
  git -C "$PROJECT_ROOT" diff HEAD
  # Untracked files: list + their contents, deterministic order
  cd "$PROJECT_ROOT" && git ls-files --others --exclude-standard | sort | while IFS= read -r uf; do
    [[ -z "$uf" ]] && continue
    echo "===UNTRACKED: $uf"
    cat "$uf" 2>/dev/null || true
  done
} | sha256sum | awk '{print $1}' > /tmp/_carehub_verify_hash.$$
current_hash=$(cat /tmp/_carehub_verify_hash.$$)
rm -f /tmp/_carehub_verify_hash.$$

# 2) sentinel과 동일하면 이미 검증된 상태 → 스킵
if [[ -f "$SENTINEL" ]] && [[ "$(cat "$SENTINEL")" == "$current_hash" ]]; then
  exit 0
fi

# 3) 변경 파일 화이트리스트 매칭 (tracked diff + untracked)
changed=$({
  git -C "$PROJECT_ROOT" diff --name-only HEAD
  git -C "$PROJECT_ROOT" ls-files --others --exclude-standard
} | sort -u)
trigger=false
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  # 테스트 파일 제외
  if [[ "$f" == *.test.* || "$f" == *.spec.* ]]; then continue; fi
  # 화이트리스트
  case "$f" in
    src/app/*.tsx|src/app/**/*.tsx|src/components/*.tsx|src/components/**/*.tsx|src/service/*.ts|src/service/**/*.ts)
      trigger=true; break ;;
  esac
done <<< "$changed"

# 4) 비검증 변경만 있으면 sentinel만 업데이트하고 종료
if [[ "$trigger" == false ]]; then
  mkdir -p "$SENTINEL_DIR"
  echo "$current_hash" > "$SENTINEL"
  exit 0
fi

# 5) 검증 트리거: exit 2 + stderr로 prompt 주입
cat >&2 <<'EOF'
[auto-verify] 코드 변경이 감지됐습니다. browser-verification 스킬을 invoke해서 검증 사이클을 시작하세요.

사이클 종료 시 ".claude/.last-verified-hash" 파일에 현재 diff hash를 기록해야 다음 Stop에서 무한 루프가 안 납니다 (스킬 본문의 "Sentinel Management" 섹션 참고).
EOF
exit 2
