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
- 자동 검증 (Stop hook) → `playwright-verification` 스킬

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
