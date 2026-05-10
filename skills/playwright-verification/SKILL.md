---
name: playwright-verification
description: Use strictly for verifying functional behavior, interactive user flows (clicks, forms, modals), layout responsiveness (overflows), and catching console/network errors on the dev server. DO NOT use for visual design/pixel-perfect diffing against Figma.
---

# Playwright Verification

## Overview

UI/플로우의 **동적 인터랙션 및 시스템 안정성**을 확인하기 위한 스킬. 
Playwright MCP는 디자인 시안과 "똑같이 생겼는지(Visual Diff)"를 검증하는 도구가 아니다. 폼 제출, 버튼 클릭, 반응형 환경(모바일 뷰포트)에서의 DOM 깨짐 현상, 자바스크립트 콘솔 에러 등 "제대로 동작하는지"를 시뮬레이션할 때만 사용한다.

## When to Use

**동작 검증 (Interaction & Flow)**
- 새 플로우/route/dialog 추가 및 동작 확인
- 기존 플로우 수정 (auth, API fetch 연동, 상태 전환)
- 데이터 흐름 변경 (폼 제출, 클릭 후 URL 라우팅 검증)

**구조/반응형 안정성 (Responsive & Error Catching)**
- 모바일 뷰포트(375px)에서 가로 스크롤(Overflow)이 발생하거나 레이아웃이 터지는지 확인
- 브라우저 콘솔 에러(Console messages) 0건 확인
- 런타임 레이스 컨디션 및 조건부 렌더링 검증

## When NOT to Use

- **시각적 디자인 검증 (Visual/Pixel-perfect matching):** 패딩, 폰트 크기, 색상 등이 Figma와 일치하는지 `computedStyle`로 추출해서 대조하는 행위 (절대 금지. 이 역할은 Storybook과 PerfectPixel의 몫이다)
- 순수 리팩터 (행동 변경 없음) / 타입만 수정

## Step 0: 환경 설정 (Environment Setup)
검증 전 타겟 URL(포트 번호) 확인. 임의로 3000이나 5173 접속 금지. `vite.config.ts`, `next.config.js` 또는 `lsof` 명령어로 현재 활성화된 포트 탐색. Auth 정보 필요시 `.env.local` 참조. 도저히 찾을 수 없다면 사용자에게 포트 정보를 요구할 것.

## Workflow — 동작 및 안정성 검증

1. `browser_navigate` — [Step 0]에서 찾은 라우트로 이동 후 렌더링 대기.
2. `browser_resize` — 모바일 레이아웃 검증이 필요하다면 360×800 등으로 변경.
3. **변경 영역 스크롤 (`scrollIntoView`)** — 클릭 및 검증 대상이 폴드 아래라면 화면 위로 띄움 (사용자 시각적 확인 동기화).
4. `browser_click` / `browser_type` / `browser_fill_form` — 핵심 동작 시뮬레이션.
5. **결과 단언 (`browser_evaluate`)** — URL이 정상적으로 바뀌었는지, 의도한 DOM 요소(모달 등)가 나타났는지, Overflow로 인해 가로축이 터지지 않았는지 확인. (CSS 수치 검증 금지)
6. **무결성 체크** — `browser_console_messages`를 확인하여 런타임 에러나 React Warning이 0건인지 체크. `browser_network_requests`로 API 호출 정상 여부 확인.

## Common Mistakes

| 실수 | 발생 패턴 | 방지 |
|---|---|---|
| CSS 속성 비교 (Visual Diff) | `computedStyle`을 뽑아 패딩/색상을 Figma와 일치하는지 비교 | AI는 시각 검증에 취약함. 동작(기능)과 에러 검증에만 집중할 것 |
| 화면 깨짐 방치 | 데스크톱 뷰만 확인 | 필요시 반드시 뷰포트를 줄여 반응형 깨짐/Overflow 여부를 확인할 것 |
| 사용자 가시성 무시 | 스크롤 안 하고 백그라운드에서만 클릭 처리 | 검증 대상 요소를 `scrollIntoView`로 띄워 사용자가 볼 수 있게 할 것 |