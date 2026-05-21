---
name: agent-browser
description: MANDATORY before ANY agent-browser CLI call when the user explicitly names agent-browser/9223 — even single-shot fetches, screenshots, or network checks. Trigger words — "agent-browser로", "agent-browser 써서", "브라우저 에이전트로/써서", "9223 크롬으로", "9223으로 확인", "띄워진 크롬으로 …", "기존 크롬에 붙어서". Also use for multi-step browser automation (5+ click/wait) without explicit trigger. Skip for: Playwright MCP, webview-test MCP (Android WebView). When user did NOT mention agent-browser/9223 AND task is single screenshot/click, raw CLI is OK.
---

# agent-browser

CLI 사용법 전체 레퍼런스는 **`browser-verifier` 스킬의 `cli.md`** 참고.

> `browser-verifier` 스킬 로드 후 `cli.md` 내용 기준으로 도구를 선택한다.

## 핵심 원칙 (요약)

- `--cdp 9223 + tab tN` 탭 명시 필수
- Navigation-aware primitive 우선: `find` → `batch` → `wait` → `pushstate` → IIFE
- 페이지 전환은 IIFE 밖, `batch + wait --url`로
- React input은 `fillReactInput()` 또는 setter+dispatchEvent
- viewport 변경 금지
- 픽셀 단위 일치 판정 안 함
