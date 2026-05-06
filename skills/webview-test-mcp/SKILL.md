---
name: webview-test-mcp
description: Use when working with webview-test MCP on Android — message says "앱 연결"/"웹뷰 연결", MULTIPLE_WEBVIEWS error appears, ADB device disconnected, or SPA route change (Next.js) is not re-rendering after webview_flow goto.
disable-model-invocation: true
---

# Webview-test MCP (개인 환경)

## Overview

webview-test MCP 서버 자체 instructions(체이닝/디바이스 선택 절차/에러 진단)는 자동 로드된다. 이 스킬은 그 위에 얹는 **개인 환경 디폴트**와 **검증된 트릭**만 담는다.

**핵심:** Wi-Fi 디바이스(192.168.100.212:5555) 디폴트, `webview_connect`는 항상 `socketIndex: 0`, Next.js SPA 라우트 변경은 `location.href` 강제.

## When to Use

- 메시지에 "앱 연결" / "웹뷰 연결" 등장 → ADB 단축 절차 실행
- webview-test MCP 첫 호출 직전 (connect 전 룰 확인)
- `MULTIPLE_WEBVIEWS` 에러 본 직후
- `webview_flow` goto 후 화면이 그대로 / waitFor timeout (Next.js)
- 디바이스 여러 대인데 어느 걸 쓸지 모호할 때

## ADB 연결 단축 ("앱 연결" / "웹뷰 연결")

메시지에 위 표현이 등장하면 **확인 없이 끝까지** 실행:

1. `adb connect 192.168.100.212:5555` 시도
2. 실패 시 `adb devices`로 USB 시리얼 확인
3. USB 기기 있으면 `adb -s <시리얼> tcpip 5555 && sleep 2 && adb connect 192.168.100.212:5555`
4. `adb devices`로 `192.168.100.212:5555  device` 확인 후 결과 보고

USB조차 안 보이면 **그때만** 사용자에게 USB 연결 요청.

## 기본 디바이스 = Wi-Fi (192.168.100.212:5555)

여러 대 붙어있어도 Wi-Fi 디바이스가 있으면 **질문 없이** 사용. Wi-Fi 끊겨 있으면 위 단축 절차부터.

## webview_connect 호출 — 첫 콜부터 `socketIndex: 0`

```
webview_connect({ socketIndex: 0 })
```

**Why:** 인자 없이 호출하면 socket 여러 개일 때 `MULTIPLE_WEBVIEWS` 에러로 재호출 → 왕복 1회 추가. MCP 서버도 multiple 시 index 0 auto-pick으로 패치되어 있지만 클라이언트에서 명시하면 둘 다 안전망.

## SPA 라우트 변경 — `location.href` 강제 (Next.js 함정)

`webview_flow`의 `goto`는 내부적으로 pushState. Next.js App Router는 pushState를 자체 라우팅 신호로 안 받아 페이지가 리렌더 안 된다. → "HMR 빌드 대기?" 오인하기 쉬움.

**Next.js / React SPA 내부 라우트 변경은 hard navigation:**

```
webview_flow({
  steps: [
    { evaluate: { expression: "location.href = '/care-plan'" } },
    { waitFor: { selector: '[data-testid=care-plan-root]' } },
    { capture: { url: true } }
  ]
})
```

**Why:** `location.href`는 풀 리로드 → Next.js router 정상 작동, 1초 안에 끝남.

| 상황 | 무엇 사용 |
|---|---|
| Next.js / React SPA 내부 라우트 | `evaluate: location.href = ...` |
| 정적 HTML / 앱 외부 URL / 첫 진입 | `goto` OK |

## Common Mistakes

| 증상 | 원인 | 고침 |
|---|---|---|
| `MULTIPLE_WEBVIEWS` 에러 → 재호출 왕복 | `webview_connect` 인자 누락 | `{ socketIndex: 0 }` 명시 |
| `goto` 후 화면 그대로 / waitFor timeout | Next.js router가 pushState 못 받음 | `evaluate: location.href = ...` |
| "USB 연결해주세요"부터 묻고 끝 | Wi-Fi 단축 시도 누락 | `adb connect 192.168.100.212:5555` 먼저 |
| "어느 디바이스 쓸까요?" 질문 | Wi-Fi 디폴트 룰 미적용 | 192.168.100.212:5555 우선 |

## Quick Reference

```bash
# 연결 시퀀스
adb connect 192.168.100.212:5555
# 실패 시
adb devices                                      # USB 시리얼 확인
adb -s <시리얼> tcpip 5555 && sleep 2 && adb connect 192.168.100.212:5555
adb devices                                      # 192.168.100.212:5555 device 확인
```

```js
// Webview 연결 — 첫 콜부터 명시
webview_connect({ socketIndex: 0 })

// SPA 라우트 변경
webview_flow({
  steps: [
    { evaluate: { expression: "location.href = '/route'" } },
    { waitFor: { selector: '[data-testid=...]' } }
  ]
})
```
