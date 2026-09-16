# par-term 로컬 포크 — 문제 해결 기록 (구 OPEN-ISSUES-HANDOFF)

작성: 2026-09-12 / 개정: 2026-09-13 (P1~P3 해결 반영)
이 문서는 **검증된 사실과 미검증 가설을 구분**해서 적는다. 재현 명령과 근거를 포함한다.

> **개정 요약**: 원래 이 문서는 "P1 pi 입력 미해결, P2 최소화 패닉 원인 미상(upstream 추정),
> P3 아이콘 no-op" 상태의 인계용이었다. 이후 조사에서 **P1과 P2의 원인이 모두 잘못 추정된
> 상태였음이 밝혀졌고**(kitty 프로토콜 아님 / egui 아님), 실제 원인을 찾아 수정·검증했다.
> 아래는 그 결과다. 원래의 잘못된 가설은 §5 "기각된 가설"에 남겨둔다.

---

## 1. 환경 · 빌드 · 검증 (먼저 읽을 것)

| 항목 | 값 |
| --- | --- |
| 소스 | `C:\Users\jky72\par-term\build\par-term` (cargo workspace, Rust) |
| 실행 파일 | `C:\Users\jky72\par-term\par-term.exe` |
| 원본 백업 | `par-term-official-0.45.0.exe` (upstream 0.45.0) |
| 직전 패치본 백업 | `par-term-prev-*.exe` (교체 전 해시) |
| 설정 | `%APPDATA%\par-term\config.yaml` |
| 디버그 로그 | `%TEMP%\par_term_debug.log` |
| 빌드 | 워크스페이스에서 `cargo build --release` (thin LTO — 아래 "빌드 속도" 참고), 스크립트 `galaxy-work\work\rebuild_patched.ps1` |

### 빌드 속도 (2026-09-13 변경)

원래 `[profile.release]`는 `lto = true` + `codegen-units = 1`이었고, 이것이 **가능한 조합 중
가장 느린 설정**이었다: 크레이트당 codegen unit이 1개라 rustc가 코어를 1개만 쓰고, 그 위에
fat LTO의 직렬 전역 패스가 붙는다. 32코어 머신에서 살아 있는 rustc가 **2개뿐**이었고,
`src/` 한 줄 수정에 **5분 40초**가 걸렸다.

변경 후:

| 프로파일 | 설정 | 용도 |
| --- | --- | --- |
| `release` (기본) | `lto = "thin"`, `codegen-units = 16`, `opt-level = 3` | 일상 반복 빌드 |
| `release-fat` | `lto = true`, `codegen-units = 1` (예전 그대로) | 릴리스 컷 / 기존 프레임 타이밍과 비교할 때 |
| `dev-release` | `opt-level = 2`, `lto = false`, `incremental = true` | 가장 빠른 반복 |

Thin LTO는 fat LTO와 수 퍼센트 이내이면서 두 단계 모두 병렬화한다. 핸드오프 문서에 기록된
프레임 타이밍(셰이더 4K ≈0.39–0.45ms)과 **비교해야 하는 측정**을 할 때는 반드시
`--profile release-fat`으로 빌드할 것(측정 기준이 바뀌면 비교가 무의미해진다).

**주의**: 프로파일이 바뀌면 워크스페이스 전체(의존성 포함)가 한 번 재컴파일된다. 한 번만
비싸고 그 뒤부터 빨라진다.

**주의 2**: pi-lens가 백그라운드에서 cargo 테스트 타깃을 돌리면 같은 `target/` 락을 공유해
서로 기다린다. 빌드가 비정상적으로 멈춘 것처럼 보이면 `cargo.exe`의 CPU 시간이 0인지 확인할 것.

**교체 순서(중요)**: `par-term.exe`를 복사하기 **전에 par-term 프로세스를 종료**해야 한다.
실행 중이면 `Device or resource busy`로 실패한다. 자식(pi 등)도 함께 죽이려면 `taskkill /T`.

**로그 규칙(중요)**: `log::info!`는 `%TEMP%\par_term_debug.log`에 항상 남는다.
`crate::debug_info!` 등은 debug 레벨 게이팅을 받아 `--log-level info`로는 남지 않는다.
로그는 세션 시작 시 회전한다 → **실행 후 읽어야** 한다.

**셸 함정**: `bg_run`/cmd 계열은 msys 경로(`/c/...`)를 못 쓴다. `cd /d C:\...`를 쓸 것.
(bash 툴은 반대로 `/c/...`를 쓴다.)

### 코어 패치 (신규 · 유지보수 대상)

`Cargo.toml`에 다음이 추가돼 있다:

```toml
[patch.crates-io]
par-term-emu-core-rust = { path = "vendor/par-term-emu-core-rust" }
```

`vendor/par-term-emu-core-rust`는 crates.io 0.48.0 사본이며 **`src/terminal/mod.rs` 한 파일만**
수정했다(§2 P1). 사본에서 의도적으로 제외한 것: `docs/`, `.claude/`, `web_term/`, `Cargo.lock`,
`Cargo.toml.orig` 등 빌드에 불필요한 것. **`benches/`는 `Cargo.toml`의 `[[bench]]`가 가리키므로
반드시 있어야 한다**(빠지면 `cargo bench`/`--all-targets`가 target resolution 오류로 즉시 실패).

> **업스트림 갱신 시**: 이 패치는 `[patch.crates-io]` 경로 교체이므로, 코어 버전을 올리면
> 새 버전으로 `vendor/`를 다시 뜨고 동일 수정을 재적용해야 한다. 또는 수정을 업스트림에
> 제안하는 편이 낫다(§6).

### 검증 도구 (`C:\Users\jky72\par-term\galaxy-work\work\`)

| 도구 | 용도 |
| --- | --- |
| `verify-final.ps1` | **최종 E2E**: pi 입력(stdin 바이트 검사) + 최소화/복원 + 1행 그리드 전달 검사 + 스크린샷 |
| `pi-observe.mjs` | `node --import`로 pi에 주입되는 관찰 shim — pi stdin 바이트와 크기 레코드를 JSONL로 기록 |
| `tabshot.ps1` | topmost + DPI aware 창 캡처 |
| `pi_input_verify.ps1` / `pi_move_test.ps1` | (구) pi 입력 검증 |
| `minimize_test.ps1` / `click_verify.ps1` | 최소화 생존 / 합성 클릭 |
| `winsize_probe.py` / `coninput_probe.py` | 자식이 보는 크기 / 콘솔 입력 레코드 |
| `render_check.py` / `test_motion.py` | 셰이더 4K 오프스크린 GPU 시간 / 애니메이션 |

코어 레벨 재현 하네스: `par-term-terminal/examples/handoff_probe.rs`
(GUI 없이 PTY를 직접 띄워 `conpty.raw` → `core-before.txt` / `core-after.txt` 생성).
GUI 타이밍에 휘둘리지 않고 코어 수정을 판정할 수 있어 유용하다.

### 도구 함정 (이걸 모르면 검증이 조용히 무효가 된다)

1. **par-term은 top-level 창을 2개 이상 소유**한다 — 큰 실제 창 + **22×22 헬퍼**.
   `EnumWindows`에서 "마지막 매치"를 쓰면 22×22를 잡아 **모든 캡처/타이핑이 무효**가 된다.
   반드시 **최대 면적**으로 선택할 것. (이 버그로 pi 입력 검증 1회가 통째로 날아갔다.)
2. 캡처 좌표는 `SetProcessDPIAware()` 없이는 DPI 가상화로 어긋난다.
3. 창 생성 직후(≈3초 미만) `EnumWindows`는 `no window`가 나온다.
4. `Start-Process -ArgumentList`는 배열을 **공백으로만** 잇고 따옴표를 붙이지 않는다.
   공백 포함 값은 문자열에 **직접 따옴표를 넣어야** 한다(안 하면 clap 인자 오류로 즉시 종료).
5. msys 경로(`/tmp/...`)는 `powershell -File`에 못 쓴다(반드시 `C:\...`).
6. `$args`는 PowerShell 자동 변수라 다른 이름을 써야 한다.
7. 함수 이름에 `-`를 쓰면 안 된다(`function Type-$Keys`는 파싱 실패).
8. 이미지에서 색으로 무언가를 찾을 때 **탭바 아래 은하의 따뜻한 픽셀이 허용오차에 걸려**
   centroid가 오염된다 → 스트립 영역으로 제한하고 클러스터 단위로 판정할 것.
9. **pi 시작 시간은 부하에 따라 크게 변한다.** 확장/업데이트 확인을 끄고(`--no-extensions`
   등 + `PI_OFFLINE=1`) 다른 무거운 작업이 없으면 **TUI가 약 4초에 뜬다.** 문서에 적혔던
   〝30~190초〞는 동시에 돌던 cargo 빌드가 원인이었다 — pi 시작이 이상하게 느리면 먼저
   CPU를 먹는 다른 프로세스를 의심할 것.
10. **`KITTY_KEYBOARD` 로그를 준비 신호로 쓰지 말 것.** 이 로그는 키 핸들러에서
    〝플래그가 바뀔 때만〞 찍히고 핸들러는 키 이벤트에서만 돈다 → **첫 타이핑 전에는 절대
    나타나지 않으므로**, 이걸 기다리는 루프는 매번 전체 타임아웃을 소모한다. 증거로만 읽을 것.
11. **픽셀로 "준비됨"을 판정하지 말 것.** pi 입력행의 전체 폭 커서 띠를 감지하는 방식은
    두 번 실패했다: ① 아직 그리지 않은 창은 평평한 흰색으로 읽혀 오검출(0.1초에 "준비됨")되고,
    ② 그 띠는 **일시적 프레임에만** 존재해 다음 실행에서는 TUI가 멀쩡히 떠 있는데도
    타임아웃까지 대기했다. 밝은 픽셀 개수 지표도 창 크기에 따라 달라져 분리되지 않았다
    (빈 터미널 5256 vs pi 2380). `wait_pi_ready.py`는 이 실패의 기록으로만 남겨둔다.
12. `vtinput_probe.py` 방식(파이썬이 VT 입력 모드를 켜고 stdin을 읽음)은
    `WaitForSingleObject`가 콘솔 핸들에서 시그널되지 않아 **0바이트로 나온다** — 쓰지 말 것.

---

## 2. P1. pi 입력이 안 됨 — ✅ 해결 · 검증

### 진짜 원인: 코어의 DEC 2026(synchronized output) 종료 마커 탐색 버그

pi가 실제로 뱉은 바이트(`conpty.raw`)의 마지막 동기화 블록:

```text
3492: ESC[?2026l  ->  ESC[16;1H "hello kitty" ...
```

코어(`par-term-emu-core-rust` 0.48.0)는 동기화 종료 마커 `ESC[?2026l`을 수신 버퍼의
**마지막 32바이트**에서만 찾고 있었다:

```rust
let peek_len = 32.min(self.sync_state.update_buffer.len());
let peek_start = self.sync_state.update_buffer.len() - peek_len;
if contains_bytes(&self.sync_state.update_buffer[peek_start..], b"\x1b[?2026l") { flush }
```

ConPTY는 마커 **뒤에** 내용을 붙여 보내므로 마커가 32바이트 창 밖으로 밀리고,
**버퍼가 영원히 flush되지 않는다.** 입력은 par-term까지 도착했지만 화면에는 반영되지 않았다.

**수정**: 검색 시작점을 `old_len - (marker_len - 1)`로 바꿔 **이번 청크 + 8바이트 오버랩**을
검사한다(전체 버퍼를 매번 재검색하면 긴 업데이트가 2차 복잡도가 되므로 하지 않는다).

### kitty 프로토콜도 실제로 필요했다 (별개 결함 2건)

pi는 시작 시 `CSI > 7 u`(flags=7 = disambiguate + report_event_types + report_alternate_keys,
**report_all 없음**)를 푸시하고 `CSI ? u`로 조회한다. 로그로 확인:
`KITTY_KEYBOARD flags requested: 0b000111`.

- 인코더가 flags=7에서 **공백을 CSI-u로 잘못 인코딩**하던 버그를 수정
  (flags=7에서는 일반 문자·공백·Enter·Tab·Backspace가 리터럴 바이트로 나가야 한다).
- `report_all`(bit 8)일 때만 일반 문자까지 CSI-u로 인코딩한다.

### 증거

| 증거 | 내용 |
| --- | --- |
| 코어 하네스 | `core-before.txt`에는 입력이 없고, 수정 후 `core-after.txt`에 `hello kitty`가 나타남 (동일 `conpty.raw` 재사용) |
| 회귀 테스트 | `par-term-terminal/tests/sync_updates_regression.rs` — 종료 마커가 청크 경계에서 잘리는 **0~9바이트 분할 전수** 검사 |
| 회귀 테스트 | `par-term-input/tests/kitty_regression_tests.rs` — flags=7/8별 인코딩 규칙 |
| GUI E2E | 입력창에 `hello kitty` 표시(스크린샷), pi stdin 수신 바이트 검사 PASS |
| 로그 | `KITTY_KEYBOARD flags requested: 0b000111` |

### 함께 넣은 개선 (원인이 아니었지만 실제 문제였던 것)

- **그리드 정착 게이트**(`commit_pty_grid_when_settled`): 시작 시 폭풍
  `78x24 → 177x41 → 178x43 → 78x24`(25ms)에서 터무니없는 41·43행이 자식에게 전달되던 것을
  "두 프레임 연속 같은 그리드일 때만 커밋 + 락 미스 시 다음 프레임 재시도"로 제거.
- **alt-screen 리사이즈 펄스**(`sync_resize_pulses`): Windows/ConPTY에는 out-of-band resize
  채널이 없어, TUI가 alt-screen에 들어가는 시점에 크기를 다시 밀어준다.
  같은 크기 재적용은 ConPTY에서 no-op이므로 `cols-1` → `cols` 순서로 보낸다.

> **기각된 원인**: kitty 프로토콜 미구현만으로는 설명되지 않았다(구현 후에도 증상 재현).
> 포커스 이벤트(DECSET 1004)는 이미 구현돼 있었고, 자식은 크기 이벤트를 정상 수신했다.
> "입력창이 화면 밖으로 밀림"은 별개 문제로 **행 수 부족**(80x24)이 원인이었다.

---

## 3. P2. 창을 최소화하면 패닉으로 죽음 — ✅ 해결 · 검증

### 진짜 원인: egui가 아니라 par-term 자체 스크롤바

패닉 메시지의 `min = 0.0, max = -19.0`은 스크롤바 썸 높이 산술과 정확히 일치한다:

```rust
scrollbar_height = (viewport_ratio * track_pixel_height).max(MIN_SCROLLBAR_THUMB_HEIGHT_PX);
// 최소화 → track ≈ 1px, MIN = 20  →  이동 가능 범위 = 1 - 20 = -19  → clamp(0, -19) 패닉
```

원래 문서는 "`src/`의 clamp는 전부 보호돼 있으니 의존성 내부"라고 추정했지만, **`.max()`로
최소값을 강제한 뒤 상한과의 관계를 보지 않은 것**이 원인이었다.

**수정 3중**:

1. `thumb_height(viewport_ratio, track) = (...).max(MIN).min(track)` — 썸이 트랙을 넘지 않는다.
2. 스크롤바 가시성 가드: `window_width > 0 && window_height > content_offset_y + content_inset_bottom`.
3. `should_render_frame()`에서 최소화 상태면 프레임을 만들지 않는다(0크기 surface 레이아웃 차단).

### 후속으로 발견한 결함: 최소화 중 1행 그리드가 자식에게 전달됨

최소화된 창은 **아이콘 크기(192×34)**를 보고하고, renderer가 이를 `13x1` 그리드로 변환한다.
복원하면 프레임이 **진짜 크기 이벤트보다 몇 ms 먼저** 재개되므로, 정착 게이트가 "두 프레임 연속
같은 그리드"로 판정해 **1행 터미널을 자식에게 전달**했다:

```text
608.271  Resized 237x39      ← 최소화 (이 구간에 PTY 리사이즈 로그 없음 = 프레임 가드 정상)
612.280  PTY <- 12x1         ← 복원 직후 2프레임 (renderer가 아직 12x1)
612.350  Resized 1300x900    ← 진짜 크기
```

**수정**: `WindowState::pty_grid_suspect` 플래그.

- 최소화 가드에서 `suspect = true` + 후보 리셋
- `commit_pty_grid_when_settled()`에서 `suspect`면 커밋하지 않음
- `WindowEvent::Resized`에서만 `suspect = false`

최악의 경우 자식이 **최소화 직전의 정상 크기**를 유지하므로 실패 방향이 안전하다.
(pi는 이 결함을 실제로 견뎠다 — 복원 화면은 깨지지 않았다. 그래도 다른 TUI는 1행 리사이즈에서
레이아웃이 깨질 수 있으므로 고칠 가치가 있다.)

### 증거

| 증거 | 내용 |
| --- | --- |
| 대조 실험 | `par-term-official-0.45.0.exe`도 동일하게 죽었다 → 이 저장소의 크롬 패치와 무관 |
| 회귀 테스트 | `par-term-render` scrollbar geometry — track 0/1/19/20/21/100 × ratio 4종에서 `travel >= 0` |
| GUI E2E | 최소화 4초 생존, 복원 정상, 복원 후 타이핑도 정상 |
| 로그 검사 | `verify-final.ps1`이 최소화~복원 구간의 PTY 그리드를 파싱해 1행이 있으면 FAIL |

---

## 4. P3. "탭바 아이콘 크기 제한" — ✅ 해결 (요청 확정 후)

요청 이력이 "높이 절반" → "가로 절반" → 선택지 확인으로 **"탭 하나의 가로 폭 절반"** 으로
확정됐다("높이는 건들지마").

- 구현: 한 탭의 폭 상한 = `(탭 영역 폭 × 0.5).max(tab_min_width)` — `src/tab_bar_ui/horizontal.rs`
- 탭 높이는 그대로 두고, pill 인셋/패딩으로 여백만 조정
- 확인: 탭 1개가 1300px 스트립에서 약 570px에서 멈춘다(스크린샷)

원래 문서가 지적한 "no-op" 문제(아이콘 폰트 16.2px vs 탭 폭 절반 65px)는 **요소를 잘못 짚은
것**이었다 — 사용자가 줄이려던 것은 프로필 아이콘이 아니라 탭 자체의 폭이었다.

---

## 5. 한글(IME) 입력 — ✅ 해결 · 검증

### 증상과 원인

par-term 창에서 **한글이 아예 입력되지 않았다**(영문 알파벳조차 들어가지 않음).

원인은 `impl_init.rs`가 `window.set_ime_allowed(true)`로 플랫폼 IME를 켜놓고도,
이벤트 루프에 **`WindowEvent::Ime` 처리 arm이 없었던 것**이다(17개 arm 중 누락).
IME가 조합 중에는 물리 키를 소비하므로 키 경로에서도 문자가 나오지 않아, 글자가
**어떤 경로로도 PTY에 도달할 수 없었다.**

### 구현

| 위치 | 내용 |
| --- | --- |
| `src/app/input_events/ime.rs` (신규) | `handle_ime_event` — `Enabled`/`Disabled`/`Preedit`/`Commit` |
| `src/app/window_state/ime_state.rs` (신규) | `ImeState` (조합 문자열·커서·후보창 위치 캐시) |
| `handle_window_event.rs` | `WindowEvent::Ime(ime) => self.handle_ime_event(ime)` |
| `egui_overlays.rs` + `egui_submit.rs` | `render_ime_preedit` — 조합 중 문자열을 커서 셀 위에 인라인 표시(밑줄 포함) |
| `publish_ime_cursor_area` | `set_ime_cursor_area`로 후보창을 커서에 붙임 |

**중요**: `Commit`은 `paste_text`를 쓰지 않고 **plain write**로 보낸다. `paste_text`는
`TerminalManager::paste`로 가서 붙여넣기 의미론(브래킷 붙여넣기, 개행 처리)이 붙기 때문에
"타이핑"에 부적합하다.

### 검증 (실제 한국어 IME)

로그에 **완성형 음절**이 찍히는 것으로 확인했다:

```text
IME: commit "호" (0xD638)
IME: commit "안" (0xC548)
IME: commit "녕" (0xB155)
```

`U+AC00~U+D7A3`(완성형 음절) 영역이면 조합이 정상이다. 화면 확인도 일치했다.

### ⚠️ 진단 함정 (이걸 모르면 정상 동작을 버그로 오판한다)

**자음만 이어서 치면 자음마다 `commit`되는 것이 정상이다.** 예를 들어 `ㅎㅇㅎㅇ`을 치면
`commit "ㅎ" (0x314e)`, `commit "ㅇ" (0x3147)` … 처럼 **호환 자모(U+3131~U+318E)** 가
따로 커밋된다. 조합할 모음이 없기 때문이다. 이 로그만 보고 "조합이 안 된다"고 단정했다가
오판한 적이 있다 — 판정은 반드시 **모음을 포함한 음절**(예: 안녕)로 할 것.

### 대안 검증 방법 (자동화가 막힌 지점)

Imm32로 조합 문자열을 주입하는 자동 검증은 **Windows가 백그라운드 프로세스의 포그라운드
전환을 막아서** 실패한다(`SetForegroundWindow` 후에도 `activated=False`). TSF 기반 IME는
활성 창에만 HIMC를 만들기 때문에 `ImmGetContext`가 0을 반환한다. 스크립트로 밀어붙이지 말고
사람이 직접 치게 할 것(이번에도 그렇게 해서 검증했다).

---

## 6. 기각된 가설 (다시 조사하지 말 것)

| 가설 | 기각 근거 |
| --- | --- |
| pi 입력 = kitty 프로토콜 미구현 | 구현 후에도 증상 재현. 진짜 원인은 §2의 코어 버그 |
| pi 입력 = 포커스 이벤트(DECSET 1004) 미구현 | 이미 구현돼 있었다 |
| pi 입력 = 자식이 크기 이벤트를 못 받음 | `coninput_probe.py`: 30초에 7건 수신 |
| pi 입력 = par-term이 화면을 안 그림(리페인트) | 창 이동으로는 안 되고 리사이즈하면 됨 → 파이프라인 문제 아님 |
| 최소화 패닉 = egui/의존성 내부 | `src/` 스크롤바 산술이 정확히 일치 (§3) |
| pi 입력창 문제 = 그리드/리사이즈 | 행 수 부족(24행)이 원인. 39행으로 키우면 정상 표시 |
| 탭 아이콘 = 프로필 아이콘/벨 이모지 | 사용자 확인 결과 탭 자체의 가로 폭 |
| 한글 = 자모 단위로 들어가서 조합이 안 된다 | **오판**. 초성만 친 경우(ㅎㅇㅎㅇ)는 자음마다 확정되는 것이 정상. 모음을 포함해 치면 완성형 음절이 커밋된다 |

---

## 7. 남은 위험 · 다음 작업

| 항목 | 내용 |
| --- | --- |
| **업스트림 반영** | 코어 수정은 `vendor/` 패치다. 업스트림(`par-term-emu-core-rust`)에 이슈/PR로 제안하면 유지보수 부담이 사라진다. 근거: 마커가 마지막 32바이트에 없다는 것만으로 버퍼가 영구 정지하는 것은 명백한 버그다 |
| **코어 버전 업 시** | `vendor/` 재생성 + 동일 수정 재적용 필요(§1) |
| `blur_enabled` | Windows에서 no-op(macOS 전용, `config_propagation.rs:144`) |
| S3/S4/S6/S7 (크롬) | 의도적 보류. 근거는 원래 문서와 동일: 테마 고정이라 이득 0 / 필요성 미확인 / 셰이더가 DWM 백드롭을 덮음 / 회귀 리스크 |
| P3 후속 | 탭 폭 상한이 **여러 탭**일 때 의도대로 동작하는지(탭 1개만 확인함) |
| 미검증 | 최소화/복원을 **여러 번 반복**했을 때의 안정성(현재 1회 검증) |

---

## 부록 A. 이미 완료·검증된 것 (재작업 금지)

| 항목 | 검증 근거 |
| --- | --- |
| Kanagawa Wave 테마 + Maple Mono NF KR | 픽셀 확인. **`theme.background`는 ANSI black(`9,6,24`)과 같아야 한다** — par-term은 셀 기본배경을 테마 `background`와 RGB 정확 일치로 판정하고, 콘솔 기본 속성은 `theme.black`으로 해석되므로 다르면 셀마다 불투명 쿼드가 그려져 배경 셰이더를 덮는다 |
| 둥근 창 모서리 + 창 테두리 | 모서리 픽셀에서 뒤 콘텐츠 노출(=DWM 라운딩), 테두리 `(84,84,109)` |
| 탭바 반투명 / 하단 인디케이터 / pill 인셋 | `tab_bar_bg_alpha 0.85` → 실측 `(19,19,25)` = `22×0.85` 일치. 공기 위 5px/아래 4px 대칭 |
| 캡션 버튼(우상단, Kanagawa) | 3원 검출 + **합성 클릭으로 실제 최소화 발동**(E2E). 닫기는 `WM_CLOSE` 포스트로 `prompt_on_quit` 우회 방지 |
| 탭 글자 굵게 / 탭 폭 유동 / 탭 폭 상한 | `tab_text_bold`, `tab_stretch_to_fill` + 50% 상한 — 캡처 확인 |
| 스크롤바 10px 캡슐 | 썸 폭 15 물리px(=10 논리) 일치, 끝단 테이퍼 7→9→11→13→15px = 반지름 7.5px 반원과 일치 |
| 창 드래그/리사이즈 | `titlebar_drag.rs`(GWLP_WNDPROC 서브클래싱 + `WM_NCHITTEST` → 탭바 빈 영역 `HTCAPTION`, 가장자리 6px 밴드로 HTLEFT/HTRIGHT/HTTOP/HTBOTTOM + 코너) |
| `--command-to-send` LF→CR | Windows ConPTY는 Enter를 CR로 받는다. LF만 보내면 제출되지 않는다 |
| 배경 셰이더 | `tilted-spiral.glsl`. 4K 오프스크린 GPU 시간 ≈0.39–0.45ms/프레임(RTX 5090) |

## 부록 B. 참고 문헌 (같은 문제를 다룬 외부 자료)

- pi 공식: `docs/terminal-setup.md` — *"Pi uses the Kitty keyboard protocol"* (터미널별 설정 안내)
- kitty 키보드 프로토콜 스펙 — `CSI > flags u`(push), `CSI ? u`(query), `CSI = u`(pop),
  `CSI code;mods u` 인코딩
- DEC 2026 synchronized output — `CSI ? 2026 h/l`
- pi 이슈 #8733 — *"TUI freezes... no reaction to input... only in VS Code integrated terminal(Windows)"*
- pi 이슈 #767 — Windows bracketed paste가 submit으로 오인
- WezTerm PR #4876 `ResizeFinished` — *"빠르게 리스케일할 때 셀 수가 바뀌는 레이스"* (정착 게이트와 동일 원리)
- microsoft/terminal PR #15935 — *"ConPTY: Avoid WINDOW_BUFFER_SIZE_EVENT when the viewport moves"*
- microsoft/terminal issue #16911 — ConPTY를 키우면 리플로우가 화면을 덮어씀
- microsoft/terminal issue #6859 — *"ConPTY: transmit DECSET/DECRST state when client enters/exits
  ENABLE_VIRTUAL_TERMINAL_INPUT"*
- wmux commit 248a2c5 — *"trigger ConPTY resize on re-attach to force TUI redraw"*:
  `resize(cols-1, rows)` → `resize(cols, rows)` (같은 크기 재적용은 no-op)
- phi-code commit 3de0ddc — *"force a startup re-render on Windows (fixes layout until resize)"*

---

## 8. 배경 셰이더 고도화 (2026-09-13, v3.0.1 → v3.5.0)

`tilted-spiral.glsl` ("Continuum – Pearl Spiral"). 작업본 = `galaxy-work/shaders/`,
설치본 = `%APPDATA%\par-term\shaders\`. **둘을 항상 동일하게 유지할 것**(cmp로 확인).

### 고친 실제 버그: 은하 중심의 검은 사각형

**증상**: 창 크기를 줄이면 은하 중심에 검은 구멍이 생겼다.

**원인**: `atan(p.y, p.x)`가 정확히 원점에서 평가되는 경로가 있었다. GLSL에서 `atan(0,0)`은
**정의되지 않고** 드라이버에 따라 NaN이 된다. 그 NaN이 `structureAt` 전체를 타고 흘러
`max(NaN, 0)`에서 0으로 접히며 검게 칠해졌다. `iCloudPixel=4` 양자화 때문에 한 블록(4×4)이
**같은 좌표를 샘플**하므로 그 블록 전체가 검아졌고, 그 블록이 중심에 걸리는지는 **창 크기에
따라** 달라져서 "창을 줄이면 생긴다"가 됐다.

**수정**: `vec2 p = dC/max(iScale,0.02) + vec2(1e-5);` — 원점을 미세하게 비켜 평가한다.

### 왜 중심이 별보다 어두웠나 (별개 문제)

`col = col/(1.0 + col*0.9)` 하이라이트 압축이 코어를 **0.67**로 눌러, 별(1.0)보다 어두운
부드러운 글로우가 됐다. **별처럼 압축 뒤에 더해야** 실제 밝은 점이 된다(별들이 그렇게 그려진다).

### 부피감 (요청)

- **spheroid 프레임**: 벌지의 반경을 원판보다 **둥근** 계(frame)로 측정한다. `p.y`가 이미
  `1/iInclination`을 갖고 있으므로 `iInclination/coreIncl`을 곱하면 된다. `CORE_ROUND=0.45`
  → 코어의 수직 반경이 원판의 **약 1.4배**. (선언만 되고 안 쓰이던 죽은 상수 `CORE_ROUND`,
  `ARM_ASYM`, `CLUSTER_AMOUNT`가 있었다 — 주석은 "둥근 metric으로 측정한다"고 적혀 있었지만
  그 코드가 없었다.)
- 벌지 반경 0.29 → 0.32, 지수 1.55 → 1.42 (어깨를 넓게) + 돔 셰이딩.

### 시도했다 되돌린 것 (재시도 금지)

| 시도 | 되돌린 이유 |
| --- | --- |
| 넓은 헤일로(외곽 봉투) | 중심에서 320~460px 구역을 **순검정(0.0) → luma 6**으로 밝혔다. 배경은 검아야 한다 |
| 사건의 지평선 + 강착 링 | 사용자 의도와 달랐다("그냥 크고 밝은 점") |

### 별 개수 (실측)

| | 값 | 근거 |
| --- | --- | --- |
| 원판 별 | 셀 5px → **3px** (5×5 탐색) | 원판 우측 별 픽셀 **+166%**, 격자 이론치 2.78배에 근접 |
| 하늘 별 | 레이어 **3개**(23/47/16px), `iSkyDensity` 0.42 | 은하 밖 하늘 +48% |
| 하늘 레이어 추가 비용 | **0** | 0.387ms로 기준선과 동일 (O(1)/픽셀) |

**5×5 확장의 근거**: 2px 별은 원판 좌표계에서 세로로 `2/inclination` 셀 폭을 차지한다.
3×3은 1셀까지만 도달 → 하한 `2.6/incl`(≈4.9px). 5×5는 2셀 도달 → 하한 `1.3/incl`(≈2.45px).
그래서 3px 셀이 안전해진다. **셀 크기와 무관하게 루프는 25회 고정**이므로, 4px로 올리는 건
같은 비용에 별만 적어지는 손해다.

### 반짝임 (전 별 적용)

`iTwinkle` 기본 1.0. 별마다 **주기·진폭·위상이 독립**이다(다른 해시 3개):
- 주기 `mix(1.6,5.2)` rad/s → **1.21~3.93초** (평균 2.08s)
- 골 깊이 `mix(0.40,0.80)` → **40~80%**
- 파형 = 주파수 다른 두 성분(`rate`, `rate×0.43`)을 0.60:0.40으로 혼합 (메트로놈 방지)
- 검증: 인접 별 상관계수 **-0.004**, 주기↔깊이 **-0.017** (독립)

**실패했던 첫 버전**: `rate = mix(0.35,1.55)`(**주기 4~18초**) + `depth = mix(0.12,0.58)`
→ 별 하나를 응시해도 몇 초간 변화가 안 보였다("반짝임이 안 보인다"는 피드백). 게다가
`1-envelope²` 형태라 골이 **드물고 얕게** 왔다. **반짝임은 주기와 진폭을 둘 다 봐야 한다.**

**중심 별만 반짝임이 빠져 있었다** — 고정 별을 추가할 때 `scintillation`을 안 걸었다.
"모든 별에 적용" 요청의 실제 대상이 이것이었다.

### 성능 (4K, render_check.py)

| 버전 | GPU 중앙값 |
| --- | --- |
| 기준선(문서) | 0.39~0.45ms |
| v3.4.0 (하늘 레이어 3개) | 0.387ms |
| v3.5.0 (5×5 원판 탐색) | **0.584ms** (+51%) |

60fps 예산의 3.5%. 증가분 0.197ms는 예측치(0.11ms × 1.78)와 일치한다.

### 셰이더 검증 함정

1. **`--screenshot`은 실제 창과 합성 방식이 다르다.** 같은 셰이더에서 오프스크린 렌더의 빈
   모서리는 테마 배경 `(9,6,24)`로, **실제 창은 `(0,0,0)`**으로 나왔다. 게다가 커맨드라인의
   `--shader <name>` 재정의는 무시됐다(debug 로그: `CLI override: using shader <config 값>`).
   배경 밝기 판정은 **실제 창 캡처**로 할 것(`shader_shot.ps1`).
2. **반짝임은 한 실행에서 여러 프레임을 찍어야 측정된다.** 별도 실행 2회는 `iTime`이 다시
   시작해 같은 위상에 걸린다(`shader_series.ps1`).
3. 원판 별은 **은하 회전으로 이동**한다. 고정 픽셀의 밝기 변화를 반짝임으로 오독하면 안 된다.
   화면 고정인 **하늘 별**로 재야 한다.
4. 은하를 화면 밖으로 밀어내는 것(`iCenterX: 1.60`)이 순수 하늘 별 측정에 가장 깔끔하다.
5. 스크린샷에 보이는 작은 검은 점은 **마우스 포인터일 수 있다**. `SetCursorPos`로 옮겨서
   확인할 것(셰이더 버그와 구분).

### 성능 최적화 (v3.5.0 → v3.6.0)

원판 별을 2.6배로 늘린 대가가 **+51%** 였는데(0.387 → 0.584ms), 낭비 3곳을 고쳐 **+5%**
(→ **0.407ms**)까지 줄였다. luma 분포는 p95/p99/max가 **완전히 동일** — 화질 손실 없음.

| # | 낭비 | 왜 낭비였나 | 조치 |
| --- | --- | --- | --- |
| 1 | `diskStars`가 **후보 별마다** `starDensityAt(dStar)` 호출 | 그 안에서 `structureAt`(vnoise 2회 + `atan`/`log`/`sin`)을 재계산 → 픽셀당 최대 5회 중복. 밀도장은 ~24px 규모로 변하는데 셀은 3px이라 **구분 자체가 불가능** | 픽셀당 1회로 승격하고 `structureAt` 샘플을 재사용. `starDensityAt` 함수 삭제 |
| 2 | 게이트에 걸려 탈락한 별도 `pow` + `scintillation`(sin 2회) + `starColour`(mix 3회)를 계산 | 하늘 레이어는 밀도가 0.13~0.42라 **58~87%가 빈 픽셀** | `if (occ >= density) continue;` / `if (inside < 0.5 || occ >= dens) return;` 로 **비싼 계산 앞으로** 이동 |
| 3 | `diskToScreen`이 후보마다 `rotv` 2회(삼각함수 4회) | 두 회전과 inclination 스케일은 프레임 전체에서 **상수** | `M = R(pa)·diag(1,incl)·R(ang)` 를 2×2 행렬로 1회 합성 |

**측정 결과** (4K, `render_check.py`)

| 버전 | 중앙값 | p95 |
| --- | --- | --- |
| v3.4.0 (별 적음, 3×3) | 0.387ms | 0.390ms |
| v3.5.0 (2.6배 별, 최적화 전) | 0.584ms | 0.600ms |
| v3.5.1 (+#1,#2) | **0.407ms** | 0.545ms |
| v3.6.0 (+#3) | 0.407ms | 0.423ms |

**주의**: #3은 중앙값을 바꾸지 못했다 — 컴파일러(GPU 드라이버)가 이미 삼각함수를 hoisting하고
있었다는 뜻이다. p95만 개선됐지만 10샘플이라 잡음일 수 있어 **과장하면 안 된다**. 그래도 명시적
hoisting은 드라이버 의존을 줄이므로 유지한다. 수학적 동일성은 무작위 20,000점 × 4조합에서
최대 오차 `4.4e-16`(부동소수점 엡실론)으로 검증했다.

**남은 여력**: `iQuality`(fbm 옥타브 수)가 유일한 큰 레버이고, 그 외에는 `structureAt`의
`atan`/`log`/`exp` 6회 정도다. 지금 비용은 60fps 예산의 **2.4%**라 더 짜낼 이유가 크지 않다.
