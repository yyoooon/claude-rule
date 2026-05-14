---
name: agent-browser
description: Use when running agent-browser CLI for desktop Chrome automation, especially multi-step UI flows. Trigger words — "agent-browser로", "9223 크롬으로", "띄워진 크롬으로 …", "기존 크롬에 붙어서", or any case where multi-step browser automation (5+ click/wait) is requested via agent-browser. Skip for: Playwright MCP, webview-test MCP (Android WebView), single screenshot/single click tasks (use raw agent-browser commands).
---

# agent-browser (개인 환경)

## Overview

agent-browser CLI 공식 디폴트는 `open → snapshot -i → click @e1 → snapshot -i → ...` 루프지만, 매 invocation마다 CLI 부팅 비용이 들어 5+ step 누적 시 체감 매우 느림. 이 스킬은 **멀티스텝 시 eval JS 묶음** 패턴과 **CDP attach 함정** 회피를 강제한다.

**핵심:** 구조 파악 1-2회 → 나머지는 eval IIFE 1회. `--cdp 9223 + tab tN`으로 탭 명시 필수. React input은 setter+dispatchEvent.

## When to Use

- 사용자가 "agent-browser로" / "9223 크롬으로" / "띄워진 크롬에서" 명시
- 멀티스텝 시나리오 (5+ click/wait/fill)
- Playwright MCP가 느려서 대안 찾는 맥락
- 기존 크롬 인스턴스에 CDP attach (`http://127.0.0.1:9223`)

## When NOT to Use

- 단일 스크린샷 / 단일 클릭 → 그냥 `agent-browser open + screenshot` 한 줄
- 실기기 Android WebView → `webview-test` MCP
- 회귀 테스트 자산화 → Playwright Test
- 자동 검증 (Stop hook) → `browser-verification` 스킬

## 디폴트 워크플로우 (멀티스텝)

### 1. CDP attach + 탭 확인 (필수)

같은 크롬에 여러 탭 떠있으면 잘못된 탭에 붙는다. 반드시 탭 명시.

```bash
agent-browser --cdp 9223 tab list
# → [t1] Care Home - http://localhost:3002/
#    [t2] Care Home - http://localhost:3001/

agent-browser --cdp 9223 tab t2   # 원하는 탭으로 활성화
agent-browser --cdp 9223 eval "location.href"   # 검증
```

**함정:** `tab 2` (positional integer) X. 반드시 `tab t2` (stable id).

### 2. 구조 파악 (1-2회 eval만)

snapshot-ref 루프 돌리지 말 것. eval 한 번으로 필요한 selector / 버튼 텍스트 / input 타입 한 번에 덤프:

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

UI가 단계마다 바뀌면 (모달/시트 열고 닫힘), **다음 단계 직전에 한 번 더** 덤프해서 새 selector 파악.

### 3. 전체 플로우는 eval IIFE 1회

구조 파악 끝나면 한 IIFE에 전부 묶어서 1회 호출. 중간 click/wait도 JS 안에서:

```bash
agent-browser --cdp 9223 eval '
(async () => {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const findBtn = txt => [...document.querySelectorAll("button, [role=button]")]
    .filter(el => el.offsetParent !== null)
    .find(el => el.textContent?.trim() === txt);

  // step 1
  const a = findBtn("Cancel");
  a?.click(); await sleep(800);

  // step 2
  const b = findBtn("Log Now");
  b?.click(); await sleep(1200);

  // step 3 — React input fill
  const input = [...document.querySelectorAll("input")]
    .find(el => el.inputMode === "decimal");
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
  setter.call(input, "60.5");
  input.dispatchEvent(new Event("input", { bubbles: true }));
  await sleep(300);

  // step 4
  findBtn("Confirm")?.click();
  await sleep(1500);

  return { ok: true, url: location.pathname };
})()
'
```

## React Input Fill (반드시 setter 통해서)

`input.value = "60"` 직접 대입은 React가 안 감지한다. 항상 prototype setter 통해서 + `input`/`change` 이벤트 dispatch:

```js
const setReactValue = (el, val) => {
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
  setter.call(el, val);
  el.dispatchEvent(new Event("input", { bubbles: true }));
  el.dispatchEvent(new Event("change", { bubbles: true }));
};
```

## Element 찾기 패턴

| 케이스 | 패턴 |
|--------|------|
| 버튼 정확 매칭 | `findBtn(txt)` (위 헬퍼) |
| 부분 텍스트 매칭 | `el.textContent?.includes(txt)` |
| visible만 | `.filter(el => el.offsetParent !== null)` |
| input by type | `inputMode === "decimal"` / `type === "number"` 등 |
| `role=dialog` 시트 안만 | scope 좁히기 — `document.querySelector("[role=dialog]")` 안에서 검색 |

## 스타일/시각 검증 (Figma 4-check)

agent-browser는 픽셀 단위 자동 회귀는 못 하지만, **Figma 시안과 구현 토큰이 일치하는지** 검증엔 잘 맞는다. 메모리의 `applying-figma-designs` 4-check 패턴을 eval IIFE로:

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
      rect: { w: Math.round(r.width), h: Math.round(r.height), x: Math.round(r.x), y: Math.round(r.y) },
      color: cs.color,
      background: cs.backgroundColor,
      font: `${cs.fontSize}/${cs.lineHeight} ${cs.fontWeight}`,
      padding: cs.padding,
      gap: cs.gap,
      opacity: cs.opacity,
      borderRadius: cs.borderRadius,
    };
  };
  return [
    inspect("[data-slot=card]", "card"),
    inspect("[data-slot=card] h3", "title"),
    inspect("[data-slot=card] button", "cta"),
  ];
})()
'
```

**4-check 항목** (메모리 `feedback_figma_apply_verification.md`):
1. 컨테이너 간 **gap** — `gap` 값 비교
2. **Figma vs 현재 시각 비교** — screenshot 1컷 떠서 같이 Read (vision)
3. **부모-자식 opacity 분리** — `opacity` 값 비교
4. **중첩 padding 합산** — 부모/자식 padding 더해서 실 시각적 spacing 추출

screenshot은 vision 비교용 (jpeg 70%로 작게):

```bash
agent-browser --cdp 9223 screenshot impl.jpeg  # AGENT_BROWSER_SCREENSHOT_DIR 디폴트로 /tmp
# Figma 시안 스크린샷 옆에 두고 같이 Read → 갭/정렬/대조 비교
```

⚠️ 금지: **자동 검증 스킬(browser-verification) 안에선 computedStyle 비교 금지.** 그 스킬은 동작/에러 검증 전용. 스타일 검증은 사용자 명시 요청 시에만 별도로.

## 디버깅 (console / network / state)

agent-browser는 네이티브 console/network 캡처 지원. 디버깅 일상에 적합.

### 콘솔 에러 빠른 진단

```bash
# 클리어 → 페이지 동작 → 캡처
agent-browser --cdp 9223 console --clear
# (사용자가 페이지 조작 or eval로 시뮬레이션)
agent-browser --cdp 9223 console --json | head -50
```

### 네트워크 4xx/5xx만 추출

```bash
agent-browser --cdp 9223 network requests --clear
# 조작
agent-browser --cdp 9223 network requests --status 4xx --json
agent-browser --cdp 9223 network requests --status 5xx --json
# 특정 API만
agent-browser --cdp 9223 network requests --filter "/api/v1/users" --json
```

### API 응답 mocking (1회성)

특정 API가 깨졌다 치고 UI 확인 / 빈 상태 점검:

```bash
agent-browser --cdp 9223 network route "**/api/v1/foo" --body '{"items":[]}'   # 빈 응답
agent-browser --cdp 9223 network route "**/api/v1/bar" --abort                  # 실패
agent-browser --cdp 9223 unroute   # 끝나면 정리
```

### React state / 컨텍스트 덤프

페이지 내부 상태 추출 (devtools 안 켜고):

```bash
agent-browser --cdp 9223 eval '
(() => {
  // localStorage / sessionStorage / cookie
  const storage = {
    local: { ...localStorage },
    session: { ...sessionStorage },
    cookie: document.cookie,
  };
  // React Query cache (window에 노출돼있다면)
  const rq = window.__REACT_QUERY_DEVTOOLS__?.queryClient?.getQueryCache().getAll()
    .map(q => ({ key: q.queryKey, status: q.state.status, error: q.state.error?.message }));
  return { storage, rq, url: location.pathname };
})()
'
```

### 디버깅 dump 표준 패턴 (한 방)

문제 재현 후 한 콜로 종합 진단:

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
}))()
' && agent-browser --cdp 9223 console --json | head -30
```

## 속도 최적화 (정확성 손상 X)

### a. 스냅샷 스코프로 토큰/시간 둘 다 절감
전체 트리 덤프 금지. 항상 `-i -c -d 2 -s "<selector>"`:

```bash
agent-browser --cdp 9223 snapshot -i -c -d 2 -s "[role=dialog]"    # 시트 안만
agent-browser --cdp 9223 snapshot -i -c -d 2 -s "main, [role=main]" # 메인 영역만
```

### b. `find` 액션으로 snapshot 생략
"버튼 텍스트 X 클릭" 같은 단발은 snapshot 없이 1콜:

```bash
agent-browser --cdp 9223 find text "Log Now" click
agent-browser --cdp 9223 find role button --name "Confirm" click
```

snapshot → @ref 클릭 2콜 → 1콜로 단축.

### c. 고정 sleep 대신 element wait
JS IIFE 안에서도 가능하면 polling. `await sleep(1500)`는 페이지가 빨리 떴어도 끝까지 기다림.

```js
const waitFor = async (sel, timeout=3000) => {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    const el = document.querySelector(sel);
    if (el && el.offsetParent !== null) return el;
    await new Promise(r => setTimeout(r, 50));
  }
  throw new Error("timeout: " + sel);
};

// 사용
findBtn("Log Now").click();
await waitFor("input[inputmode=decimal]");   // 떴으면 즉시 진행
```

라우트 변경 후 첫 paint까지 평균 200-400ms — 고정 1.5s sleep을 200ms 가까이로 줄임.

### d. 스크린샷은 JPEG + /tmp 디폴트
환경변수 한 번 박아두면 매번 경로/포맷 안 적어도 됨:

```bash
export AGENT_BROWSER_SCREENSHOT_DIR=/tmp
export AGENT_BROWSER_SCREENSHOT_FORMAT=jpeg
export AGENT_BROWSER_SCREENSHOT_QUALITY=70
```

검증용 스샷이라면 jpeg 70%면 충분 (png 대비 ~5-10배 작음 → Read 토큰도 줄어듦).

### e. 첫 콜 느리면 데몬 꺼져있던 것
세션 시작 후 첫 `agent-browser` 호출이 유독 느린(2-3s) 경우, daemon 콜드 스타트. 두 번째부터 정상. 대처:

```bash
agent-browser --cdp 9223 eval "1" >/dev/null   # 워밍업 핑 (선택)
```

### f. snapshot/eval 결과 head로 잘라 토큰 절감
구조 파악용 덤프는 `| head -50` 또는 `| tail -40`로 자름. visible buttons 10개만 봐도 충분.

## 사용자 시그널 → 즉시 전환

| 사용자 신호 | 행동 |
|-------------|------|
| "너무 느려" / "답답해" | 즉시 snapshot-ref 루프 중단 → eval IIFE 패턴으로 |
| "다시 한 번에 가" | 전체 시나리오를 단일 eval로 재구성 |
| "기존 크롬으로" / "9223" | `--cdp 9223 + tab list + tab tN` 절차 항상 적용 |

## 안 쓰는 패턴

- ❌ `agent-browser click @e1 && agent-browser wait 500 && agent-browser click @e2` 식 체이닝 — CLI 부팅 누적
- ❌ `tab 2` (positional integer)
- ❌ `input.value = "..."` (React 안 감지)
- ❌ snapshot 5번 이상 반복 — 그 시점에 멈추고 eval 묶음으로
