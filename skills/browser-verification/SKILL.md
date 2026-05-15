---
name: browser-verification
description: Auto-invoke when Stop hook injects "[auto-verify]" prompt, OR when user explicitly requests verification of interactions/flows/text changes. The skill dispatches a subagent that runs agent-browser against the dev server, judges if changes need verification, and (on failure) loops with `superpowers:systematic-debugging` to self-fix up to 2 iterations. DO NOT use for pixel-perfect visual diffing.
---

# Browser Verification

## Overview

UI/플로우의 **동적 인터랙션 및 시스템 안정성**을 확인하기 위한 스킬. 두 가지 경로로 발동된다:

1. **Auto-invocation** — Stop hook이 "[auto-verify]" 메시지를 stderr로 주입하면 자동 실행
2. **명시적 요청** — 사용자가 검증을 직접 요청한 경우

agent-browser는 디자인 시안과 "똑같이 생겼는지(Visual Diff)"를 검증하는 도구가 아니다. 폼 제출, 버튼 클릭, DOM 깨짐, JS 콘솔 에러 등 "제대로 동작하는지"를 시뮬레이션할 때만 사용한다.

**뷰포트는 절대 변경하지 않는다.** 사용자가 이미 띄운 Chrome 탭의 현재 크기를 그대로 사용. `agent-browser viewport` 호출 금지 — 사용자가 보고 있는 창 크기를 마음대로 바꾸면 작업 흐름이 깨진다.

## When to Use

**동작 검증 (Interaction & Flow)**
- 새 플로우/route/dialog 추가 및 동작 확인
- 기존 플로우 수정 (auth, API fetch 연동, 상태 전환)
- 데이터 흐름 변경 (폼 제출, 클릭 후 URL 라우팅 검증)

**구조 / 에러 안정성 (Error Catching)**
- 브라우저 콘솔 에러 0건 확인
- 런타임 레이스 컨디션 및 조건부 렌더링 검증
- 4xx/5xx 네트워크 응답 확인

## When NOT to Use

- **시각적 디자인 검증 (Visual/Pixel-perfect matching):** `computedStyle`로 패딩/색상 추출해서 Figma와 대조하는 행위 (절대 금지. Storybook과 PerfectPixel 영역)
- 순수 리팩터 (행동 변경 없음) / 타입만 수정 / 주석/포맷만 변경

## Auto-Invocation Protocol

Stop hook이 다음 stderr 메시지를 주입하면 본 스킬이 자동 발화한다:

```
[auto-verify] 코드 변경이 감지됐습니다. browser-verification 스킬을 invoke해서 검증 사이클을 시작하세요.
```

이 시그널을 받으면:
1. 이번 턴에 사용자가 코드를 수정하지 않았다면 (예: 메모리 조회, 문서 작성만) → 즉시 sentinel 기록 후 종료 (Sentinel Management 섹션 참고). hook의 spurious trigger 흡수용.
2. 그렇지 않으면 아래 "Subagent Dispatch Protocol" 진행.

## Subagent Dispatch Protocol

`Agent` 툴로 `general-purpose` 서브에이전트를 dispatch한다. 메인 컨텍스트에 snapshot/DOM dump가 누적되지 않게 하기 위함.

### Brief 템플릿

```
[Verification Task]

이번 턴 변경된 파일:
{git diff --name-only HEAD 결과 + untracked 파일 (`git ls-files --others --exclude-standard`)}

git diff 본문 (최대 300줄, 이상이면 head -300 + "...(truncated)"):
{git diff HEAD | head -300}

작업 순서:

1. [Gate] 위 diff가 동작/UI에 영향 있는 변경인지 판단.
   다음 중 하나에 해당하면 즉시 status: SKIP 리턴:
   - 변수/함수 리네임 (시그니처 동일)
   - 타입 정의 추가/수정만 (런타임 영향 X)
   - 주석/공백/포맷만
   - 안 쓰는 코드 제거 (orphan import 등)
   - 동일 동작 리팩터 (조건문 순서 등)
   - domain.ts 변경 + 같은 diff에 대응 *.test.ts 수정 + UI 파일(*.tsx) 변경 없음 (TDD 시그널, unit test가 cover)

2. [Dev 서버 URL 확인]
   lsof -i -P -n | grep LISTEN | grep node
   또는 :3000 기본값. PORT 확정 후 다음 단계.

3. [사용자 Chrome (9223) 살아있는지 확인 — 필수]
   curl -s http://127.0.0.1:9223/json/version
   - 응답 X → 즉시 status: FAIL + reason: "사용자 Chrome on 9223 not running. 검증은 사용자 띄운 크롬에서만 실시." → 종료.
   - 자체 브라우저 spawn 금지. agent-browser open만 단독 호출하지 말 것 (--cdp 없으면 자체 Chrome 띄움).
   - 이후 모든 agent-browser 호출에 `--cdp 9223` 명시.

4. [타겟 탭 잡기]
   agent-browser --cdp 9223 tab list
   - 출력에서 `http://localhost:PORT` 매칭 탭의 stable id (예: t2) 찾기
   - 매칭 탭 있음 → agent-browser --cdp 9223 tab t<N>
   - 매칭 탭 없음 → agent-browser --cdp 9223 open http://localhost:PORT/route (--cdp로 사용자 Chrome에 새 탭 추가)

5. [버퍼 클리어]
   agent-browser --cdp 9223 console --clear
   agent-browser --cdp 9223 network requests --clear

6. [뷰포트]
   agent-browser --cdp 9223 viewport 375 812

7. [네비게이션 + 강제 리로드]
   현재 탭이 검증 대상 route가 아니면 → agent-browser --cdp 9223 open http://localhost:PORT/route
   이미 맞는 route면 → agent-browser --cdp 9223 eval "location.reload()" && agent-browser --cdp 9223 wait 800
   페이지 stale 방지. 새 라우트 추가/Server Component 변경/HMR race window 모두 흡수.

8. [동작 시뮬레이션] — eval IIFE 1콜로 묶을 것
   agent-browser --cdp 9223 eval '
   (async () => {
     const sleep = ms => new Promise(r => setTimeout(r, ms));
     const findBtn = txt => [...document.querySelectorAll("button, [role=button]")]
       .filter(el => el.offsetParent !== null)
       .find(el => el.textContent?.trim().includes(txt));
     // 추가/변경된 핸들러 클릭/입력 ...
     // 새 텍스트/엘리먼트 DOM 렌더 확인 ...
     // API/라우팅 변경 시 URL 응답 확인 ...
     return { url: location.pathname, ... };
   })()'

9. [무결성]
   agent-browser --cdp 9223 console --json          → error/warning 0건 확인
   agent-browser --cdp 9223 network requests --status 4xx --json   → 0건 확인
   agent-browser --cdp 9223 network requests --status 5xx --json   → 0건 확인

10. [리턴] 아래 형식, 200단어 이하

⚠️ 금지:
- computedStyle 비교, 픽셀 단위 검증
- 전체 DOM snapshot dump (snapshot 명령 자제 — eval로 필요 정보만 추출)
- 50줄 이상 결과 출력
- agent-browser CLI를 step마다 따로 호출하는 안티패턴 (멀티스텝은 eval IIFE 1콜)
```

### 리턴 형식

```yaml
status: PASS | FAIL | SKIP
reason: "(SKIP/FAIL 시 1-2줄 사유)"
confidence: low | medium | high   # FAIL 시 필수
issues:                            # FAIL 시
  - file: src/components/X.tsx
    selector: "[data-testid=submit]"
    expected: "버튼 클릭 시 /onboarding으로 이동"
    actual: "URL 변경 없음, console에 'token missing' 에러"
    severity: blocker | warning
console_errors: []
network_errors: []
```

## Fix Loop (FAIL 시)

### 흐름

```
서브에이전트 #1 → FAIL (issues 리스트)
       ↓
메인 Claude:
  1. Skill 툴로 `superpowers:systematic-debugging` invoke 필수
  2. 디버깅 스킬 가이드 따라:
     - issues의 selector/expected/actual로 가설 세움
     - 변경한 파일들 + 인접 의심 코드 읽기
     - 가장 가능성 높은 root cause 1개 picked
  3. Edit으로 수정
       ↓
수정 직전 안전 점검:
  - git diff HEAD --stat으로 누적 변경량 확인
  - 50줄 이상 추가됐으면 즉시 에스컬레이션 (의도치 않은 누적 방어)
  - 서브에이전트 confidence: low면 자동 수정 안 함, 사용자 확인 먼저
       ↓
서브에이전트 #2 (재검증) → PASS or FAIL
       ↓
  PASS → 짧게 보고 + sentinel 기록 → 종료
  FAIL → 1회 더 (총 2회까지)
       ↓
서브에이전트 #3 → 여전히 FAIL
       ↓
에스컬레이션:
  - 발견된 issues 리스트
  - 시도한 수정 2회 요약 (diff 핵심만)
  - 추측되는 root cause
  - 사용자 의사 대기. 코드는 마지막 수정 상태 유지 (revert X).
  - sentinel 기록 안 함 → 사용자 추가 수정 시 다음 Stop에 재검증
```

### 인프라 에러 처리

| 케이스 | 동작 |
|---|---|
| Dev 서버 미기동 | 서브에이전트 FAIL + reason → 사용자에게 "dev 서버 켜고 다시 시도" 안내. 수정 루프 안 들어감. |
| 사용자 Chrome (9223) 미기동 | FAIL + reason → 사용자에게 "검증용 크롬을 9223으로 띄우고 다시 시도" 안내. 자체 브라우저 spawn 금지. 수정 루프 안 들어감. |
| agent-browser daemon 에러 / Chrome 미설치 | FAIL + reason → 사용자 보고. 수정 루프 안 들어감. |
| Auth 필요 + 토큰 없음 | SKIP + reason → 사용자 노티. |
| Diff 너무 큼 (대규모 리팩터) | SKIP + reason "manual review recommended" → 사용자 안내. |

## Sentinel Management

무한 루프 방지용. 검증 사이클이 어떤 형태로든 종료되면 sentinel 파일에 현재 diff 해시를 기록한다.

**경로**: `$PROJECT_ROOT/.claude/.last-verified-hash`

**기록 시점:**
- 서브에이전트 PASS → 기록
- 서브에이전트 SKIP → 기록
- 사용자 에스컬레이션 → **기록 안 함** (사용자가 추가 수정 시 재검증되도록)

**기록 방법** (hook 스크립트의 해시 계산과 동일하게 tracked diff + untracked 파일 내용 모두 포함):

```bash
mkdir -p "$PROJECT_ROOT/.claude"
{
  git -C "$PROJECT_ROOT" diff HEAD
  cd "$PROJECT_ROOT" && git ls-files --others --exclude-standard | sort | while IFS= read -r uf; do
    [[ -z "$uf" ]] && continue
    echo "===UNTRACKED: $uf"
    cat "$uf" 2>/dev/null || true
  done
} | sha256sum | awk '{print $1}' > "$PROJECT_ROOT/.claude/.last-verified-hash"
```

## 사용자 보고 톤 (메모리 "결과만 짧게 보고" 룰)

```
✅ PASS (1줄)
"검증 통과: /onboarding 진입 + GUID 입력 → /home 라우팅 정상"

🔧 PASS after fix (2줄)
"검증 1차 실패 → 수정 후 통과
 수정: handleSubmit에서 saveToken 누락 → 추가"

⏭️ SKIP
"검증 스킵: 변수 리네임 + 타입 추가만 (비동작 변경)"

❌ ESCALATION
"검증 실패. 2회 시도 후 막혔습니다.

발견 문제:
- /onboarding 클릭 후 URL이 /home으로 안 바뀜
- console: 'Cannot read property token of undefined'

시도한 수정:
1. saveToken 호출 추가 → 동일 에러
2. response.data?.accessToken 옵셔널 체이닝 → 동일 에러

추측: API 응답 구조 예상과 다름. /auth/login 응답 직접 확인 필요해 보입니다."
```

## Workflow Summary

```
1. [Auto] Stop hook에서 [auto-verify] 시그널 감지 OR [Manual] 사용자 요청
2. 이번 턴에 코드 변경 없으면 sentinel만 기록하고 종료
3. Subagent dispatch (general-purpose) — Brief 템플릿 사용
4. 서브에이전트 결과 분류:
   - SKIP → 짧게 보고 + sentinel 기록 → 종료
   - PASS → 짧게 보고 + sentinel 기록 → 종료
   - FAIL (인프라 에러) → 사용자 안내 + sentinel 기록 → 종료
   - FAIL (코드 문제) → Fix Loop
5. Fix Loop (최대 2회): systematic-debugging → 수정 → 재검증
6. 최종 결과 보고
```

## Common Mistakes

| 실수 | 발생 패턴 | 방지 |
|---|---|---|
| CSS 속성 비교 (Visual Diff) | `computedStyle`을 뽑아 패딩/색상을 Figma와 일치하는지 비교 | AI는 시각 검증에 취약. 동작과 에러 검증에만 집중. |
| 화면 깨짐 방치 | 데스크톱 뷰만 확인 | 반드시 viewport를 375 812로 설정. |
| 메인 컨텍스트 오염 | 메인 Claude가 직접 agent-browser 호출 → 출력 누적 | 항상 서브에이전트로 dispatch. |
| 페이지 stale | HMR 신뢰하고 reload 생략 | 검증 시작 시 항상 `eval "location.reload()"`. |
| CLI 호출 누적 | step마다 agent-browser 따로 호출 | 멀티스텝은 eval IIFE 1콜 (agent-browser 스킬 참고). |
| **자체 브라우저 spawn** | `--cdp` 없이 `agent-browser open ...` 호출 → 별도 Chrome 띄움 | 모든 호출에 `--cdp 9223` 필수. 9223 미응답이면 FAIL로 끊을 것 (절대 자체 spawn 금지). |
| 자동 수정 폭주 | 한 번 실패 후 계속 수정 시도 | 최대 2회. 누적 50줄 추가 시 즉시 에스컬레이션. |
| Sentinel 누락 | 검증 후 hash 기록 안 함 → 다음 Stop에서 또 발화 | PASS/SKIP/인프라 에러 시 반드시 sentinel 기록. |
