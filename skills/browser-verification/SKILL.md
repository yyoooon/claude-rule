---
name: browser-verification
description: Auto-invoke when Stop hook injects "[auto-verify]", or when user explicitly requests verification of behavior/interactions/console-errors after code changes. NOT for pixel-perfect visual diffing — use Storybook/PerfectPixel for that.
---

# Browser Verification

## Overview

UI/플로우의 **동적 인터랙션 및 시스템 안정성**을 확인하기 위한 스킬. 두 가지 경로로 발동:

1. **Auto-invocation** — Stop hook이 "[auto-verify]" 메시지를 stderr로 주입하면 자동 실행
2. **명시적 요청** — 사용자가 검증을 직접 요청

**커버 범위 (agent-browser 스킬의 8-카테고리 기준):**
- ✅ **2/3/4** — 기본. console/network는 항상 포함
- ✅ **1-a/1-b** — diff에 시각/토큰 변경이 있을 때 조건부 추가 (아래 Category Selection 참고)
- ❌ 픽셀 단위 일치 판정 — 본 스킬 영역 밖

**두 직교 축으로 검증을 결정:**
- **Tier** (Light/Full): 얼마나 비싸게 — 메인 직접 vs 서브에이전트
- **Category** (1-a/1-b/2/3/4): 무엇을 — diff 패턴으로 set 산출

**뷰포트 변경 금지.** 사용자가 띄운 Chrome 탭 크기 그대로 사용. `agent-browser viewport` 호출 X.

> agent-browser CLI 디테일(IIFE 패턴 / React setter / CDP attach 절차)은 **`agent-browser` 스킬** 참고. 본 스킬은 auto-verify *프로토콜* (언제/어떻게/얼마나 검증할지)에 집중.

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

- **픽셀/시안 일치 판정** — auto-verify는 비교 기준이 없어 부적합 (시각 디버깅은 agent-browser 카테고리 1 수동 사용)
- 순수 리팩터 (행동 변경 없음) / 타입만 수정 / 주석/포맷만 변경

## Token Application Check (구조적 매칭, 시각 X)

디자인 토큰 매핑이 실제 DOM에 박혔는지는 **확인 OK**. 시각 비교가 아니라 **classList/computed value 숫자 매칭**이라 신뢰도 100%.

**확인 대상 변경**: Figma 적용 / 새 토큰 도입 / 토큰 스왑. 라우팅·문자열 수정 등 토큰 무관 변경엔 생략.

**방법** (eval IIFE 안에 묶기, 별도 콜 X):
- 1차: `el.classList.contains('bg-blue-weak')` — Tailwind 클래스가 직접 박혀있을 때 (가장 안전)
- 2차: `getComputedStyle(el).backgroundColor` rgb/hex 비교 — 클래스가 동적 조합되어 classList 검사가 불가능할 때만
- **인라인 스타일(`style={{ background: 'var(--x)' }}`) 케이스**: classList 체크 불가. `getComputedStyle(el).background`로 computed 값을 뽑아 Figma 스펙 색상값(rgba)과 비교. applying-figma-designs 작업 후라면 Figma MCP에서 확인한 색상값을 기대값으로 사용.

**금지**: px·gap·padding 수치 비교, 폰트 메트릭 측정 — 0.5~2px 오차로 판정 불안정 (이 영역은 본 스킬 밖).

## Auto-Invocation Protocol

Stop hook이 다음 stderr 메시지를 주입하면 본 스킬이 자동 발화한다:

```
[auto-verify] 코드 변경이 감지됐습니다. browser-verification 스킬을 invoke해서 검증 사이클을 시작하세요.
```

이 시그널을 받으면:
1. 이번 턴에 사용자가 코드를 수정하지 않았다면 (예: 메모리 조회, 문서 작성, WebView 연결만) → **사용자 메시지 출력 없이 silent로** sentinel 기록 후 종료. hook의 spurious trigger 흡수용 — 사용자가 알 필요 없음.
2. 아래 "Wiring-Only Skip Gate" 통과 시 → **silent로** sentinel 기록 + 종료.
3. 그렇지 않으면 아래 "Verification Tier Selection"으로 tier 판정 → Light Path 또는 Full Path 진입.

**Silent SKIP 규칙:** 코드 변경 없음 / wiring-only 케이스는 사용자 채팅에 메시지 출력 X. Bash 호출도 `>/dev/null 2>&1`로 출력 숨김. sentinel 파일만 조용히 업데이트.

## Wiring-Only Skip Gate

검증 비용보다 "사용자가 dev 서버에서 직접 확인하는 비용"이 더 싼 trivial 변경을 걸러낸다. **다음 세 조건을 모두 만족하면 즉시 SKIP** (sentinel 기록 + 1줄 보고 + 종료):

1. 변경이 **wiring 단순** — signature 변경 없는 prop 추가/교체, 문자열 상수 수정, className/variant 값 교체. 새 로직/조건부 렌더/새 mount 없음.
2. **동일 패턴이 같은 코드베이스 다른 곳에서 이미 동작 중** — 예: record 페이지에서 검증된 `onClick={() => router.push(...)}` 패턴을 home에도 동일 적용. 코드베이스에 처음 등장하는 패턴이면 skip 안 함.
3. **잘못되면 사용자가 1클릭으로 즉시 catch 가능** — UI에 노출된 인터랙션이라 dev 서버 보면서 0.5초에 확인 가능.

### SKIP 예시 (이런 변경은 검증 X)

- 기존 컴포넌트에 `onClick` prop 추가 (컴포넌트는 이미 onClick 지원하고, 같은 prop이 다른 페이지에서 동작 검증됨)
- 라우트 경로 문자열 오타 수정 (`/heart-rate` → `/heartrate`)
- **`router.push('/A')` → `router.push('/B')` 같은 라우트 인자 string 교체** — 핸들러 로직 동일, 목적지 경로만 다름. 다른 페이지에서 `router.push` 패턴이 이미 동작 검증된 코드베이스라면 검증 비용 > 사용자 1클릭 비용.
- `variant="default"` → `variant="ghost"` 같은 prop 값 교체
- Tailwind class 문자열 교체 (`bg-gray-100` → `bg-gray-200`)

### SKIP 안 함 (Tier Selection으로 진행)

- 핸들러 내부 로직 변경 (toast, mutation, 상태 전환)
- 새 컴포넌트 mount / 조건부 렌더 (`{cond && <X />}`) 추가
- 같은 패턴이 코드베이스에 처음 등장 (검증된 레퍼런스 없음)
- 사용자가 보지 않는 페이지/상태에서만 발동하는 변경

### 보고 형식

**Silent.** 사용자 채팅에 메시지 출력하지 않음. sentinel 파일만 조용히 업데이트하고 종료.

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

**LLM thinking turn(3–5초)이 진짜 병목.** 한 사이클이 5 turn을 넘어가면 20초가 그냥 사라진다.

**원칙:**
1. `agent-browser` 스킬 "Tool Selection Hierarchy" 순서로 도구 매칭 — IIFE를 첫 도구로 꺼내지 말 것
2. Navigation 동반은 **`batch + wait --url` 1콜** (거의 항상 정답)
3. 같은 페이지 내는 `eval IIFE` 1콜
4. tab switch와 eval은 **별도 Bash call** (`&&` 체인 시 탭 컨텍스트 소실)
5. console/network 결과는 jq 한 줄로 count + 첫 메시지만

목표: tab switch(1) + 본 검증(1) + console/network(1) + sentinel(1) = **4 turn / 10초 이하**.

**최대 시간 폭주 안티패턴**: IIFE 안에서 `location.href`/`reload` + `await sleep` + return → CDP race로 재시도 turn 누적. 실측 사례 181초. 자세한 진단/대안은 `agent-browser` 스킬 "Navigation Boundary" 참고.

### Full Path 진입 조건

- Tier 알고리즘이 full 판정
- Light path에서 unexpected 에러 발견 (메인이 fix 가능 범위를 넘어선다고 판단)
- 사용자가 명시적으로 "꼼꼼히 검증" 요청

## Category Selection — 무엇을 검증할지

Tier와 **직교 축**. diff에서 어떤 카테고리를 검증해야 하는지 set으로 산출.

### diff 패턴 → 카테고리 매핑

| 변경 패턴 (diff에서 탐지) | 카테고리 |
|---|---|
| Tailwind className / 색 / `tokens.css` 변경 | **1-a** + **1-b** |
| 인라인 `style={{ ... }}` 에 CSS 변수/색상 변경 | **1-b** (classList 불가 — computed 값 비교) |
| applying-figma-designs 스킬을 탄 작업 | **1-b** 무조건 (Figma 스펙 색상 vs computed) |
| 새 JSX 요소 mount / 조건부 렌더 추가 | **1-a** |
| 새 `onClick` / 핸들러 (navigation 없음) | **2** |
| `router.push` 인자 변경 / link href / nav 트리거 | **2** (navigation — Step 3 분기표대로 batch+wait) |
| 폼/입력/다단계 모달 (같은 페이지 내) | **3** |
| 폼 submit → 페이지 전환 | **3** (IIFE+batch 혼합) |
| API/mutation/queries/fetch 변경 | **4** |
| `useEffect` 초기 mount fetch | **4** + **1-a** |

**디폴트로 카테고리 4(console/network)는 항상 포함** — 거의 free, silent 버그 잡음.

### 실행

cat set이 결정되면 **`agent-browser` 스킬의 "다중 카테고리 합치기"** 패턴 그대로 실행:
- A 그룹(1-b/2/3) → IIFE 1콜
- B 그룹(4) → console/network 2콜
- C 그룹(1-a) → 시각 변경 있을 때만 스크린샷 + Read

IIFE 본문 조립 규칙 / 예시 코드는 모두 agent-browser 본문 참고 (본 스킬은 어떤 cat을 켤지만 결정).

### 산출 예시

```
diff: src/app/record/_components/WeightForm.tsx + src/styles/tokens.css

탐지:
  - tokens.css 변경 → cats += {1-a, 1-b}
  - 새 <form> + setReactValue → cats += {3}
  - useMutation 호출 → cats += {4}

최종 cats = {1-a, 1-b, 3, 4}

실행:
  1. IIFE 1콜 (cat 1-b inspect + cat 3 form submit + trace)
  2. console/network 2콜 (cat 4)
  3. 스크린샷 1콜 + Read (cat 1-a)
```

## 검증 계획 공지 (사후 보고, 승인 X)

Tier + Category Selection이 끝나면 **승인 받지 말고 즉시 eval 실행**. 사용자에게는 한 줄로 무엇을 검증하는지 알리고 바로 진행한다.

```
Light path 진입 (5–10초 예상) — /record에서 차트 SVG 속성 + console 에러 체크
```

**금지**: "진행할까요?" / "검증 계획: ..." 같은 승인 대기 패턴. 사용자가 "묻지 말고 자동 검증" 룰을 명시했으므로, eval을 먼저 날리고 결과만 보고한다.

**예외 (알림 자체도 생략):**
- Wiring-Only SKIP 케이스 (sentinel만 기록하고 끝)
- 코드 변경 없음 케이스

## Light Path Protocol

메인 Claude가 직접 실행. 서브에이전트 dispatch 안 함.

### Step 1 — Expected URL 결정

**PORT 결정 (먼저):**
```bash
PORT=$(grep -s 'PORT=' .env.local | cut -d= -f2 | tr -d ' ' | head -1)
[ -z "$PORT" ] && PORT=$(lsof -i -P -n 2>/dev/null | grep LISTEN | grep node | head -1 | grep -oE ':\d+' | tr -d ':')
[ -z "$PORT" ] && PORT=3000
```
워크트리마다 포트가 다를 수 있으므로 `.env.local` 우선 확인.

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

### Step 2.5 — 실행 전 커밋 (필수)

eval/batch 첫 호출 전 두 조건 충족:

1. **컴포넌트 코드를 Read로 읽었는가?** — DOM selector, className, data-attribute 등 구조를 코드로 파악. eval로 탐색하지 말 것.
2. **전체 플로우를 1콜로 작성했는가?** — navigation 동반은 `batch`, 같은 페이지는 IIFE. 단계별 별도 호출 금지. 본문 조립은 `agent-browser` 스킬 "Tool Selection Hierarchy" + "Navigation Boundary" 참고.

### Step 3 — 검증 (1콜)

Category Selection으로 cat set 결정 후 **도구 선택**:

| 변경 성격 | 도구 |
|---|---|
| Navigation (router.push / link click → URL 변경) | `batch "<trigger>" "wait --url '**/...'" "get url"` |
| 같은 페이지 내 DOM (token, attribute, text, 모달 동작) | eval IIFE |
| State 변경 → reload → 검증 | `batch "eval '...'" "reload" "wait --load networkidle" "..."` |
| 폼 입력 → submit → 페이지 전환 | IIFE(입력) → batch(submit+wait+검증) |

본문 조립 / 코드 예시는 `agent-browser` 스킬 "Tool Selection Hierarchy" + "Navigation Boundary" + "다중 카테고리 합치기" 참고. cat 1-a 포함이면 Step 4 직후 스크린샷 1콜 + Read.

**Reload 판단:**
- 생략 — `_components/_lib/_mock/_store/` 변경 (HMR 충분)
- 필요 — middleware / SSR / route handler / useEffect 초기 fetch / cross-route 진입

```bash
agent-browser --cdp 9223 tab t<N> >/dev/null
agent-browser --cdp 9223 eval '
(async () => {
  if (location.pathname !== "<expectedPath>") {
    return { ok: false, reason: "tab navigated away", currentUrl: location.pathname };
  }
  // reload 필요한 경우만 아래 두 줄 포함 (HMR 충분하면 생략)
  // location.reload();
  // await new Promise(r => setTimeout(r, 1500));
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

### Step 4 — Console + Network 에러 체크 (1콜)

count + 핵심 메시지만 빨리 뽑기:

```bash
agent-browser --cdp 9223 console --json 2>&1 | \
  jq -c '{errors: [.data.messages[]? | select(.type=="error") | .text | .[0:160]], count: ([.data.messages[]? | select(.type=="error")] | length)}'
```

API 변경 검증이면 4xx/5xx도 같이:

```bash
agent-browser --cdp 9223 network requests --status 4xx --json 2>&1 | jq -c '[.data.requests[]? | {url, status}]'
agent-browser --cdp 9223 network requests --status 5xx --json 2>&1 | jq -c '[.data.requests[]? | {url, status}]'
```

- 사전 클리어 권장: 검증 시작 전에 `agent-browser --cdp 9223 console --clear` + `network requests --clear` (이전 노이즈 제거)
- d3 / SVG / 변경 파일 관련 error 0건이면 PASS
- **CareHubBridge / 다른 워크트리 포트(`worktrees_b` 등)에서 온 에러는 무시** — 환경 차이 (메모리 룰)

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

2. [PORT 결정]
   ```bash
   PORT=$(grep -s 'PORT=' .env.local | cut -d= -f2 | tr -d ' ' | head -1)
   [ -z "$PORT" ] && PORT=$(lsof -i -P -n 2>/dev/null | grep LISTEN | grep node | head -1 | grep -oE ':\d+' | tr -d ':')
   [ -z "$PORT" ] && PORT=3000
   ```

3. [Chrome 9223 확인]
   `curl -s http://127.0.0.1:9223/json/version` — 응답 X면 FAIL 종료. 모든 호출 `--cdp 9223` 명시. 자체 spawn 금지.

4. [타겟 탭 + URL 가드]
   `tab list`에서 `http://localhost:PORT/<route>` 매칭 탭 stable id (t<N>) 찾아 switch. 없으면 `batch "open http://localhost:PORT/route" "wait --load networkidle"`. eval 안에서 `location.pathname` 재검증, mismatch면 SKIP "tab navigated away".

5-7. [버퍼 클리어 + 동작 시뮬레이션] — 변경 성격별 패턴 선택

   Category Selection으로 cat set 산출 후 본 스킬 "Step 3" 분기표에 따라 도구 선택. 구체 명령은 `agent-browser` 스킬 "Tool Selection Hierarchy" + "Navigation Boundary" 참고.

   공통 전처리:
   ```bash
   agent-browser --cdp 9223 console --clear >/dev/null
   agent-browser --cdp 9223 network requests --clear >/dev/null
   agent-browser --cdp 9223 tab t<N> >/dev/null
   ```

   그 다음 navigation 검증이면 `batch + wait --url`, 같은 페이지면 IIFE, state 변경이면 `batch (eval + reload + wait --load + 검증)`.

   ⚠️ viewport 변경 금지. ⚠️ IIFE 안에서 navigation 트리거 금지 (CDP race).

8. [무결성] — 1개 bash 호출로 묶기
   console + network 4xx/5xx를 jq로 한 번에. network는 `--status 4xx` 내장 필터 사용:

   ```bash
   agent-browser --cdp 9223 console --json 2>&1 | \
     jq -c '{errors: [.data.messages[]? | select(.type=="error") | .text[0:160]]}' && \
   agent-browser --cdp 9223 network requests --status 4xx --json 2>&1 | \
     jq -c '[.data.requests[]? | {url, status}]' && \
   agent-browser --cdp 9223 network requests --status 5xx --json 2>&1 | \
     jq -c '[.data.requests[]? | {url, status}]'
   ```

   셋 다 빈 배열이면 PASS. CareHubBridge / 다른 워크트리 포트 에러는 무시.

9. [리턴] 아래 형식, 200단어 이하

⚠️ 금지:
- computedStyle 비교, 픽셀 단위 검증
- 전체 DOM snapshot dump (snapshot 명령 자제 — eval로 필요 정보만 추출)
- 50줄 이상 결과 출력
- step별로 따로 agent-browser CLI 호출 (멀티스텝은 `batch` 또는 eval IIFE 1콜로 합칠 것 — LLM tool turn이 가장 큰 비용)
- **IIFE 안에서 `location.href` / `location.reload()` / navigation 트리거 click + `await sleep` + return** (CDP race로 재시도 turn 폭주). `batch "<trigger>" "wait --url '**/...'" "<verify>"`로 분리.
- **navigation 후 외부 `sleep + tab list`로 폴링** — `wait --url` 1콜로 해결됨.
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

## Elapsed Time Measurement

매 사이클 wall-clock 측정 + 보고. 추정 X.

### 측정

Tier Selection 직후 stash, sentinel 기록 시 차이 계산:

```bash
T0=$(python3 -c "import time; print(int(time.time()*1000))")
# ... 모든 호출 ...
T1=$(python3 -c "import time; print(int(time.time()*1000))"); ELAPSED_MS=$((T1-T0))
echo "${ELAPSED_MS}" > .claude/.verify-elapsed-ms
```

보고는 1자리 소수점: `✅ PASS (8.4s) — light path`.

### Baseline + 초과 시 자동 알림

| 경로 | 목표 | red flag | 알림 메시지 |
|---|---|---|---|
| Light | < 15s | > 20s | "step 압축 누락 또는 reload race 의심" |
| Full (no fix) | < 60s | > 90s | "Brief에서 step 분리 호출 의심" |
| Full (1 fix loop) | < 120s | > 180s | "fix loop 자체 점검 필요" |

red flag 초과 시 PASS 보고 다음 줄에 `⚠️ baseline(Xs) 초과 — <메시지>` 1줄 자동 덧붙임. 안쪽이면 침묵.

## Proactive Status Communication

검증 사이클이 길어질 수 있거나 이슈를 발견했을 때, **메인 Claude는 한 줄 알림을 띄워 사용자가 답답하지 않게 한다.** 사용자는 자기 작업 중이라 "지금 뭐 하는지" 모르면 불안.

### 알림 시점

- **Tier 결정 직후** — "Light path 진입 (5–10초 예상)" / "Full path 진입 (30–60초 예상)"
- **인프라 에러** (9223 미응답 / dev 서버 미기동) — 1줄 사유 + sentinel + 종료
- **URL Mismatch / 추론 실패** — 1줄 사유 + 종료
- **Fix loop 진입** — "1차 실패 → 수정 후 재검증 중"

룰: 한 줄, 결과 위주. 진행률 % / 단계 번호 X. 같은 phase 알림 중복 X.

## Sentinel Management

무한 루프 방지. `$PROJECT_ROOT/.claude/.last-verified-hash`에 현재 diff hash 기록.

**기록 시점**: PASS / SKIP → 기록. ESCALATION → 기록 안 함 (사용자 추가 수정 시 재검증).

⚠️ **ephemeral 파일 제외 필수** (`.log`, `.pid`, `.env*`, `.DS_Store`). hook 스크립트와 패턴 일치시켜야 무한 루프 안 남:

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

## 사용자 보고 톤 (메모리 "결과만 짧게 보고" 룰)

모든 보고에 elapsed 시간 포함 (`(Xs)` 형식).

**PASS 보고에는 "체크: …"로 무엇을 검증했는지 요약**한다. 사용자가 "AI가 어디까지 확인했는지" 다시 물어보지 않아도 되게 하기 위함. 스킵한 항목(픽셀 일치/라우팅 등)은 굳이 명시 X — 보고는 짧게. SKIP/ESCALATION엔 체크 요약 불필요.

**길이 룰:**
- 항목 3개 이내 → 한 줄에 ` / `로 구분
- 4개 이상 또는 80자 초과 → bullet 목록으로 줄바꿈 (최대 5개)
- 같은 카테고리 항목은 묶기 (예: `라벨/태그 9개`, `토큰 2개(bg-blue-weak, text-primary)`)

```
✅ PASS
"검증 통과 (8.4s) — light path
 체크: dropdown 라벨/태그 9개 / 토큰 (bg-blue-weak, text-primary) / console 에러"

🔧 PASS after fix
"검증 1차 실패 → 수정 후 통과 (52s)
 수정: handleSubmit에서 saveToken 누락 → 추가"

⏭️ SKIP (정상) — silent. 사용자 채팅에 출력 없음.
⏭️ SKIP (인프라 에러) — "검증 스킵: dev 서버 미기동 (`yarn dev` 후 재시도)"

❌ ESCALATION — 발견 문제 / 시도한 수정 2건 요약 / 추측 root cause. 코드는 마지막 수정 유지.
```

## Workflow Summary

```
1. [Auto] Stop hook에서 [auto-verify] 시그널 감지 OR [Manual] 사용자 요청
2. 이번 턴에 코드 변경 없으면 sentinel만 기록하고 종료
3. **Tier Selection** — diff 크기/범위로 light/full 분기 (얼마나)
4. **Category Selection** — diff 패턴으로 cat set 산출 (무엇을). A 그룹은 IIFE 1콜에 합침, 1-a는 조건부 스크린샷
5. Light Path: 메인 직접 (tab list / reload+eval / console / [선택]스크린샷) — 5–10초
   - PASS → 1줄 보고 + sentinel 기록 → 종료
   - 변경 미반영/console 에러 → 짧게 사유 보고 + sentinel 안 기록 (사용자 수정 유도)
   - light path가 cover 못 하는 변경 발견 → Full Path로 escalate
6. Full Path: Subagent dispatch (general-purpose) — Brief 템플릿 사용
7. 서브에이전트 결과 분류:
   - SKIP (정상) → **silent** + sentinel 기록 → 종료
   - SKIP (인프라 에러) → 짧게 보고 + sentinel 기록 → 종료
   - PASS → 짧게 보고 + sentinel 기록 → 종료
   - FAIL (코드 문제) → Fix Loop
8. Fix Loop (최대 2회): systematic-debugging → 수정 → 재검증
9. 최종 결과 보고
```

## Common Mistakes (검증 프로토콜 관점)

| 실수 | 방지 |
|---|---|
| **★ Navigation을 IIFE에 묶음** (실측 181s 폭주 사례) | navigation은 batch step으로 분리. `batch "<trigger>" "wait --url '**/dest'" "<verify>"`. IIFE 안에서 `location.href`/`reload`/router-click + `await sleep` + `return` 금지. |
| **풀 시퀀스 over-engineering** | Tier Selection으로 light path 진입. 한 줄 변경에 서브에이전트 풀 dispatch 금지. |
| **잘못된 탭 캡처** | tab switch 후 IIFE 안에서 `location.pathname` 재검증. mismatch면 사용자 안내 + 종료 (자동 navigate 강제 X). |
| **자체 브라우저 spawn** | 모든 호출에 `--cdp 9223` 필수. 9223 미응답이면 FAIL로 끊을 것. |
| **메인 컨텍스트 오염** | Full path는 항상 서브에이전트로 dispatch. Light path는 메인 직접 OK 단, 결과 50줄 이내. |
| **Sentinel 누락** | PASS/SKIP/인프라 에러 시 반드시 hash 기록. |

> 도구 사용 관련 실수 (`&&` 탭 컨텍스트 소실 / `open`으로 탭 오염 / 외부 sleep 폴링 / 뷰포트 변경 등)는 `agent-browser` 스킬의 "Navigation Boundary" + "안 쓰는 패턴" 참고.
