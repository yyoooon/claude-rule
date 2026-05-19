---
name: agent-browser
description: Use when running agent-browser CLI for desktop Chrome automation, especially multi-step UI flows. Trigger words — "agent-browser로", "9223 크롬으로", "띄워진 크롬으로 …", "기존 크롬에 붙어서", or any case where multi-step browser automation (5+ click/wait) is requested via agent-browser. Skip for: Playwright MCP, webview-test MCP (Android WebView), single screenshot/single click tasks (use raw agent-browser commands).
---

# agent-browser (도구 사용 카탈로그)

## Overview

agent-browser CLI 사용 기법 모음. **카테고리별로 패턴이 다르니** 작업 시작 전 카테고리부터 선언.

핵심 원칙:
- `--cdp 9223 + tab tN`으로 탭 명시 필수
- 멀티스텝은 eval IIFE 1콜 (CLI 부팅 비용 누적 방지)
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

"왜 좁아 보이지?" / "왜 흐릿하지?" 의문을 핀포인트로 잡는 디버깅.

```bash
agent-browser --cdp 9223 eval '
(() => {
  const inspect = (sel, label) => {
    const el = document.querySelector(sel);
    if (!el) return { label, error: "not found" };
    const cs = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    return {
      label,
      rect: { w: Math.round(r.width), h: Math.round(r.height) },
      color: cs.color,
      background: cs.backgroundColor,
      font: `${cs.fontSize}/${cs.lineHeight} ${cs.fontWeight}`,
      padding: cs.padding,
      gap: cs.gap,
      opacity: cs.opacity,
    };
  };
  return [
    inspect("[data-slot=card]", "card"),
    inspect("[data-slot=card] h3", "title"),
  ];
})()
'
```

**팁:**
- **부모/자식 같이** 뽑기 (`['.parent', '.child']`) — opacity 곱연산/padding 합산 추적
- **`getBoundingClientRect` 반드시 포함** — declared padding과 실제 렌더 크기가 다른 경우 흔함 (box-sizing, flex shrink, min-width 충돌)
- 4방향 따로 봐야 할 땐 `cs.paddingLeft` 등 분리

**눈으로 못 잡는 케이스 (이때만 유용):**

| 케이스 | 왜 눈으로 못 잡나 |
|---|---|
| 부모-자식 opacity 곱연산 (50%×50%=25%) | "좀 흐릿한가?" 수준 |
| 중첩 padding 합산 (outer + inner) | "어디서 좁아진지" 불명 |
| transform/scale 적용 시 실 사이즈 vs 시각 사이즈 | 사람 눈엔 같이 보임 |

**도구 한계:**
- `cs.color`는 `rgb(...)` 반환 — hex 비교 시 변환 필요
- `padding`/`gap`는 shorthand — 방향별 비교 시 각자 query
- CSS 변수는 resolved 값으로만 — 토큰 이름 일치는 못 봄

---

## 카테고리 2 — 단일 액션 (find + scoped snapshot)

"버튼 누르면 모달 뜨나" 같은 1-2 step.

```bash
# find 액션으로 snapshot 생략 — 2콜 → 1콜
agent-browser --cdp 9223 find text "Log Now" click
agent-browser --cdp 9223 find role button --name "Confirm" click

# 스코프 제한 snapshot — 시트 안만
agent-browser --cdp 9223 snapshot -i -c -d 2 -s "[role=dialog]"
agent-browser --cdp 9223 snapshot -i -c -d 2 -s "main, [role=main]"
```

**대기는 내장 waitFor 활용** — 커스텀 `setTimeout` 폴링 짜지 말 것:
```bash
agent-browser --cdp 9223 wait --selector "[role=dialog]"
```

IIFE 안에서 폴링 직접 짜야 하는 경우는 카테고리 3 참고.

---

## 카테고리 3 — 멀티스텝 IIFE (★ 가장 중요)

5+ 단계 시나리오. **CLI 부팅 비용 누적 방지가 핵심.**

### 패턴

1. **1-2회 eval로 구조 파악** — 폼/버튼 selector 덤프
2. **전체 플로우 IIFE** — 클릭/대기/입력을 JS 한 덩어리로 브라우저에 주입

### 구조 파악 dump

```bash
agent-browser --cdp 9223 eval '
(() => {
  const btns = [...document.querySelectorAll("button, [role=button]")]
    .filter(el => el.offsetParent !== null)
    .map(el => ({ text: el.textContent?.trim().slice(0,60), aria: el.getAttribute("aria-label") }));
  const inputs = [...document.querySelectorAll("input")]
    .filter(el => el.offsetParent !== null)
    .map(el => ({ type: el.type, placeholder: el.placeholder, inputmode: el.inputMode, value: el.value }));
  return { url: location.pathname, btns, inputs };
})()
'
```

**dump에서 다음 트리거 이미 잡혔다면 별도 호출 금지** — 첫 dump에 다음 단계 selector가 보이면 한 IIFE에 묶어버릴 것. 별도 eval로 끊으면 사용자 화면에 "모달 뜬 채 멈춤" 노출됨.

"다음 UI는 진짜 모르는" 케이스 (동적 폼, 조건부 분기) 한정으로만 중간 dump 허용.

### 전체 플로우 IIFE — trace + 실패 시 dumpDom

각 단계마다 trace 누적, 실패 시 DOM dump 같이 반환. 별도 호출 없이 한 콜 안에서 디버깅 컨텍스트 다 잡힘.

```js
(async () => {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const findBtn = (txt, root=document) => [...root.querySelectorAll("button, [role=button]")]
    .filter(el => el.offsetParent !== null)
    .find(el => el.textContent?.trim() === txt);
  const waitFor = async (predicate, timeout=3000) => {
    const t0 = Date.now();
    while (Date.now() - t0 < timeout) {
      const r = predicate();
      if (r) return r;
      await sleep(50);
    }
    return null;
  };

  const traces = [];
  const trace = (label, extra={}) => traces.push({
    step: traces.length + 1, label, url: location.pathname, ...extra
  });
  const dumpDom = () => ({
    visibleText: document.body.innerText.slice(0, 300),
    visibleBtns: [...document.querySelectorAll("button, [role=button]")]
      .filter(el => el.offsetParent !== null)
      .map(el => el.textContent?.trim().slice(0, 40)).filter(Boolean),
    errorEls: [...document.querySelectorAll("[role=alert], .error, [data-error]")]
      .map(el => el.textContent?.trim().slice(0, 200)),
  });

  // step 1
  const action = findBtn("Record Your Weight");
  if (!action) { trace("action NOT FOUND", dumpDom()); return { ok: false, traces }; }
  action.click();
  trace("clicked action");

  // step 2 — 모달 폴링
  const logNow = await waitFor(() => {
    const d = document.querySelector("[role=dialog]");
    return d ? findBtn("Log Now", d) : null;
  });
  if (!logNow) { trace("Log Now WAIT FAILED", dumpDom()); return { ok: false, traces }; }
  logNow.click();
  trace("clicked Log Now");

  // step 3 — React input
  const input = await waitFor(() => document.querySelector("input[inputmode=decimal]"));
  if (!input) { trace("input NOT FOUND", dumpDom()); return { ok: false, traces }; }
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
  setter.call(input, "60.5");
  input.dispatchEvent(new Event("input", { bubbles: true }));
  trace("input filled");

  // step 4
  findBtn("Confirm")?.click();
  trace("clicked Confirm");

  return { ok: true, traces };
})()
```

### React Input Fill — setter 필수

`input.value = "60"` 직접 대입은 React가 안 감지. 항상:

```js
const setReactValue = (el, val) => {
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
  setter.call(el, val);
  el.dispatchEvent(new Event("input", { bubbles: true }));
  el.dispatchEvent(new Event("change", { bubbles: true }));
};
```

### 고정 sleep 대신 element waitFor

```js
findBtn("Log Now").click();
await waitFor(() => document.querySelector("input[inputmode=decimal]"));  // 떴으면 즉시 진행
```

라우트 변경 후 첫 paint까지 평균 200-400ms. 고정 `sleep(1500)`는 그 차이만큼 화면에 텀으로 보임.

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

### 디버깅 dump 표준 (한 콜로 종합)

문제 재현 후 한 번에:

```bash
agent-browser --cdp 9223 eval '
(() => ({
  url: location.pathname,
  title: document.title,
  visibleText: document.body.innerText.slice(0, 500),
  errorEls: [...document.querySelectorAll("[role=alert], .error, [data-error]")]
    .map(el => el.textContent?.trim().slice(0, 200)),
  inputs: [...document.querySelectorAll("input")]
    .filter(el => el.offsetParent !== null)
    .map(el => ({ name: el.name, type: el.type, value: el.value, valid: el.validity.valid })),
  storage: { local: { ...localStorage }, cookie: document.cookie },
}))()
' && agent-browser --cdp 9223 console --json | head -30
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

폼 입력 변경 + 토큰 변경 + API 연동 변경이 한 PR에 있을 때:

```js
(async () => {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const traces = [];
  const trace = (label, extra={}) => traces.push({ step: traces.length+1, label, ...extra });

  // === cat 3: 멀티스텝 ===
  findBtn("저장").click();
  trace("clicked 저장");
  const dialog = await waitFor(() => document.querySelector("[role=dialog]"));
  if (!dialog) return { ok: false, traces };
  trace("modal opened");
  const input = dialog.querySelector("input[inputmode=decimal]");
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
  setter.call(input, "60.5");
  input.dispatchEvent(new Event("input", { bubbles: true }));
  trace("input filled");

  // === cat 1-b: 토큰 적용 확인 (같이) ===
  const card = document.querySelector("[data-slot=card]");
  const tokenCheck = {
    hasClass: card.classList.contains("bg-blue-weak"),
    bg: getComputedStyle(card).backgroundColor,
    rect: card.getBoundingClientRect().toJSON(),
  };

  // === cat 4: console/network은 IIFE 끝나고 외부 CLI로 ===
  return { ok: true, traces, tokenCheck };
})()
```

→ 그 다음 외부에서 `console --json` + `network requests --json` 2콜로 cat 4 처리. cat 1-a 필요하면 `screenshot --output /tmp/v.png` 추가로 1콜.

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

- ❌ `agent-browser click @e1 && wait 500 && click @e2` 식 체이닝 — CLI 부팅 누적
- ❌ `tab 2` (positional integer)
- ❌ `input.value = "..."` (React 안 감지)
- ❌ snapshot 5번 이상 반복 — 멈추고 IIFE로
- ❌ 모달/시트 띄운 직후 CLI 종료 + 별도 eval 재진입 — 사용자 화면에 "모달 뜬 채 멈춤" 노출
- ❌ 모달/페이지 전환 후 고정 `sleep(1000ms+)` — waitFor 폴링이 200-400ms면 충분
- ❌ 픽셀 단위 일치 판정 (1-2px, 색 hex 미세 비교)
- ❌ `agent-browser viewport ...` — 사용자가 띄운 탭 크기 변경 금지
