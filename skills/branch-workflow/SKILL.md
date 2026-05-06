---
name: branch-workflow
description: Use when working on git branches and the user issues a Korean shortcut — "브랜치 생성해 줘", "00000 브랜치 만들어줘", "브랜치 최신화 해줘", "최신화 해줘", "브랜치 정리해줘", "브랜치 지워줘", "pr 올려줘", "PR 보내줘", "pr 만들어줘". Auto-detects base remote: `upstream` if present (fork workflow), otherwise `origin` (single-remote repo). Works for both fork and non-fork repos.
---

# Branch Workflow

## Overview

브랜치 생성·최신화·정리·PR 4가지 단축 명령. **base remote 자동 결정**:

- `upstream` remote 있음 → fork 워크플로. base = `upstream/main`, PR도 upstream으로 cross-fork.
- 없음 → 일반 단일 remote. base = `origin/main`, PR도 origin 같은 레포로.

```
[fork 환경]                          [일반 환경]
upstream/main ←── source            origin/main ←── source
origin/main                            └── feat/foo (작업, push)
  └── feat/foo (작업, origin push)
```

자식 브랜치는 항상 `origin`에 push. base만 환경별로 다름.

## 시작 전 — base remote 결정

```bash
git remote -v
BASE_REMOTE=$(git remote | grep -qx upstream && echo upstream || echo origin)
echo "base = $BASE_REMOTE/main"
```

이후 모든 명령에서 `$BASE_REMOTE` 사용. (사용자에게 어느 쪽인지 1줄 보고)

## 트리거 → 동작

### "[이름] 브랜치 생성해 줘" / "00000 브랜치 만들어줘"

```bash
git fetch $BASE_REMOTE
git switch -c <name> $BASE_REMOTE/main
git push -u origin <name>
```
- `<name>`은 사용자 메시지에서 추출 (e.g. "사용자목록 브랜치 생성해 줘" → 사용자목록)
- prefix(`feat/`, `fix/` 등) 컨벤션 모르면 한 번 짧게 물어봄. 추측 금지
- fetch 먼저 — 안 하면 stale 기준으로 분기됨

### "브랜치 최신화 해줘" / "최신화"

```bash
git pull --rebase $BASE_REMOTE main
```
**충돌 발생 시 자동 해결 ❌**:
- `git rebase --abort` 하지 말 것 — 사용자가 직접 해결할 수 있게 그대로 둠
- "충돌 발생, 직접 해결해주세요"라고 보고 후 멈춤

**Why**: 충돌 해결은 도메인 판단 영역. 잘못 머지하면 작업 손실.

### "브랜치 정리해줘" / "브랜치 지워줘"

```bash
CURRENT=$(git branch --show-current)
git status --short                # 미커밋 변경 있으면 stop
git switch <parent>                # 보통 main. 워크트리 패턴이면 부모 브랜치
git branch -D "$CURRENT"
```
- 미커밋 변경 있으면 먼저 멈추고 사용자에게 보고. 자동 stash 금지
- 부모 브랜치는 보통 `main`. `feat/foo` + `feat/foo-A` 같은 워크트리 패턴이면 `feat/foo`
- origin remote 브랜치 삭제(`git push origin -d`)는 사용자 명시할 때만

### "pr 올려줘" / "PR 보내줘" / "pr 만들어줘"

```bash
git fetch $BASE_REMOTE
git log $BASE_REMOTE/main..HEAD --oneline   # 커밋 목록 확인
git diff $BASE_REMOTE/main...HEAD            # diff 리뷰
```

**PR 생성 — base remote에 따라 분기**:

```bash
if [ "$BASE_REMOTE" = "upstream" ]; then
  # fork → upstream으로 cross-fork PR
  gh pr create \
    --repo <upstream-owner/repo> \
    --base main \
    --head <origin-owner>:<branch> \
    --title "..." \
    --body "..."
else
  # 단일 remote — 같은 레포에 PR
  gh pr create \
    --base main \
    --title "..." \
    --body "..."
fi
```

- **fork면 base는 항상 upstream/main**, **일반 레포면 origin/main** — 헷갈리면 멈추고 확인
- diff에 미완성/debug 코드/`console.log` 등 보이면 PR 생성 전 사용자에게 보고하고 stop
- PR 본문 형식은 프로젝트 컨벤션 따라. 모르면 기본(Summary / Test plan)

## Common Mistakes

| 실수 | 방지 |
|---|---|
| 환경 확인 없이 upstream/main 가정 | 시작 전 `git remote`로 BASE_REMOTE 결정. upstream 없으면 origin |
| origin/main 기준으로 브랜치 생성(fork 환경에서) | fork면 항상 `upstream/main`, fetch 먼저 |
| rebase 충돌 자동 해결 시도 | 멈추고 사용자에게 보고 (`--abort` 금지) |
| PR base remote 헷갈림 | fork = upstream/main, 일반 = origin/main. 추측 말고 BASE_REMOTE 따름 |
| 미커밋 변경 있는데 브랜치 삭제 | `git status` 먼저, 있으면 stop |

## Red Flags — STOP

- "remote 확인 안 하고 그냥 upstream으로 fetch" → 먼저 `git remote -v`로 BASE_REMOTE 결정
- "충돌 작은 거니까 자동 머지" → 항상 사용자에게
- "PR base 추측해서 default로" → BASE_REMOTE 따라 명시
- "미커밋 변경 있는데 stash 후 삭제" → 멈추고 사용자에게
