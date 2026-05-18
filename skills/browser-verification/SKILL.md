---
name: browser-verification
description: Auto-invoke when Stop hook injects "[auto-verify]", or when user explicitly requests verification of behavior/interactions/console-errors after code changes. NOT for pixel-perfect visual diffing — use Storybook/PerfectPixel for that.
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
2. 그렇지 않으면 아래 "Verification Tier Selection"으로 tier 판정 → Light Path 또는 Full Path 진입.

## Verification Tier Selection

검증 비용은 변경 영향도에 비례해야 한다. **무조건 서브에이전트 dispatch는 over-engineering이다.** 매 사이클마다 30–60초 풀 시퀀스를 도는 대신, 변경 유형에 따라 light/full을 분기한다.

### Tier 결정 알고리즘

`git diff --name-only HEAD` + `git diff HEAD --stat` 결과로 다음을 평가한다:

```
디렉토리/파일 패턴 평가:
  - 변경에 다음이 모두 해당? → Light Path
    * 변경 파일이 다음 중 하나만:
        - *.tsx / *.css / *.scss (시각/JSX)
        - src/app/**/_components/**/*.ts(x) (page-scoped 컴포넌트)
        - src/app/**/_lib/**/*.ts (page-scoped 유틸 — 정책 함수, 변환, 색상 매핑 등)
        - src/app/**/_mock/**/*.ts (mock 데이터)
        - src/app/**/_store/**/*.ts (page-scoped store)
    * src/lib/ src/service/ src/app/api/ 변경 없음 (전역 서비스 layer는 항상 Full)
    * Next.js 라우팅 게이트 (`src/middleware.ts`) 변경 없음 — 이 파일 1줄만 바뀌어도 무조건 Full
    * route handlers (route.ts) 변경 없음
    * 새 page.tsx 추가 없음 (untracked가 page면 Full, _components/_lib 추가면 Light 가능)
    * 누적 추가 라인 < 80
  - 다음 중 하나라도 해당 → Full Path
    * 라우팅/middleware/auth 파일 변경
    * 전역 service/api/queries/mutations 변경 (src/service/, src/app/api/)
    * 새 page.tsx 또는 새 route 추가
    * Zustand store / context provider 변경 (page-scoped _store/ 제외)
    * 80줄 이상 누적 변경
```

**Page-scoped 디렉토리가 light인 이유**: `src/app/<route>/_lib/`, `_components/`, `_mock/`, `_store/`는 Next.js 컨벤션상 라우터가 무시하는 페이지 내부 모듈. 영향 범위가 한 페이지로 제한되므로 시각 검증과 동등하게 다룬다. 전역 영향이 가능한 `src/lib/`, `src/service/`와 구분.

### Light Path 핵심 원칙

- **메인 Claude가 직접** agent-browser 호출 (서브에이전트 X)
- agent-browser 호출은 최대 3개 (tab list 검증 / reload+eval IIFE / console 에러)
- 목표: 5–10초 안에 결과
- 메인 컨텍스트 오염 최소화를 위해 eval 결과는 짧은 JSON만 (50줄 이내)
- 실패 시 즉시 사용자 보고 (자동 fix loop 들어가지 않음 — light path는 빠른 sanity check)

### Light Path Tool Turn 압축 (필수)

**LLM thinking turn(3–5초)이 진짜 병목.** Light path도 step을 별도 Bash 호출로 쪼개면 각 사이에 thinking turn이 끼어 40초+ 걸린다.

**원칙: Step 2-4를 1–2개 Bash 호출에 chaining으로 묶는다.**

```bash
# 권장 패턴 (Bash 1콜 = LLM 1 turn)
agent-browser --cdp 9223 tab list 2>&1 | head -5 && \
agent-browser --cdp 9223 tab t<N> >/dev/null && \
sleep 0.5 && \
agent-browser --cdp 9223 eval '<IIFE>' && \
agent-browser --cdp 9223 console --json 2>&1 | python3 -c \
  "import json,sys; d=json.load(sys.stdin); errs=[m for m in d['data']['messages'] if m['type']=='error']; print(f'errors:{len(errs)}'); print(errs[0]['text'][:200] if errs else '')"
```

- tab list 결과를 인간 눈으로 확인할 필요 없으면 head로 잘라서 같은 turn에 즉시 다음 호출
- console error는 **count + 첫 메시지 1줄**을 1콜에 뽑음 (두 번 호출 X)
- `sleep 0.5` 또는 `sleep 1`을 reload 전후에 넣어 race 방지 (재시도 turn 자체를 없앰)
- 결과 받고 PASS면 sentinel 기록 1콜 추가 → 총 2 turn 이내 완료 (10초 이하 가능)

**안티패턴 (40초+ 걸리는 케이스)**:
- step별 분리 호출: tab list → (thinking) → tab switch → (thinking) → eval → (thinking) → console → (thinking) → ...
- console error 갯수 → (thinking) → error 내용 봤어야 → 추가 호출
- reload 후 짧은 sleep 없이 즉시 eval → CDP error → 재시도 turn

### Full Path 진입 조건

- Tier 알고리즘이 full 판정
- Light path에서 unexpected 에러 발견 (메인이 fix 가능 범위를 넘어선다고 판단)
- 사용자가 명시적으로 "꼼꼼히 검증" 요청

## Light Path Protocol

메인 Claude가 직접 실행. 서브에이전트 dispatch 안 함.

### Step 1 — Expected URL 결정

변경된 파일 경로에서 expected URL을 추론한다:
- `src/app/(home)/...` → `/`
- `src/app/record/...` → `/record`
- `src/app/onboarding/...` → `/onboarding`
- `src/components/...` → 컴포넌트가 어디서 import되는지 grep으로 1차 매핑 후 가장 가능성 큰 라우트
- 추론 실패 시 → Full Path로 escalate

### Step 2 — Chrome 9223 / Tab 확인 (1콜)

```bash
agent-browser --cdp 9223 tab list 2>&1
```

- 9223 응답 없음 → 즉시 사용자에게 "검증용 크롬 9223으로 띄워주세요" 안내 + sentinel 기록 + 종료
- 출력에서 expected URL과 **정확히 일치**하는 tab id (예: t2) 추출
- **매칭 탭 없음** → expected URL로 새 탭 열기 (`agent-browser --cdp 9223 open http://localhost:<PORT>/<route>`)
- **매칭 탭 있지만 사용자가 다른 탭으로 navigate했을 가능성** → tab switch 후 location.pathname 검증 (Step 3 eval 안에서)
- ⚠️ **유사 URL 다른 탭으로 자동 switch 금지**: 예) expected가 `/record`인데 `/tracker/heartrate` 탭에 같은 컴포넌트가 떠 있더라도, 진입 경로/상태가 다르면 검증 동치 X. expected와 정확히 일치하지 않으면 새 탭 열거나 사용자에게 안내.

### Step 3 — Reload + 검증 (1콜, IIFE)

```bash
agent-browser --cdp 9223 tab t<N> >/dev/null
agent-browser --cdp 9223 eval '
(async () => {
  if (location.pathname !== "<expectedPath>") {
    return { ok: false, reason: "tab navigated away", currentUrl: location.pathname };
  }
  location.reload();
  await new Promise(r => setTimeout(r, 1500));
  // 변경 검증 — DOM attribute / textContent 위주 (computed style 비교는 Visual Diff 금지 룰에 걸림)
  // OK: el.getAttribute("fill"), el.textContent, querySelector(".new-class") 존재 여부
  // NOT OK: getComputedStyle(el).color/padding 등 픽셀/색상 픽업
  const result = { ok: true, url: location.pathname /* + 변경 관련 attribute/text 추출 값 */ };
  return result;
})()
'
```

- `tab navigated away` 리턴 → 사용자에게 "검증 대상 탭이 다른 페이지로 이동했습니다. 다시 `/<expectedPath>`로 가주세요" 안내 + sentinel 기록 + 종료
- 변경 관련 값이 기대와 다름 → 사용자에게 짧게 보고하고 종료 (light path는 fix loop 안 함)

### Step 4 — Console 에러 체크 (1콜)

```bash
agent-browser --cdp 9223 console --json 2>&1 | head -200
```

- 출력이 너무 길면 grep으로 error/warn level만 필터: `... | jq '.data.messages[] | select(.type=="error" or .type=="warning")'`
- d3 / SVG / 변경 파일 관련 error 0건이면 PASS

### Step 5 — 보고 + Sentinel

PASS면 1줄 보고 후 sentinel 기록. FAIL이면 짧은 사유 + sentinel 기록 X (사용자 추가 수정 유도).

## Subagent Dispatch Protocol (Full Path)

`Agent` 툴로 `general-purpose` 서브에이전트를 dispatch한다. 메인 컨텍스트에 snapshot/DOM dump가 누적되지 않게 하기 위함.

### 모델 선택

**디폴트: `model: "haiku"`** — DOM 검증/console/network 체크는 단순 작업이라 Haiku로 충분하고 thinking turn이 Opus 대비 2-3배 빠르다. 70초 → 30-40초.

**예외로 Opus/Sonnet 선택**:
- Fix Loop 2회차 (서브에이전트가 직접 systematic-debugging까지 해야 할 때)
- diff가 50줄 이상 + 여러 파일에 걸친 변경 (가설 수립 복잡도 높음)
- 첫 dispatch에서 Haiku가 confidence: low 리턴

### Tool Turn 압축 원칙

서브에이전트의 LLM thinking turn이 진짜 병목이다 (각 turn 3-5초). 따라서 **여러 bash 명령은 한 turn에 묶어서 보낸다**.

Brief 템플릿의 step 5-8 (버퍼 클리어 / 네비게이션 / 동작 시뮬레이션 / 무결성)을 가능한 한 `&&` 또는 `;` 체이닝으로 합쳐 1-2 turn에 완료. 호출 횟수가 아니라 **LLM tool turn 수**가 비용. step별 따로 호출하면 5+ turn × 4초 = 20초 낭비.

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

4. [타겟 탭 잡기 + URL Mismatch 가드]
   agent-browser --cdp 9223 tab list
   - 출력에서 expected URL (`http://localhost:PORT/<route>`) 매칭 탭의 stable id (예: t2) 찾기
   - 매칭 탭 있음 → agent-browser --cdp 9223 tab t<N>
   - 매칭 탭 없음 → agent-browser --cdp 9223 open http://localhost:PORT/route (--cdp로 사용자 Chrome에 새 탭 추가)
   - **사용자가 검증 도중 다른 페이지로 navigate할 수 있음.** 다음 eval 안에서 location.pathname을 expected와 다시 검증하고, mismatch면 즉시 reason: "tab navigated away — 사용자가 검증 대상 페이지에서 벗어남"로 SKIP 리턴.

5-7. [버퍼 클리어 + 리로드 + 동작 시뮬레이션] — 1개 bash 호출로 묶기
   tool turn 수가 진짜 비용. 다음과 같이 `&&` 체이닝 또는 한 줄로 결합:

   ```bash
   agent-browser --cdp 9223 console --clear >/dev/null && \
   agent-browser --cdp 9223 network requests --clear >/dev/null && \
   agent-browser --cdp 9223 eval '
   (async () => {
     const sleep = ms => new Promise(r => setTimeout(r, ms));
     if (location.pathname !== "<expectedPath>") {
       return { ok: false, reason: "tab navigated away", currentUrl: location.pathname };
     }
     location.reload();
     await sleep(1200);
     // 추가/변경된 핸들러 클릭/입력 ...
     // 새 텍스트/엘리먼트 DOM 렌더 확인 ...
     // API/라우팅 변경 시 URL 응답 확인 ...
     return { ok: true, url: location.pathname /* + 변경 관련 attribute/text */ };
   })()
   '
   ```

   ⚠️ 뷰포트는 절대 변경하지 말 것. 사용자가 띄운 탭 크기 그대로 사용 (`agent-browser viewport` 호출 금지).

8. [무결성] — 1개 bash 호출로 묶기
   console + network 4xx + 5xx를 따로 호출하지 말고 jq로 한 번에:

   ```bash
   agent-browser --cdp 9223 console --json 2>&1 | \
     jq '{errors: [.data.messages[]? | select(.type=="error" or .type=="warning")]}' && \
   agent-browser --cdp 9223 network requests --json 2>&1 | \
     jq '{bad: [.data.requests[]? | select(.status >= 400)]}'
   ```

   둘 다 빈 배열이면 PASS.

9. [리턴] 아래 형식, 200단어 이하

⚠️ 금지:
- computedStyle 비교, 픽셀 단위 검증
- 전체 DOM snapshot dump (snapshot 명령 자제 — eval로 필요 정보만 추출)
- 50줄 이상 결과 출력
- step별로 따로 agent-browser CLI 호출 (멀티스텝은 한 bash 줄에 `&&` 체이닝 또는 eval IIFE 1콜로 합칠 것 — LLM tool turn이 가장 큰 비용)
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

## Elapsed Time Measurement (Level 2)

매 검증 사이클의 wall-clock 시간을 측정해서 결과 보고에 포함한다. 추정 대신 실측. 이번 사이클이 5초였는지 40초였는지 사용자가 즉시 알 수 있고, 누적되면 스킬 개선 베이스라인이 자동으로 쌓인다.

### 측정 패턴

검증 사이클 진입 시 (Tier Selection 직후) 시작 시각을 stash하고, sentinel 기록 직전에 종료 시각과의 차이를 계산한다.

```bash
# 진입 시
T0=$(date +%s%3N)

# ... 모든 agent-browser 호출, eval, console 체크 등 ...

# 종료 시 (sentinel 기록과 함께 같은 turn에)
T1=$(date +%s%3N); ELAPSED_MS=$((T1-T0))
{ git diff HEAD; ...; } | sha256sum | awk '{print $1}' > .claude/.last-verified-hash
echo "${ELAPSED_MS}" > .claude/.verify-elapsed-ms
```

- `.verify-elapsed-ms`는 매 사이클 덮어씌움. 누적 트렌드 추적 원하면 `>>` 로 append + timestamp 같이 기록
- Light path와 Full path 모두 같은 패턴 적용

### 보고 형식

사용자 보고 1줄에 elapsed 포함:

```
✅ PASS (8.4s) — light path
🔧 PASS after fix (52s) — full path, 1 fix
⏭️ SKIP (1.2s)
```

자릿수는 초 단위 소수점 1자리 (`$(echo "scale=1; $ELAPSED_MS/1000" | bc)s`).

### 기대 baseline

| 경로 | 목표 | red flag |
|---|---|---|
| Light | < 15s | 20s+ → step 압축 누락 의심 |
| Full (no fix) | < 60s | 90s+ → Brief에서 step 분리 호출 의심 |
| Full (1 fix loop) | < 120s | 180s+ → systematic-debugging 호출 자체 시간 점검 |

베이스라인을 자주 초과하면 스킬 본문 재점검 신호.

## Proactive Status Communication

검증 사이클이 길어질 수 있거나 이슈를 발견했을 때, **메인 Claude는 한 줄 알림을 띄워 사용자가 답답하지 않게 한다.** 사용자는 자기 작업 중이라 "지금 뭐 하는지" 모르면 불안.

### 알림 필수 시점

| 시점 | 메시지 예시 |
|---|---|
| Tier 결정 직후 | "Light path 진입 (5–10초 예상)" / "Full path — 서브에이전트 dispatch (30–60초 예상)" |
| Chrome 9223 미응답 | "검증용 크롬(9223) 미응답 — 검증 중단. 9223 포트로 크롬 띄워주세요." → sentinel 기록 + 종료 |
| Dev 서버 미기동 | "Dev 서버 미기동 — 검증 스킵. `yarn dev` 후 재시도." → 종료 |
| Expected URL 추론 실패 | "변경 파일에서 검증 대상 라우트 추론 실패 — Full path로 escalate" 또는 종료 |
| URL Mismatch 감지 | "검증 대상 탭이 `/<other>`로 이동됨. `/<expected>`로 돌아가주시거나 검증 스킵 가능" → 종료 |
| Light path에서 unexpected console 에러 | "Light path 도중 console 에러 발견 — 짧게 사유: ..." → 종료 (fix loop X) |
| Full path fix loop 1회차 진입 | "1차 검증 실패 → 수정 후 재검증 중" |
| Full path 최종 에스컬레이션 | "2회 시도 후 막힘 — 발견 이슈 / 시도한 수정 / 추측 root cause 정리" |

### 알림 형식 룰

- **한 줄, 결과 위주**. 진행률 % / 단계 번호 같은 사족 X
- 사용자 메모리 "결과만 짧게 보고" 룰 준수
- 같은 사이클에 같은 phase 알림 중복 금지
- 알림은 Bash/Tool 호출 *직전* 또는 *결과 받자마자*. 호출 도중 long-running task 동안 띄울 수 없으니 dispatch 직전에 예상 시간 안내.

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
3. Verification Tier Selection — diff 패턴으로 light/full 분기
4. Light Path: 메인 직접 (tab list / reload+eval / console) — 5–10초
   - PASS → 1줄 보고 + sentinel 기록 → 종료
   - 변경 미반영/console 에러 → 짧게 사유 보고 + sentinel 안 기록 (사용자 수정 유도)
   - light path가 cover 못 하는 변경 발견 → Full Path로 escalate
5. Full Path: Subagent dispatch (general-purpose) — Brief 템플릿 사용
6. 서브에이전트 결과 분류:
   - SKIP → 짧게 보고 + sentinel 기록 → 종료
   - PASS → 짧게 보고 + sentinel 기록 → 종료
   - FAIL (인프라 에러) → 사용자 안내 + sentinel 기록 → 종료
   - FAIL (코드 문제) → Fix Loop
7. Fix Loop (최대 2회): systematic-debugging → 수정 → 재검증
8. 최종 결과 보고
```

## Common Mistakes

| 실수 | 발생 패턴 | 방지 |
|---|---|---|
| CSS 속성 비교 (Visual Diff) | `computedStyle`을 뽑아 패딩/색상을 Figma와 일치하는지 비교 | AI는 시각 검증에 취약. 동작과 에러 검증에만 집중. |
| **뷰포트 변경** | `agent-browser viewport ...` 호출해서 사용자가 띄운 창 크기를 멋대로 바꿈 | 절대 viewport 호출 금지. 사용자가 띄운 탭 크기 그대로 사용. |
| 메인 컨텍스트 오염 | Full Path에서 메인 Claude가 직접 agent-browser 호출 → 출력 누적 | Full path는 항상 서브에이전트로 dispatch. Light path는 메인 직접 OK 단, eval 결과를 50줄 이내로 압축. |
| **잘못된 탭 캡처** | 사용자가 검증 중에 다른 페이지로 navigate한 사이에 우리는 t<N>으로 잘못된 화면 캡처 | tab switch 후 항상 eval 안에서 `location.pathname`을 expected와 재검증. mismatch면 즉시 사용자 안내 + 종료 (자동 navigate 강제 X — 사용자 작업 흐름 침범). |
| **풀 시퀀스 over-engineering** | 차트 SVG 한 줄 시각 수정에도 서브에이전트 30–60초 풀 dispatch | Verification Tier Selection으로 light path 진입. 변경 영향도에 맞게 검증 비용 분배. |
| 페이지 stale | HMR 신뢰하고 reload 생략 | 검증 시작 시 항상 `eval "location.reload()"`. |
| CLI 호출 누적 | step마다 agent-browser 따로 호출 | 멀티스텝은 eval IIFE 1콜 (agent-browser 스킬 참고). |
| **자체 브라우저 spawn** | `--cdp` 없이 `agent-browser open ...` 호출 → 별도 Chrome 띄움 | 모든 호출에 `--cdp 9223` 필수. 9223 미응답이면 FAIL로 끊을 것 (절대 자체 spawn 금지). |
| 자동 수정 폭주 | 한 번 실패 후 계속 수정 시도 | 최대 2회. 누적 50줄 추가 시 즉시 에스컬레이션. |
| Sentinel 누락 | 검증 후 hash 기록 안 함 → 다음 Stop에서 또 발화 | PASS/SKIP/인프라 에러 시 반드시 sentinel 기록. |
| **open으로 엉뚱한 탭 오염** | `tab list` 확인 없이 `open <url>` 날림 → 현재 활성 탭(다른 포트/라우트)이 URL 변경됨 | 항상 `tab list` 먼저 → 목적 탭 `tab t<N>` switch → 그 탭 안에서 `eval "location.href=..."` 로 navigate. `open`은 매칭 탭이 아예 없을 때만. |
