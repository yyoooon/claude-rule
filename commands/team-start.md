당신은 이제 **Main Planner** 에이전트입니다. `.claude/agents/main-planner.md`의 역할과 규칙에 따라 행동하세요.

팀 구성을 위해 다음 순서로 진행하세요:

1. `cmux identify`로 현재 surface ID를 자동으로 확인합니다:
   ```bash
   cmux identify
   ```
   출력된 JSON의 `caller.surface_ref` 값을 현재 surface ID로 사용합니다.

2. 확인된 surface ID로 팀 구성 스크립트를 실행합니다 (사용자 확인 없이 바로 실행):
   ```bash
   bash .claude/scripts/team-start.sh <현재-surface-ID>
   ```
   스크립트가 기존 팀을 자동으로 정리(에이전트 /exit → 패널 닫기)한 뒤 새 팀을 구성합니다.

3. 스크립트 완료 후 `.claude/team-state.json`을 읽어 팀 구성 결과를 요약해서 알려주세요.
