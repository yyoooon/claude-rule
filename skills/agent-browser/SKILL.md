---
name: agent-browser
description: MANDATORY before ANY agent-browser CLI call when the user explicitly names agent-browser/9223 — even single-shot fetches, screenshots, or network checks. Trigger words — "agent-browser로", "agent-browser 써서", "브라우저 에이전트로/써서", "9223 크롬으로", "9223으로 확인", "띄워진 크롬으로 …", "기존 크롬에 붙어서". Also use for multi-step browser automation (5+ click/wait) without explicit trigger. Skip for: Playwright MCP, webview-test MCP (Android WebView). When user did NOT mention agent-browser/9223 AND task is single screenshot/click, raw CLI is OK.
---

# agent-browser (도구 사용 카탈로그)

## Overview

agent-browser CLI 사용 기법 모음. **카테고리별로 패턴이 다르니** 작업 시작 전 카테고리부터 선언.

핵심 원칙:
- `--cdp 9223 + tab tN`으로 탭 명시 필수
- **Navigation-aware primitive 우선** — `batch` / `wait --url` / `wait --load` / `find <locator> <value> <action>` / `pushstate`. IIFE를 첫 도구로 꺼내기 전에 이걸로 표현 가능한지 먼저 점검 (아래 "Tool Selection Hierarchy" 참고)
- **페이지 전환 없는** 멀티스텝은 eval IIFE 1콜 (같은 페이지 내 폼/모달/DOM 검사)
- **페이지 전환을 동반하는** 멀티스텝은 `batch` + `wait --url`로 묶기 — IIFE 안에서 `location.href`/`reload`/navigation 트리거 click을 묶으면 CDP context 끊겨 재시도 turn 폭주 (아래 "Navigation Boundary" 참고)
- React input은 setter+dispatchEvent (직접 `.value` 대입은 React가 안 감지)
- **픽셀 단위 일치 판정은 안 함** (#DC2626 vs #DC2727, 16px vs 17px 같은 미세 비교)

## 검증 카테고리 (시작 전 선언)

| 카테고리 | 목적 | 주 패턴 |
|---|---|---|
| **1-a** 시각 sanity | 변경이 화면에 반영됐나 (매크로) | 스크린샷 1장 + Read |
| **1-b** 렌더 원인 분석 | "왜 이렇게 보이지?" 디버깅 | computed style + rect 덤프 |
| **2** 단일 액션 | 클릭 → 모달 뜸 같은 1-2 step | find + scoped snapshot |
| **3** 멀티스텝 ★ | 5+ 단계 시나리오 | eval IIFE 1콜 + trace |
| **4** 네트워크/콘솔 | API 실패, 빈 데이터, 에러 바운더리 | console + network --json |

AI가 헷갈리지 않게 **사용자가 카테고리를 선언**하거나 본 스킬이 첫 응답에서 추론 후 명시.

---

## 시작 전 — CDP attach + 탭 확인 (모든 카테고리 공통)

같은 크롬에 여러 탭 떠있으면 잘못된 탭에 붙는다. 반드시 탭 명시.

```bash
agent-browser --cdp 9223 tab list
# → [t1] Care Home - http://localhost:3002/
#    [t2] Care Home - http://localhost:3001/

agent-browser --cdp 9223 tab t2                # 원하는 탭 활성화
agent-browser --cdp 9223 eval "location.href"  # 검증
```

⚠️ **`tab 2` (positional integer) X**. 반드시 `tab t2` (stable id).
⚠️ **viewport 변경 금지** — 사용자가 띄운 탭 크기 그대로 사용 (`agent-browser viewport` 호출 금지).

---

## Tool Selection Hierarchy (이 순서로 먼저 점검)

작업을 IIFE로 짜기 전에 항상 위에서 아래로 매칭되는지 확인. **위로 갈수록 빠르고, LLM turn도 더 적게 먹는다.**

| 우선순위 | 패턴 | 언제 |
|---|---|---|
| 1 | `find <locator> <value> <action>` | "X 텍스트 버튼 클릭" 같은 단일 액션. snapshot도 IIFE도 불필요 |
| 2 | `batch "cmd1" "cmd2" ..."` | 여러 step을 **CLI 내부에서** 순차 실행. LLM turn 1번, CDP attach 1번. navigation 동반해도 step 사이에 `wait --url`/`wait --load` 끼우면 안전 |
| 3 | `wait --url '**/foo'` / `wait --load networkidle` / `wait --text "..."` | hard sleep 대체. SPA navigation 완료를 정확히 감지 → CDP race 안 남 |
| 4 | `pushstate <url>` | Next.js `next.router.push` 자동 감지 SPA navigation. `location.href = ...`보다 안전 (RSC fetch 트리거됨) |
| 5 | eval IIFE | **같은 페이지 내** 다단계 DOM 조작/검사. `setReactValue` 같이 CLI primitive로 표현 불가능한 케이스 |
| 6 | snapshot + ref | 페이지 구조를 모를 때 1회 정찰. 그 다음은 1-4 중 하나로 |

### 결정 룰

- **단일 click/fill** → `find text "..." click` / `find label "..." fill "..."`
- **click → 페이지 이동 → 새 페이지 검증** → `batch "find text '...' click" "wait --url '**/dest'" "get url"` (3 step 1 turn)
- **click → 모달/시트 등장 → fill** → 같은 페이지 내라 IIFE OK
- **폼 입력 → submit → 페이지 이동** → IIFE로 입력까지 + `batch`로 submit + wait
- **navigation 직접 트리거** → `pushstate /target` 또는 `batch "eval 'router 트리거'" "wait --url '**/target'"`

IIFE는 "**같은 페이지 내**에서만 묶는 도구"로 본다. navigation 경계를 가로지르는 순간 batch로 갈아탄다.

---

## Navigation Boundary (★ CDP race 방지)

CDP `Runtime.evaluate`는 응답이 돌아오기 전 page navigation이 일어나면 execution context가 무효화돼 `"Inspected target navigated or closed"` 에러 발생. **재시도 turn 누적 = 시간 폭주의 주범.**

### IIFE 안에서 절대 묶지 말 것

다음 작업은 IIFE 내부에서 호출하지 말 것. **모두 batch step으로 분리:**

- `location.href = "..."` / `location.assign(...)` / `location.replace(...)`
- `location.reload()`
- `history.pushState(...)` 직후 라우터가 트리거하는 RSC fetch
- `<a href>` / `router.push`/`router.replace` 트리거하는 `.click()`
- `<form>` submit이 navigation을 일으키는 경우

### 올바른 패턴 (batch + wait)

```bash
# nav 트리거 → 완료 대기 → 검증
agent-browser --cdp 9223 batch \
  "find text 'View Sleep HRV Details' click" \
  "wait --url '**/tracker/energy'" \
  "get url"
```

```bash
# 직접 SPA navigation
agent-browser --cdp 9223 batch \
  "pushstate /tracker/energy" \
  "wait --load networkidle" \
  "find text 'Energy Score' wait"
```

```bash
# reload 후 검증 (cross-route 진입, scenario state 변경 등)
agent-browser --cdp 9223 batch \
  "eval 'sessionStorage.setItem(\"key\", \"value\")'" \
  "reload" \
  "wait --load networkidle" \
  "eval '({ ok: location.pathname === \"/expected\" })'"
```

batch 안의 `wait --url`/`wait --load`는 CDP가 새 context로 reattach될 때까지 정확히 block. 외부에서 `sleep + tab list` 폴링하는 패턴보다 훨씬 빠르고 안전.

### 안 되는 케이스 (IIFE로 가야 하는)

같은 페이지 내 폼 입력 → 모달 등장 → 입력 → submit 같은 시나리오는 navigation이 없으므로 그대로 IIFE 유지. batch는 step 사이에 React 상태/CSS-in-JS hydration 같은 정밀 폴링이 필요한 케이스는 약함.

---

## 카테고리 1-a — 시각 sanity (스크린샷 1장)

"변경이 의도대로 화면에 반영됐나" 매크로 확인.

```bash
agent-browser --cdp 9223 screenshot --output /tmp/shot.png
# 이후 Read(/tmp/shot.png)로 멀티모달 해석
```

**용도:** 색 카테고리 바뀜 / 컴포넌트 누락 / 글랜더 깨짐 같은 **큰 그림 sanity**.
**금지:** 픽셀 단위 일치 판정 (1-2px 차이, 색 hex 미세 비교).

⚙️ **환경 디폴트 박아두면 매번 경로 안 적어도 됨:**
```bash
export AGENT_BROWSER_SCREENSHOT_DIR=/tmp
export AGENT_BROWSER_SCREENSHOT_FORMAT=jpeg
export AGENT_BROWSER_SCREENSHOT_QUALITY=70
```
검증용은 jpeg 70% 충분 — Read 토큰도 작아짐.

---

## 카테고리 1-b — 렌더 원인 분석 (computed style + rect)

"왜 좁아 보이지?" / "왜 흐릿하지?" 디버깅. **부모/자식 같이** 뽑고 `getBoundingClientRect` 포함 (declared padding과 실제 렌더가 box-sizing/flex shrink/min-width로 다른 경우 흔함).

```bash
agent-browser --cdp 9223 eval '
(() => {
  const inspect = (sel) => {
    const el = document.querySelector(sel); if (!el) return null;
    const cs = getComputedStyle(el); const r = el.getBoundingClientRect();
    return { sel, w: Math.round(r.width), h: Math.round(r.height),
      bg: cs.backgroundColor, color: cs.color, padding: cs.padding, opacity: cs.opacity };
  };
  return [inspect("[data-slot=card]"), inspect("[data-slot=card] h3")];
})()'
```

**유용한 케이스**: 부모-자식 opacity 곱연산 / 중첩 padding 합산 / transform·scale 실 사이즈 vs 시각 사이즈. 눈으로 못 잡음.

**한계**: `cs.color`는 `rgb(...)` (hex 비교 시 변환), shorthand padding/gap은 방향별 분리 query, CSS 변수는 resolved 값 (토큰 이름 일치는 못 봄).

---

## 카테고리 2 — 단일 액션 (find + wait + scoped snapshot)

"버튼 누르면 모달 뜨나" / "링크 누르면 어디로 가나" 같은 1-2 step.

```bash
# find 액션으로 snapshot 생략 — 2콜 → 1콜
agent-browser --cdp 9223 find text "Log Now" click
agent-browser --cdp 9223 find role button --name "Confirm" click

# 스코프 제한 snapshot — 시트 안만
agent-browser --cdp 9223 snapshot -i -c -d 2 -s "[role=dialog]"
agent-browser --cdp 9223 snapshot -i -c -d 2 -s "main, [role=main]"
```

### 대기 — 상황별 wait 선택

커스텀 `setTimeout` 폴링 짜지 말 것. 상황에 맞는 wait 선택:

```bash
agent-browser --cdp 9223 wait "[role=dialog]"           # 엘리먼트 등장
agent-browser --cdp 9223 wait --text "Success"          # 텍스트 등장
agent-browser --cdp 9223 wait --url '**/dashboard'      # URL 패턴 매칭 (navigation 완료)
agent-browser --cdp 9223 wait --load networkidle        # 네트워크 idle (SPA hydration 안전 대기)
agent-browser --cdp 9223 wait --fn "window.app.ready"   # JS 표현식 truthy
```

### Navigation 동반 단일 액션 → batch 1콜

"링크 클릭 → URL 변경 검증" 같은 패턴은 IIFE 짜지 말고 batch:

```bash
agent-browser --cdp 9223 batch \
  "find text 'View Details' click" \
  "wait --url '**/tracker/energy'" \
  "get url"
```

→ LLM turn 1번. CDP race 0번. IIFE + 외부 sleep + tab list 폴링 패턴보다 10배 빠름.

IIFE 안에서 폴링 직접 짜야 하는 경우(같은 페이지 내 React 상태/모달 등장 등)는 카테고리 3 참고.

---

## 카테고리 3 — 멀티스텝 (★ 가장 중요)

5+ 단계 시나리오. **CLI 부팅 비용 누적 방지가 핵심.**

### 먼저 — 페이지 전환 있나?

| 시나리오 | 도구 |
|---|---|
| **같은 페이지 내**만 (모달 열고 폼 입력 → submit → 모달 닫힘) | IIFE 1콜 |
| **페이지 전환 포함** (form submit → /next-page → 새 페이지에서 검증) | **batch** ↔ IIFE 혼합 |
| **순수 navigation 체인** (link click → page A → link click → page B) | batch only |

페이지 전환 가로지르는 IIFE는 CDP race로 깨진다 — "Navigation Boundary" 섹션 참고. batch + wait로 갈아탈 것.

### batch ↔ IIFE 혼합 예시

폼 입력은 IIFE, navigation은 batch:

```bash
# step 1 — 같은 페이지 내 폼 채우기 (IIFE)
agent-browser --cdp 9223 eval '
(() => {
  const input = document.querySelector("input[name=weight]");
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
  setter.call(input, "60.5");
  input.dispatchEvent(new Event("input", { bubbles: true }));
  return { filled: input.value };
})()'

# step 2 — submit → navigation → 다음 페이지 검증 (batch)
agent-browser --cdp 9223 batch \
  "find role button --name 'Save' click" \
  "wait --url '**/record/summary'" \
  "find text '저장 완료' wait" \
  "get url"
```

### 같은 페이지 시나리오 IIFE 패턴

1. **1-2회 eval로 구조 파악** — 폼/버튼 selector 덤프
2. **전체 플로우 IIFE** — 클릭/대기/입력을 JS 한 덩어리로 브라우저에 주입

### 구조 파악 dump (선택)

페이지 구조 모를 때만 1회. 보통은 코드 Read로 selector 먼저 파악.

```bash
agent-browser --cdp 9223 eval '
(() => ({
  url: location.pathname,
  btns: [...document.querySelectorAll("button, [role=button]")].filter(el => el.offsetParent).map(el => el.textContent?.trim().slice(0,60)),
  inputs: [...document.querySelectorAll("input")].filter(el => el.offsetParent).map(el => ({ type: el.type, name: el.name, value: el.value })),
}))()'
```

dump에 다음 단계 selector 잡혔으면 별도 호출 X — 한 IIFE에 묶어버릴 것 (사용자 화면에 "모달 뜬 채 멈춤" 노출 방지).

### 전체 플로우 IIFE 패턴

각 단계마다 trace 누적, 실패 시 dumpDom 같이 반환. 한 콜로 디버깅 컨텍스트 다 잡힘.

```js
(async () => {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const findBtn = (txt, root=document) => [...root.querySelectorAll("button, [role=button]")]
    .filter(el => el.offsetParent !== null)
    .find(el => el.textContent?.trim() === txt);
  const waitFor = async (pred, ms=3000) => {
    const t0 = Date.now();
    while (Date.now() - t0 < ms) { const r = pred(); if (r) return r; await sleep(50); }
    return null;
  };
  const traces = [];
  const trace = (label, extra={}) => traces.push({ step: traces.length+1, label, ...extra });
  const dumpDom = () => ({
    visibleText: document.body.innerText.slice(0, 300),
    errorEls: [...document.querySelectorAll("[role=alert], .error")].map(el => el.textContent?.trim().slice(0, 200)),
  });

  findBtn("Record Weight")?.click(); trace("opened modal");
  const input = await waitFor(() => document.querySelector("input[inputmode=decimal]"));
  if (!input) { trace("input not found", dumpDom()); return { ok: false, traces }; }
  setReactValue(input, "60.5"); trace("filled");
  findBtn("Confirm")?.click(); trace("submitted");
  return { ok: true, traces };
})()
```

### React Input Fill — setter 필수

`input.value = "60"` 직접 대입은 React가 안 감지:

```js
const setReactValue = (el, val) => {
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
  setter.call(el, val);
  el.dispatchEvent(new Event("input", { bubbles: true }));
  el.dispatchEvent(new Event("change", { bubbles: true }));
};
```

### 고정 sleep 대신 element waitFor

같은 페이지 내 모달/요소 등장은 `waitFor` 50ms 폴링 (200-400ms 안에 끝남). 페이지 전환은 IIFE 밖 `wait --url`/`wait --load` 사용.

---

## 카테고리 4 — 네트워크/콘솔

API 실패, 빈 데이터, 에러 바운더리, console 에러.

### 콘솔 에러 빠른 진단

```bash
agent-browser --cdp 9223 console --clear
# (조작)
agent-browser --cdp 9223 console --json | head -50
```

### 네트워크 4xx/5xx만 추출

```bash
agent-browser --cdp 9223 network requests --clear
# (조작)
agent-browser --cdp 9223 network requests --status 4xx --json
agent-browser --cdp 9223 network requests --status 5xx --json
agent-browser --cdp 9223 network requests --filter "/api/v1/users" --json
```

### Mocking (1회성)

```bash
agent-browser --cdp 9223 network route "**/api/v1/foo" --body '{"items":[]}'  # 빈 응답
agent-browser --cdp 9223 network route "**/api/v1/bar" --abort                 # 실패
agent-browser --cdp 9223 unroute   # 끝나면 정리
```

### ⚠️ 콘솔이 만능 아님

콘솔에 **안 찍히는** 실패 흔함:
- React Suspense fallback 무한 루프
- Optimistic update silent rollback
- React Query `enabled: false` — 요청 자체가 안 나감
- Error Boundary가 잡아서 silent

→ 콘솔만 보고 "이상 없음" 단정 금지. **네트워크 탭 같이** 볼 것.

### 디버깅 dump 표준 (한 콜)

```bash
agent-browser --cdp 9223 eval '
(() => ({
  url: location.pathname,
  errorEls: [...document.querySelectorAll("[role=alert], .error, [data-error]")].map(el => el.textContent?.trim().slice(0, 200)),
  inputs: [...document.querySelectorAll("input")].filter(el => el.offsetParent).map(el => ({ name: el.name, value: el.value, valid: el.validity.valid })),
  storage: { local: { ...localStorage }, cookie: document.cookie },
}))()'
```

---

## 다중 카테고리 합치기 (효율 실행)

여러 카테고리가 동시에 필요할 때 콜 수 최소화 패턴. CSS + 폼 + API가 한 PR에 같이 들어와도 1콜+2콜+(선택)1콜로 끝.

### A/B/C 그룹

| 그룹 | 카테고리 | 실행 방식 |
|---|---|---|
| **A. Eval IIFE 1콜** | 1-b, 2, 3 | DOM-side 전부 한 IIFE에 묶음 |
| **B. 사이드 CLI** | 4 | `console --json` + `network requests --json` 2콜 (싸다) |
| **C. 별도 콜 + Read** | 1-a | 스크린샷 + 이미지 Read (이미지 토큰 비용) |

→ **5개 카테고리 다 켜져도 IIFE 1콜 + console/network 2콜 + (선택)스크린샷 1콜 = 5-10초 종료.**

### IIFE 본문 조립 규칙 (A 그룹)

cat set에 따라 한 IIFE 안에 묶음:
- **1-b 포함** → `inspect(sel)` 헬퍼로 computed style + rect 캡처 추가
- **2 포함** → 단일 element click 시뮬레이션 추가
- **3 포함** → trace + waitFor + React setter 다단계 시뮬레이션 추가

### 예시 — cat 1-b + 3 + 4 동시 수행

폼 입력 + 토큰 변경 + API 연동이 한 PR에 있을 때:

```js
(async () => {
  // cat 3: 멀티스텝 — 모달 열고 입력
  findBtn("저장")?.click();
  const dialog = await waitFor(() => document.querySelector("[role=dialog]"));
  if (!dialog) return { ok: false, reason: "modal not opened" };
  setReactValue(dialog.querySelector("input[inputmode=decimal]"), "60.5");

  // cat 1-b: 토큰 적용 확인 (같이)
  const card = document.querySelector("[data-slot=card]");
  return {
    ok: true,
    tokenCheck: {
      hasClass: card.classList.contains("bg-blue-weak"),
      bg: getComputedStyle(card).backgroundColor,
    },
  };
})()
```

→ 외부에서 `console --json` + `network requests --status 4xx --json` 2콜로 cat 4 처리. cat 1-a 필요하면 `screenshot --output /tmp/v.png` 추가.

---

## Element 찾기 패턴

| 케이스 | 패턴 |
|---|---|
| 버튼 정확 매칭 | `findBtn(txt)` |
| 부분 텍스트 매칭 | `el.textContent?.includes(txt)` |
| visible만 | `.filter(el => el.offsetParent !== null)` |
| input by type | `inputMode === "decimal"` / `type === "number"` |
| dialog 안에서만 | `document.querySelector("[role=dialog]")` 스코프 |

---

## 사용자 시그널 → 즉시 전환

| 시그널 | 행동 |
|---|---|
| "너무 느려" / "답답해" | 즉시 snapshot-ref 루프 중단 → eval IIFE |
| "다시 한 번에 가" | 전체 시나리오 단일 eval 재구성 |
| "기존 크롬으로" / "9223" | `--cdp 9223 + tab list + tab tN` 적용 |

---

## 안 쓰는 패턴

- ❌ `agent-browser click @e1 && wait 500 && click @e2` 식 shell 체이닝 — `batch "click @e1" "wait 500" "click @e2"`로 묶을 것 (CLI 부팅 1회로)
- ❌ `tab 2` (positional integer)
- ❌ `input.value = "..."` (React 안 감지)
- ❌ snapshot 5번 이상 반복 — 멈추고 `find` 또는 IIFE로
- ❌ 모달/시트 띄운 직후 CLI 종료 + 별도 eval 재진입 — 사용자 화면에 "모달 뜬 채 멈춤" 노출
- ❌ 모달/페이지 전환 후 고정 `sleep(1000ms+)` — `wait --url`/`wait --text`/`wait <sel>`이 navigation 완료를 정확히 감지
- ❌ **IIFE 안에서 `location.href`/`location.reload()`/router 트리거 click** — CDP context 끊김 → "Inspected target navigated or closed" → 재시도 turn 폭주. `batch "..." "wait --url '**/...'" "..."`로 분리.
- ❌ **IIFE 안에서 `location.href = "/"` 후 `await sleep(1500); return ...`** — return이 CDP에 도달하기 전 nav 완료되며 끊김. 같은 함정.
- ❌ **navigation 후 외부에서 `sleep + tab list`로 폴링** — `wait --url '**/dest'` 1콜로 끝남
- ❌ 픽셀 단위 일치 판정 (1-2px, 색 hex 미세 비교)
- ❌ `agent-browser viewport ...` — 사용자가 띄운 탭 크기 변경 금지
