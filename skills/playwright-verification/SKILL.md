---
name: playwright-verification
description: Use when UI layout/style changes or user flows (form, button, modal, route, navigation, state transition) are added/modified ("UI 고쳐줘", "레이아웃/스타일 수정", "플로우 추가", "동작 확인해줘", "스크린샷으로 봐줘", "리디자인 적용", "버그 픽스", "라우트/다이얼로그 추가") — verify in dev server with Playwright MCP before reporting completion. Symptoms: just edited JSX/CSS, added a route/dialog, fixed a race condition, changed API response handling. Skip for pure refactors, type-only edits, comments/naming (순수 리팩터, 타입만 수정, 주석·네이밍 변경).
---

# Playwright Verification

## Overview

UI/기능 변경 후 **코드 읽기나 computed style 수치만으로 보고하지 말 것**. 레이아웃 정확성은 눈으로만 판단 가능하고, 동작 정확성은 시뮬레이션으로만 확인 가능. 디폴트 도구는 **Playwright MCP + 실행 중인 dev 웹**.

`superpowers:verification-before-completion`의 UI/플로우 변경 특화 버전. Figma 적용 작업 중이면 `applying-figma-designs` 스킬의 Step 3(자체 검증)이 이 스킬을 호출.

## When to Use

**시각 검증 (UI 변경)**
- 레이아웃·구조·정렬·간격이 바뀌는 작업
- Figma 적용/리디자인
- CSS/스타일/토큰 수정

**동작 검증 (기능 변경)**
- 새 플로우/route/dialog 추가
- 기존 플로우 수정 (auth, fetch, 상태 전환)
- 읽기로 확신 어려운 버그 픽스 (race condition, 조건부 렌더)
- 데이터 흐름 변경 (API 응답 처리, 캐시 무효화, 폼 제출)

## When NOT to Use

- 순수 리팩터 (행동 변경 없음)
- 타입만 수정 / 주석·네이밍 변경
- 빌드 스크립트·설정 파일
- 웹뷰/실기기 검증 → **웹뷰 전환 조건** 섹션 참고

## Step 0: 환경 설정 및 타겟 확인 (Environment Setup)

검증을 시작하기 전, 다음 순서로 타겟 URL(포트 번호)과 Auth 정보를 획득할 것.

1. **명시적 인수 ($ARGUMENTS):** 명령어 호출 시 인수로 포트나 타겟 정보가 들어왔다면 최우선으로 사용할 것. (예: `$1` = 포트 번호, `$2` = 유저 정보)
2. **포트 탐색:** 임의로 3000이나 5173으로 접속하지 말 것. `vite.config.ts`, `next.config.js` 등 설정 파일을 확인하거나 터미널 명령어를 통해 현재 활성화된 로컬 서버 포트를 확인할 것. (예: `lsof -i -P -n | grep LISTEN`). dev 서버가 꺼져있다면 실행할 것.
3. **인증 정보 획득:** 로그인이 필요한 경우 `.env.local` 이나 `.env.development`를 읽어 테스트 계정 정보를 찾을 것.
4. **Fallback:** 위 방법으로 도저히 찾을 수 없다면, 무작정 진행하여 실패하지 말고 **"현재 dev 서버 포트 번호와 테스트 계정 정보를 알려주세요"라고 사용자에게 먼저 질문할 것.**

## Workflow — 시각 검증

1. `mcp__playwright__browser_resize` (모바일 프로젝트면 360×800)
2. `browser_navigate` — [Step 0]에서 찾은 라우트로 이동 (필요 시 sessionStorage/localStorage 세팅). **이동 후 네트워크 유휴 상태(networkidle)나 핵심 DOM 요소가 렌더링될 때까지 대기할 것.**
3. **변경 영역 스크롤** (`scrollIntoView`) — 검증 대상이 폴드 아래라면 먼저 화면 위로. 사용자 가시성 섹션 참조.
4. `browser_take_screenshot` — 1장, 화면 깨짐 sanity check
5. **미세 수치 의심 시**: `browser_evaluate`로 `getComputedStyle` / `getBoundingClientRect` 일괄 추출 → Figma spec(또는 의도한 값)과 diff
6. 차이 발견 → 코드 수정 → 재측정. diff 0 될 때까지 2~3회 자동 반복 (사용자 안 깨움)

## Workflow — 동작 검증

1. `browser_navigate` — [Step 0]에서 획득한 포트 및 인증 정보 활용. **렌더링 완료 대기 필수.** (모바일이면 `browser_resize` 360×800)
2. **변경 영역 스크롤** (`scrollIntoView`) — 클릭 대상이 폴드 아래라면 먼저 화면 위로. 사용자 가시성 섹션 참조.
3. `browser_click` / `browser_type` / `browser_fill_form` — 핵심 동작 시뮬
4. `browser_evaluate` — 결과 단언 (URL 변경, DOM 요소 존재/부재, storage 변화)
5. `browser_console_messages` — 에러 0건 확인
6. `browser_network_requests` — 기대 API 호출 확인 (필요 시)

**깊이:** 해피 패스 1번 + 명백한 엣지(에러/빈 상태) 1~2개. 그 이상은 e2e 스펙 영역.

## 사용자 가시성 (Visibility for the User)

사용자가 **같은 dev 브라우저를 옆에서 보고 있다**는 가정으로 검증할 것. 코드는 동작해도 화면이 그대로면 사용자에겐 "검증 안 한 것"으로 보임.

**규칙:** `browser_navigate` / `browser_click` 직전에 검증 대상 요소를 화면에 띄울 것.

```js
// 클릭/검증 직전, 대상 요소가 폴드 아래일 가능성 있으면 무조건
browser_evaluate({
  function: `() => {
    const el = document.querySelector('[data-testid=...]') 
      ?? [...document.querySelectorAll('span')].find(s => s.textContent === 'Logged');
    el?.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }`
})
// 약간의 wait로 사용자가 시각적으로 따라잡을 시간 확보 (300~500ms)
```

**언제 무조건 스크롤하나:**
- 카드/섹션이 페이지 중간~하단에 위치
- 클릭 후 새로 노출되는 요소가 폴드 밖일 때 (확장 카드, 더보기, 무한스크롤)
- 단순 DOM 쿼리로 끝내는 경우에도 — 사용자 시야에 변화가 있어야 검증으로 인식됨

**예외:** 첫 화면 위쪽 헤더/CTA 등 폴드 안 명백한 요소.

## Quick Reference

| 상황 | 도구 | 비고 |
|---|---|---|
| 화면 깨짐 sanity | `browser_take_screenshot` | 1장으로 충분 |
| 정확한 수치 검증 | `browser_evaluate` + `getComputedStyle` | 스크린샷보다 10~100배 빠름, 토큰도 거의 안 듦 |
| 클릭/타이핑 시뮬 | `browser_click` / `browser_type` / `browser_fill_form` | |
| 결과 단언 | `browser_evaluate` (URL, DOM, storage) | |
| 콘솔 에러 체크 | `browser_console_messages` | 항상 0건 확인 |
| API 호출 확인 | `browser_network_requests` | 필요 시만 |

## 웹뷰 전환 조건

사용자 메시지에 **"웹뷰", "기기", "ADB", "앱 연결", "Android", "실기기"** 단어가 **직접 등장**할 때만 `webview-test` MCP로 전환. 추측/자동 전환 금지. ADB 연결 명령도 그 트리거 단어 없으면 자동 실행하지 않는다.

## Common Mistakes

| 실수 | 발생 패턴 | 방지 |
|---|---|---|
| 코드만 보고 "다 됐어요" 보고 | UI/플로우 수정했는데 검증 생략 | 행동 변경 있으면 워크플로 1단계부터 무조건 |
| 스크린샷만 보고 OK | 미세 수치 차이를 놓침 | 의심 가는 부분은 `browser_evaluate`로 computed style 추출해 diff |
| 자동으로 ADB/웹뷰 전환 | 웹 작업만 지시받았는데 웹뷰로 점프 | 트리거 단어 없으면 Playwright만 |
| 타입체크 = 검증으로 착각 | "lint/타입 통과했으니 OK" | 타입체크는 코드 정합성, **행동 정합성은 Playwright로만** |
| dev 서버 죽은 채로 보고 | navigate 실패했는데 코드 수정만 반복 | navigate 실패 시 dev 서버 상태부터 확인 (Step 0) |

## Red Flags — STOP and verify

아래 생각이 들면 멈추고 워크플로 실행:

- "코드만 봐도 분명히 동작할 것"
- "타입체크/유닛 테스트 통과했으니 OK"
- "computed style 수치 맞으니 시각 검증 생략"
- "비슷한 변경 전에도 했으니 이번은 안 봐도 됨"
- "CSS만 살짝 바꾼 거라"
- "검증하면 토큰 많이 들 것 같아서"

전부: **dev 서버 띄우고 Playwright로 1번이라도 확인** 후 보고.