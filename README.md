# windows-beautiful-par-term

[par-term](https://github.com/paulrobello/par-term) (Rust + wgpu 터미널) 을 Windows에서 보기 좋게
꾸미고, 사용 중 발견한 버그를 고친 **로컬 포크**입니다.

- **테마**: Kanagawa Wave (바이너리에 내장 — 설정에서 `theme: kanagawa-wave`만 지정하면 됨)
- **배경**: `tilted-spiral.glsl` 커스텀 셰이더 (기울어진 나선은하, 픽셀아트 스타일)
- **크롬**: 알약(pill) 탭 · 활성 탭 하단 인디케이터 · 탭바 반투명 · macOS 스타일 캡션 버튼 ·
  DWM 둥근 모서리 + 1px 테두리 · 탭바 빈 영역으로 창 드래그
- **수정**: pi 입력이 안 되던 문제, 창을 최소화하면 죽던 패닉, kitty 키보드 프로토콜,
  한글(IME) 입력, `--command-to-send`가 제출되지 않던 문제

원본은 MIT 라이선스이며 `source/LICENSE`에 그대로 유지되어 있습니다.

---

## 1. 빠른 설치 (권장 — 빌드 불필요)

### 1-1. 파일 3개를 제자리에 둡니다

| 이 저장소의 파일 | 복사할 위치 |
| --- | --- |
| `release/par-term.exe` | `%USERPROFILE%\par-term\par-term.exe` |
| `config/config.yaml` | `%APPDATA%\par-term\config.yaml` |
| `config/shaders/tilted-spiral.glsl` | `%APPDATA%\par-term\shaders\tilted-spiral.glsl` |

`%USERPROFILE%`은 보통 `C:\Users\<이름>`, `%APPDATA%`는 보통
`C:\Users\<이름>\AppData\Roaming` 입니다. 폴더가 없으면 만드세요.

### 1-2. 폰트 설치

이 설정은 **Maple Mono NF KR** 을 씁니다. 없으면 폰트 폴백이 일어나 글자가 밋밋해집니다.
[Nerd Fonts 릴리스](https://github.com/ryanoasis/nerd-fonts/releases) 등에서 받아 설치하거나,
`config/config.yaml`의 `font_family*` 값을 이미 가진 폰트로 바꾸세요.

### 1-3. 실행

```powershell
& "$env:USERPROFILE\par-term\par-term.exe"
```

---

## 2. 자동 설치 (install.ps1)

위 1-1을 대신 해줍니다. 기존 파일은 덮어쓰기 전에 `.bak-<타임스탬프>`로 백업합니다.

```powershell
# 이 저장소 폴더에서
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -WhatIf   # 미리 확인
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1          # 실제 설치
```

설정을 건드리지 않고 실행파일만 바꾸려면 `-SkipConfig`를 쓰세요.

---

## 3. 소스에서 직접 빌드

`source/` 는 이 포크의 **전체 작업 트리**입니다 (빌드 산출물 `target/`과 git 이력 제외).

```powershell
# Rust 1.98+ (edition 2024) 필요
cd source
cargo build --release
# 결과: source\target\release\par-term.exe
```

- 증분 빌드 약 **1분 20초** (thin LTO, 32코어 기준). 이전의 fat LTO+`codegen-units=1`
  설정은 5분 40초가 걸려서 `release-fat` 프로파일로 옮겨 보존했습니다.
- 릴리스용 최소/최속 바이너리가 필요하면 `cargo build --profile release-fat`.
- **기존 배포본과 프레임 타이밍을 비교할 때는 `release-fat`을 쓰세요.** 최적화 설정이 다르면
  비교가 무의미해집니다.

`patches/` 에는 upstream v0.45.0 위에 올린 커밋 5개가 patch 파일로 들어 있습니다
(`git am patches/*.patch`). 소스 트리를 통째로 받았다면 필요 없습니다.

---

## 4. 원본과 다른 점

### 새로 넣은 기능

| 항목 | 내용 |
| --- | --- |
| 테마 | Kanagawa Wave 내장 (`par-term-config/src/themes.rs`) |
| 탭바 | 반투명(`tab_bar_bg_alpha`), 알약 탭, 활성 탭 하단 인디케이터, 탭 글자 굵게, 탭 폭 유동 + **탭 하나가 탭바 폭의 절반을 넘지 않는 상한** |
| 창 | DWM 둥근 모서리 + 1px 테두리, **탭바 빈 영역 드래그로 창 이동**, 가장자리 6px 리사이즈 밴드 |
| 창 버튼 | 우상단 macOS 스타일 3원 캡션 버튼 (`window_decorations: false`일 때) |
| 키보드 | **kitty 키보드 프로토콜 인코더** (`input.kitty_keyboard`, 기본 true) |
| 입력 | **한글/일본어/중국어 IME 조합** 처리 + 조합 중 글자 인라인 표시 |

### 고친 버그

| 증상 | 원인 | 조치 |
| --- | --- | --- |
| pi를 띄우면 입력이 화면에 반영되지 않음 | 코어가 DEC 2026(synchronized output) 종료 마커를 수신 버퍼의 **마지막 32바이트**에서만 찾았는데, ConPTY는 마커 **뒤에** 내용을 붙여 보내 마커가 밀려나갔다 → 버퍼가 영원히 flush되지 않음 | 코어를 `vendor/`로 떠서 검색 범위를 "이번 청크 + 8바이트 오버랩"으로 수정 |
| **창을 최소화하면 패닉으로 종료** (원본 0.45.0도 동일) | 스크롤바 썸 높이를 20px 최소값으로 올리는데 최소화 시 트랙이 1px이 되어 이동 범위가 `1-20 = -19` → `clamp(0, -19)` | 썸을 트랙 높이로 제한 + 트랙이 너무 작으면 숨김 + 최소화 중 프레임 생성 차단 |
| 최소화→복원 시 자식에게 **1행(1-row) 그리드**가 전달됨 | 최소화된 창은 아이콘 크기(192×34 → 13×1)를 보고하고, 복원 시 "진짜 크기" 이벤트보다 몇 ms 먼저 프레임이 재개되어 낡은 그리드가 "2프레임 연속 동일"로 판정됨 | 최소화~실제 resize 이벤트까지 그리드를 불신하고 자식을 마지막 정상 크기에 붙잡아 둠 (매 프레임 도는 두 경로 모두) |
| `--command-to-send` 명령이 입력만 되고 제출되지 않음 | Windows ConPTY는 Enter를 CR로 받는데 LF를 보냄 | Windows에서 CR 전송 |
| 한글이 아예 입력되지 않음 | IME를 켜두고(`set_ime_allowed(true)`) `WindowEvent::Ime`를 처리하는 코드가 없어 조합 결과가 버려짐. par-term은 문자를 물리 키에서 만들기 때문에 다른 경로도 없음 | `Ime::Commit` → PTY 전달, `Ime::Preedit` → 커서 위치 인라인 표시, `set_ime_cursor_area`로 후보창 위치 갱신 |

---

### 배경 셰이더 (`config/shaders/tilted-spiral.glsl`)

Kanagawa Wave 테마 위에 나선은하를 그리는 커스텀 셰이더입니다. 현재 **v3.6.0**
("Continuum – Pearl Spiral").

- **은하핵**: 중심에 2px 픽셀 별 하나가 고정되어 있고(설정에서 크기 조절), 그 주변은
  spheroid 프레임으로 측정한 부피감 있는 코어입니다.
- **별**: 원판 별은 3px 격자(5×5 탐색), 하늘 별은 3개 레이어(23 / 47 / 16px). 전부 **각진 픽셀
  사각형**이라 안티앨리어싱이 없습니다.
- **반짝임**: 모든 별에 적용되며, 별마다 **주기(1.2~3.9초) · 진폭(40~80%) · 위상이 독립**입니다
  (인접 별 상관계수 -0.004).
- **조절**: 설정 UI에 슬라이더 **22개**가 노출됩니다 — `Galaxy Scale`, `Star Density`,
  `Sky Star Density`, `Star Cell (px)`, `Twinkle`, `Nucleus Star (px)`, `Core Gain` 등.
  `Twinkle`은 반짝임 전체 진폭의 **마스터 배율**이라 과하면 0.5 정도로 낮추면 됩니다.
- **성능**: 4K에서 **0.407ms/프레임** (60fps 예산의 **2.4%**).

셰이더를 고쳐 쓰려면 `%APPDATA%\par-term\shaders\tilted-spiral.glsl` 을 직접 수정하고
par-term에서 새 창을 열면 됩니다(파일 변경을 자동 감지합니다). 문법 확인은:

```powershell
& "$env:USERPROFILE\par-term\par-term.exe" shader-lint "$env:APPDATA\par-term\shaders\tilted-spiral.glsl"
```

`tools/` 의 `shader_shot.ps1`(실제 창 캡처), `shader_series.ps1`(반짝임 시계열),
`render_check.py`(4K GPU 시간)로 육안·수치 검증을 할 수 있습니다.

---

## 5. 검증 상태 (정직한 기록)

| 항목 | 상태 | 근거 |
| --- | --- | --- |
| pi 입력 반영 | ✅ 검증 | 입력창에 타이핑이 표시되는 스크린샷, 자식 stdin 바이트 수신 확인 |
| 최소화 → 복원 생존 | ✅ 검증 | 최소화 4초 후에도 프로세스 생존, 복원 후 정상 |
| 1행 그리드 미전달 | ✅ 검증 | 자식이 보고한 크기 이력이 `79x24 ↔ 80x24`뿐, `rows<=1` 이벤트 0건 |
| 회귀 테스트 | ✅ 통과 | `par-term-input` 26 · `par-term-terminal` 19 · `par-term-render` 98, 실패 0 |
| **한글 IME** | ✅ **검증 (실제 IME로 확인)** | 조합이 정상 동작합니다. 터미널이 받은 값이 완성형 음절입니다: `commit "호" (0xD638)`, `commit "안" (0xC548)`, `commit "녕" (0xB155)`. 조합을 거쳐 확정된 음절이 그대로 전달되는 것을 로그로 확인 — `U+AC00~U+D7A3` 영역 |
| clippy CI 게이트 | ✅ 통과 | `cargo clippy --all-targets --all-features -- -D warnings` 기준. `clippy::doc_lazy_continuation` 1건과 Windows에서만 나오던 upstream `dead_code` 1건을 수정 |
| 배경 셰이더 | ✅ 검증 | 4K 0.407ms/프레임, 빈 배경 순검정(0.0), 반짝임 주기·진폭을 코드 이식과 시계열 캡처 양쪽으로 확인 |

한글 입력이 여전히 안 되면 `%TEMP%\par_term_debug.log`에서 `IME:` 로 시작하는 줄을 보세요.
`--log-level info`로 실행하면 됩니다:

```powershell
& "$env:USERPROFILE\par-term\par-term.exe" --log-level info
```

- `IME: commit "안" (3 bytes)` 처럼 **완성형 음절**(U+AC00~U+D7A3)이 보이면 정상입니다.
- `IME: commit "ㅎ"` 처럼 **호환 자모**(U+3131~U+318E)만 보인다면, 그 순간 초성만 치고 있었을 가능성이 큽니다.
  자음만 이어서 치면(예: ㅎㅇㅎㅇ) 조합할 모음이 없어 자음마다 확정되는 것이 **정상 동작**입니다.
- 그 줄조차 없으면 IME 이벤트가 창에 도달하지 않은 것입니다 (Windows IME/포커스 문제).

---

## 6. 문제 해결

| 증상 | 확인할 것 |
| --- | --- |
| 실행 직후 종료 | 콘솔에서 직접 실행해 오류를 보세요. `--log-level info`, 로그는 `%TEMP%\par_term_debug.log` |
| 배경이 안 보임 | `%APPDATA%\par-term\shaders\tilted-spiral.glsl` 존재 여부, `config.yaml`의 `custom_shader_enabled: true` |
| 이미지가 이상함 | `theme.background`는 ANSI black(`9,6,24`)과 같아야 합니다. 다르면 셀마다 불투명 쿼드가 그려져 배경 셰이더를 덮습니다 |
| 글꼴이 밋밋함 | Maple Mono NF KR 설치 여부 |
| 창이 안 움직임 | 탭바의 **빈 영역**을 잡아야 합니다(탭 위가 아님). 최대화 상태에서는 비활성 |
| 설정이 적용 안 됨 | 설정 파일은 `%APPDATA%\par-term\config.yaml` 하나뿐입니다. 실행 중에도 일부 항목은 자동 반영됩니다 |

### 되돌리기

`release/par-term-official-0.45.0.exe` 가 **원본 upstream 0.45.0 바이너리**입니다.
그것을 `par-term.exe` 자리에 덮어쓰면 원래대로 돌아갑니다.

---

## 7. 저장소 구성

```text
release/       패치된 실행파일 + 원본 0.45.0 백업
config/        config.yaml + 커스텀 셰이더
source/        전체 소스 트리 (빌드 산출물·git 이력 제외)
patches/       upstream 위에 올린 커밋 5개 (git am 용)
tools/         개발/검증 스크립트 (창 캡처, 입력 프로브, 셰이더 성능 측정 등)
docs/          작업 기록: 미해결 문제 핸드오프, 브리핑, 셰이더 개선 이력
galaxy-work/   셰이더 제작 작업장 (shaders/ 작업본, work/ 스크립트, outputs/ 렌더 결과)
```

`docs/OPEN-ISSUES-HANDOFF.md` 가 이 작업 전체의 기록입니다 — 무엇을 확인했고 무엇이
아직 가설인지 구분해서 적어 두었습니다.

## 8. 출처

- 원본: [paulrobello/par-term](https://github.com/paulrobello/par-term) — MIT License, Copyright (c) 2026 Paul Robello
- 이 저장소는 그 포크이며 `source/LICENSE`에 원 라이선스를 유지합니다.
