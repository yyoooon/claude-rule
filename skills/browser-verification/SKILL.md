---
name: browser-verification
description: Auto-invoke when Stop hook injects "[auto-verify]", or when user explicitly requests verification of behavior/interactions/console-errors after code changes. NOT for pixel-perfect visual diffing — use Storybook/PerfectPixel for that.
---

# Browser Verification

## Overview

UI/플로우의 **동적 인터랙션 및 시스템 안정성**을 확인하는 스킬. 두 가지 경로로 발동:

1. **Auto-invocation** — Stop hook이 "[auto-verify]" 메시지를 stderr로 주입하면 자동 실행
2. **명시적 요청** — 사용자가 검증을 직접 요청

> **실행 API / 도구 선택 / 예시** — `browser-verifier` 스킬 참고 (`execution.md`, `examples.md`).
> **Tier 판정(light/full)** — `browser-verifier` 스킬 `routing.md` 참고.
> **디버깅 접근** — `browser-verifier` 스킬 `debugging.md` 참고.

**뷰포트 변경 금지.** 사용자가 띄운 Chrome 탭 크기 그대로 사용. `agent-browser viewport` 호출 X.

## When to Use

- 새 플로우/route/dialog 추가 및 동작 확인
- 기존 플로우 수정 (auth, API fetch 연동, 상태 전환)
- 데이터 흐름 변경 (폼 제출, 클릭 후 URL 라우팅 검증)
- 브라우저 콘솔 에러 0건 확인
- 4xx/5xx 네트워크 응답 확인

## When NOT to Use

- **픽셀/시안 일치 판정** — 비교 기준 없음 (시각 디버깅은 agent-browser cat 1 수동 사용)
- 순수 리팩터 / 타입만 수정 / 주석·포맷만 변경

## Auto-Invocation Protocol

Stop hook이 다음 stderr를 주입하면 본 스킬이 자동 발화:

```
[auto-verify] 코드 변경이 감지됐습니다. browser-verification 스킬을 invoke해서 검증 사이클을 시작하세요.
```

수신 후:
1. 코드 변경 없음 → **silent** sentinel 기록 + 종료
2. Wiring-Only Skip Gate 통과 → **silent** sentinel 기록 + 종료
3. 그 외 → Tier Selection (routing.md) → Light Path 또는 Full Path

**Silent SKIP:** 사용자 채팅 출력 X. sentinel 파일만 조용히 업데이트.

## Wiring-Only Skip Gate

다음 **세 조건 모두** 충족 시 즉시 SKIP:

1. 변경이 wiring 단순 — signature 변경 없는 prop 추가/교체, 문자열 상수 수정, className/variant 값 교체. 새 로직/조건부 렌더 없음.
2. 동일 패턴이 같은 코드베이스 다른 곳에서 이미 동작 중.
3. 잘못되면 사용자가 1클릭으로 즉시 catch 가능.

### SKIP 예시
- 기존 컴포넌트에 `onClick` prop 추가 (이미 검증된 패턴)
- 라우트 문자열 오타 수정
- `router.push('/A')` → `router.push('/B')` 인자만 교체
- `variant="default"` → `variant="ghost"` prop 값 교체
- Tailwind class 문자열 교체

### SKIP 안 함
- 핸들러 내부 로직 변경 (toast, mutation, 상태 전환)
- 새 컴포넌트 mount / 조건부 렌더 추가
- 같은 패턴이 코드베이스에 처음 등장

## Light Path Protocol

메인 Claude가 직접 실행. 서브에이전트 dispatch 안 함. 목표 5–10초.

### Step 1 — PORT + Expected URL 결정

```bash
PORT=$(grep -s 'PORT=' .env.local | cut -d= -f2 | tr -d ' ' | head -1)
[ -z "$PORT" ] && PORT=$(lsof -i -P -n 2>/dev/null | grep LISTEN | grep node | head -1 | grep -oE ':\d+' | tr -d ':')
[ -z "$PORT" ] && PORT=3000
```

변경 파일 경로 → expected URL 추론:
- `src/app/(home)/...` → `/`
- `src/app/record/...` → `/record`
- `src/app/onboarding/...` → `/onboarding`
- 추론 실패 → Full Path escalate

### Step 2 — Chrome 9223 / Tab 확인

**같은 대화에서 이미 탭 id를 아는 경우** → 재사용, `tab list` 생략.

**Cold start:**
```bash
agent-browser --cdp 9223 tab list 2>&1
```
- 응답 X → "검증용 크롬 9223으로 띄워주세요" 안내 + sentinel + 종료
- PORT 매칭 탭 id(t\<N\>) 메모리에 기억
- expected URL과 다르면 이동:
  ```bash
  agent-browser --cdp 9223 tab t<N>
  agent-browser --cdp 9223 open http://localhost:<PORT>/<expectedPath>
  ```

⚠️ **다른 PORT 탭으로 자동 점프 금지** — worktree 작업 흐름 파괴.

### Step 2.5 — 실행 전 커밋

1. 컴포넌트 코드를 Read로 읽어 DOM 구조 파악 (eval 탐색 금지)
2. 전체 플로우를 1콜로 작성 (`browser-verifier` execution.md 참고)

### Step 3 — 검증 (1콜)

도구 선택 (`browser-verifier` execution.md + examples.md 참고):

| 변경 성격 | 도구 |
|---|---|
| Navigation (router.push / link click) | `batch "<trigger>" "wait --url '**/...'" "get url"` |
| 같은 페이지 단일 인스펙션 | eval IIFE |
| 같은 페이지 sub-view 전환 | `batch "eval '<click>'" "wait '<selector>'" "eval '<inspect>'"` |
| 폼 입력 → submit → 페이지 전환 | IIFE(입력) → batch(submit+wait+검증) |

**Reload 판단:**
- 생략 — `_components/_lib/_mock/_store/` 변경 (HMR 충분)
- 필요 — middleware / SSR / route handler / useEffect 초기 fetch

### Step 4 — Console + Network 에러 체크 (1콜)

```bash
agent-browser --cdp 9223 console --json 2>&1 | \
  jq -c '{errors: [.data.messages[]? | select(.type=="error") | .text | .[0:160]], count: ([.data.messages[]? | select(.type=="error")] | length)}'
```

API 변경이면 4xx/5xx 추가:
```bash
agent-browser --cdp 9223 network requests --status 4xx --json 2>&1 | jq -c '[.data.requests[]? | {url, status}]'
agent-browser --cdp 9223 network requests --status 5xx --json 2>&1 | jq -c '[.data.requests[]? | {url, status}]'
```

**CareHubBridge / 다른 워크트리 포트 에러는 무시.**

### Step 5 — 보고 + Sentinel

PASS → 1줄 보고 + sentinel. FAIL → 사유 보고 (sentinel X).

## Full Path Protocol

`Agent` 툴로 `general-purpose` 서브에이전트 dispatch. 모델: Haiku 디폴트.

**Haiku → Opus/Sonnet 상향 조건:**
- Fix Loop 2회차
- diff 50줄 이상 + 여러 파일
- 첫 dispatch에서 `confidence: low` 리턴

### Brief 템플릿

```
[Verification Task]

변경 파일: {git diff --name-only HEAD + untracked}
git diff (최대 300줄): {git diff HEAD | head -300}

작업 순서:

1. [Gate] 동작/UI 영향 없는 변경이면 즉시 status: SKIP 리턴
   (리네임/타입만/주석·포맷/orphan 제거/TDD 시그널)

2. [PORT] .env.local → lsof → 3000

3. [Chrome 9223] curl 확인. 응답 X면 FAIL 종료.

4. [탭 + URL 가드] tab list → PORT 매칭 t<N> → switch → eval로 pathname 재검증

5-7. [버퍼 클리어 + 동작 시뮬]
   console --clear / network requests --clear / tab switch 후
   browser-verifier execution.md 기준 도구 선택

8. [무결성]
   console + network 4xx/5xx jq 1콜

9. [리턴] 200단어 이하, 아래 형식

⚠️ 금지: IIFE 안 navigation, sleep polling, viewport 변경, snapshot dump, step별 별도 CLI 호출
```

### 리턴 형식

```yaml
status: PASS | FAIL | SKIP
reason: "(SKIP/FAIL 시 1-2줄)"
confidence: low | medium | high
issues:
  - file: src/components/X.tsx
    selector: "[data-testid=submit]"
    expected: "..."
    actual: "..."
    severity: blocker | warning
console_errors: []
network_errors: []
```

## Fix Loop (FAIL 시)

```
서브에이전트 #1 → FAIL
  ↓ systematic-debugging 스킬 invoke
  ↓ Edit으로 수정 (누적 50줄 초과 시 에스컬레이션)
서브에이전트 #2 → PASS or FAIL
  ↓ FAIL → 1회 더 (총 2회)
서브에이전트 #3 → FAIL → 에스컬레이션
  (issues + 시도 2회 요약 + 추측 root cause. sentinel X. 코드 유지.)
```

## Category Selection

**디폴트: console/network(4) 항상 포함.**

| diff 패턴 | 카테고리 |
|---|---|
| Tailwind className / tokens.css 변경 | 1-a + 1-b |
| 인라인 `style={{ }}` CSS 변수 변경 | 1-b |
| 새 JSX 요소 mount / 조건부 렌더 | 1-a |
| `router.push` / link href 변경 | 2 |
| 폼/입력/다단계 모달 | 3 |
| API/mutation/queries 변경 | 4 |
| `useEffect` 초기 fetch | 4 + 1-a |

## Sentinel Management

`$PROJECT_ROOT/.claude/.last-verified-hash`에 diff hash 기록.

**기록 시점:** PASS / SKIP → 기록. ESCALATION → 기록 안 함.

```bash
EPHEMERAL_PATTERN='\.(log|pid)$|^\.env(\.|$)|^\.DS_Store'
mkdir -p "$PROJECT_ROOT/.claude"
{
  git -C "$PROJECT_ROOT" diff HEAD
  cd "$PROJECT_ROOT" && git ls-files --others --exclude-standard \
    | { grep -vE "$EPHEMERAL_PATTERN" || true; } | sort | while IFS= read -r uf; do
    [[ -z "$uf" ]] && continue
    echo "===UNTRACKED: $uf"; cat "$uf" 2>/dev/null || true
  done
} | sha256sum | awk '{print $1}' > "$PROJECT_ROOT/.claude/.last-verified-hash"
```

## 사용자 보고 톤

모든 보고에 elapsed 시간 포함 (`(Xs)` 형식).

```
✅ PASS — 검증 통과 (8.4s) — light path
   체크: dropdown 라벨 9개 / 토큰(bg-blue-weak, text-primary) / console 에러

🔧 PASS after fix — 1차 실패 → 수정 후 통과 (52s)
   수정: handleSubmit에서 saveToken 누락 → 추가

⏭️ SKIP (인프라 에러) — "dev 서버 미기동 (yarn dev 후 재시도)"

❌ ESCALATION — 발견 문제 / 시도 2건 요약 / 추측 root cause
```

**Silent SKIP (wiring-only / 코드 변경 없음)** — 사용자 채팅 출력 X.

## Elapsed Time

```bash
T0=$(python3 -c "import time; print(int(time.time()*1000))")
# ...
T1=$(python3 -c "import time; print(int(time.time()*1000))"); ELAPSED_MS=$((T1-T0))
echo "${ELAPSED_MS}" > .claude/.verify-elapsed-ms
```

| 경로 | 목표 | red flag |
|---|---|---|
| Light | < 15s | > 20s |
| Full (no fix) | < 60s | > 90s |
| Full (1 fix loop) | < 120s | > 180s |

## Workflow Summary

```
1. Auto-verify 시그널 / 사용자 요청
2. 코드 변경 없음 → silent sentinel + 종료
3. Wiring-Only Skip Gate → silent sentinel + 종료
4. routing.md로 Tier 판정 + Category 산출
5. Light Path: 메인 직접 (5-10초). 도구는 execution.md 참고.
6. Full Path: 서브에이전트 dispatch (Haiku 디폴트).
7. Fix Loop: systematic-debugging → 수정 → 재검증 (최대 2회)
```
