---
name: webview-test-mcp
description: Use when working with webview-test MCP on Android — message says "앱 연결"/"웹뷰 연결", MULTIPLE_WEBVIEWS error appears, ADB device disconnected, or SPA route change (Next.js) is not re-rendering after webview_flow goto.
---

# Webview-test MCP (개인 환경)

## Overview

webview-test MCP 서버 자체 instructions(체이닝/디바이스 선택 절차/에러 진단)는 자동 로드된다. 이 스킬은 그 위에 얹는 **개인 환경 디폴트**와 **검증된 트릭**만 담는다.

**핵심:** Wi-Fi 디바이스 디폴트(IP는 매번 동적 조회), `webview_connect`는 항상 `socketIndex: 0`, Next.js SPA 라우트 변경은 `location.href` 강제.

## When to Use

- 메시지에 "앱 연결" / "웹뷰 연결" 등장 → ADB 연결 절차 실행
- webview-test MCP 첫 호출 직전 (connect 전 룰 확인)
- `MULTIPLE_WEBVIEWS` 에러 본 직후
- `webview_flow` goto 후 화면이 그대로 / waitFor timeout (Next.js)
- 디바이스 여러 대인데 어느 걸 쓸지 모호할 때

## ADB 연결 절차 ("앱 연결" / "웹뷰 연결")

**IP는 절대 하드코딩하지 말 것.** 디바이스 IP는 DHCP라 매번 바뀐다. 항상 `adb shell`로 실제 IP 조회 후 연결.

메시지에 위 표현이 등장하면 **확인 없이 끝까지** 실행:

```bash
# 1. 현재 붙어있는 디바이스 확인
adb devices

# 2-A. 이미 <IP>:5555 형태가 device로 보이면 — 이미 Wi-Fi 연결됨, 끝.

# 2-B. USB 시리얼만 보이면 — 디바이스 IP 조회 후 Wi-Fi 전환:
SERIAL=$(adb devices | awk 'NR>1 && $2=="device" && $1 !~ /:/ {print $1; exit}')
IP=$(adb -s $SERIAL shell ip -f inet addr show wlan0 | grep -oE 'inet [0-9.]+' | awk '{print $2}')
adb -s $SERIAL tcpip 5555 && sleep 2 && adb connect $IP:5555
adb devices  # <IP>:5555 device 확인

# 2-C. 아무것도 없으면 — 그때만 USB 연결 요청
```

**한 번 실패한 IP는 다시 시도하지 말 것.** 이전 세션 IP가 메모/머릿속에 있어도 timeout이면 즉시 `adb shell ip addr` 조회로 갱신.

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

## Speed Modes — 기본은 빠른 모드, 정밀은 명시 옵트인

### 기본 모드 (디폴트)

"X 동작하는지 봐줘" 톤 요청은 **얇게**:

1. 한 `webview_evaluate` (또는 `webview_flow`) 안에 클릭/대기/검증 체이닝. 단계마다 별도 콜 금지.
2. 검증은 "동작하는지" 수준만 — overlay/요소 존재 여부 + 핵심 1-2개 필드. 픽셀 정밀 geometry / `getBoundingClientRect` / computed style 디테일 생략.
3. **fixture/handler 사전 정독 금지** — e2e spec, `data-task-id` 같은 단서로 충분하면 핸들러 수백 줄 통째 `Read` 금지. `webview_evaluate`로 DOM/state 직접 묻는 게 빠름.
4. Task 분할 자제 — 시나리오 단위 1-2개. 클릭 하나당 task 쪼개지 말 것.
5. `webview_screenshot` 디폴트 생략 — computed style / 존재 여부로 끝나면 안 찍음.

### 정밀 모드 (명시 옵트인)

사용자 메시지에 다음 신호가 있을 때만 깊이:

- **"세세하게" / "꼼꼼하게" / "정밀하게" / "픽셀 단위" / "위치 정확한지"**
- **"스크린샷 보여줘" / "시각적으로 확인"**
- 회귀 테스트 / QA / 릴리즈 검증 맥락 명시

이 경우에만 `getBoundingClientRect`, `webview_screenshot`, e2e spec 수준 geometry 추가.

### 시간 비용 (왜 디폴트가 얇은지)

| 행위 | CDP 비용 |
|---|---|
| `webview_evaluate` 1콜 | 50-200ms |
| `webview_screenshot` 1콜 | **4-5초** (CDP timeout 누적) |
| `goto` 후 `sleep 2500ms` | 2500ms 고정 |
| `waitFor` selector | 실제 필요 시간만 (200-400ms 평균) |

→ 디폴트 검증에서 screenshot · 큰 sleep은 누적 지연의 주범. 명시 신호 없으면 사용 금지.

## Common Mistakes

| 증상 | 원인 | 고침 |
|---|---|---|
| `adb connect <IP>` 반복 timeout | stale IP 하드코딩 / 캐시 | `adb shell ip addr show wlan0`로 실제 IP 먼저 |
| `MULTIPLE_WEBVIEWS` 에러 → 재호출 왕복 | `webview_connect` 인자 누락 | `{ socketIndex: 0 }` 명시 |
| `goto` 후 화면 그대로 / waitFor timeout | Next.js router가 pushState 못 받음 | `evaluate: location.href = ...` |
| "USB 연결해주세요"부터 묻고 끝 | `adb devices` 먼저 안 봄 | 항상 `adb devices`부터 |
| 검증이 느림 ("왜 이렇게 오래걸려") | screenshot/fixture Read/큰 sleep 디폴트 사용 | Speed Modes 디폴트 — screenshot·정독·sleep 생략, 한 evaluate에 체이닝 |
| `goto` 직후 `sleep 2500ms` 같은 큰 wait | 최악 케이스 기준 고정 sleep | `waitFor: { selector: ... }`로 실제 필요 시간만 |

## Quick Reference

```bash
# 디바이스 IP 조회 (DHCP라 매번 바뀜 — 절대 하드코딩 금지)
adb -s <시리얼> shell ip -f inet addr show wlan0 | grep -oE 'inet [0-9.]+' | awk '{print $2}'

# Wi-Fi 전환 + 연결
adb -s <시리얼> tcpip 5555 && sleep 2 && adb connect <IP>:5555
adb devices  # <IP>:5555 device 확인
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
