# par-term 픽셀아트 은하 배경 — 현재 구현 브리핑

작성: pi (coding agent) · 용도: 은하 모양 개선 상담

---

## 1. 최종 목표 (하드 요구사항)

터미널 창 **뒤에 항상 떠 있는** 애니메이션 은하 배경.

1. **진짜 픽셀아트**: 별은 1×1 / 2×2 **하드엣지 정사각형**, 정수 픽셀 스냅, **안티앨리어싱 금지**. 둥근 점은 명시적으로 거부됨.
2. **칠흑 배경** (#000000).
3. 별은 **밴드/은하를 따라 흐르고**, 여러 속도(시차)를 가짐.
4. **눈에 띄는 격자·체커보드·반복 타일 금지**.
5. **GPU 부담 최소** (게임/작업 중에도).
6. **영상 / GIF / 프리렌더 / 이미지 텍스처 금지.** 진짜 절차적(per-pixel) 렌더링.

현재 단계: "가는 대각선 은하수 띠" → **기울어진 나선은하**로 교체 완료. 이제 **모양 자체를 더 아름답게** 다듬는 단계.

---

## 2. 환경

- Windows 11 x64, 3840×2160 @ 120Hz, DPI 100%
- RTX 5090 (dGPU) + AMD Radeon Graphics (iGPU)
- 도구: PowerShell 7, git bash, Python 3.10 (Pillow, numpy), `moderngl` 5.12 (벤더링됨)
- Rust 1.98.1 (`x86_64-pc-windows-msvc`) — par-term 소스 패치/빌드용

---

## 3. par-term 설치 상태

par-term은 Rust + wgpu 터미널이야. **커스텀 배경 셰이더 슬롯**을 제공하고, 성능 제어가 기본 내장돼 있어서 선택했어.

| 항목 | 값 |
| --- | --- |
| 실행파일 | `C:\Users\jky72\par-term\par-term.exe` — **로컬 패치 빌드**, 45,859,328 bytes, sha256 `882d3346932e…` |
| 공식 백업 | `C:\Users\jky72\par-term\par-term-official-0.45.0.exe` (45,897,216 bytes, sha256 `486b5f4377d0…`) |
| 설정 | `C:\Users\jky72\AppData\Roaming\par-term\config.yaml` |
| 셰이더 설치 위치 | `C:\Users\jky72\AppData\Roaming\par-term\shaders\` (번들 73개 + 우리 것) |

### 로컬 패치 내용 (은하와 무관, 창 동작)

`window_decorations: false`(테두리 없는 창)에서 **창을 드래그로 옮기고 가장자리로 리사이즈**할 수 있게 패치했어.
WezTerm이 앱 내부에서 `WM_NCCALCSIZE`/`WM_NCHITTEST`로 처리하는 것(PR #1675/#1677)을, par-term에는 그 코드가 없어서
윈도우 프로시저 **서브클래싱**으로 구현했어.

- 신규 `src/app/window_manager/titlebar_drag.rs` — `WM_NCHITTEST`에서 탭바 빈 영역 → `HTCAPTION`, 가장자리 6px → `HT*`
- diff: `C:\Users\jky72\par-term\build\tab-bar-drag.patch`, 문서: `build\PATCH-NOTES.md`
- **셰이더와는 완전히 독립**이야. 셰이더 작업에는 영향 없음.

### 셰이더 관련 config

```yaml
custom_shader: tilted-spiral.glsl
custom_shader_enabled: true
custom_shader_animation: true
custom_shader_brightness: 1.0      # 앱이 자동 적용 안 함 → 셰이더가 iBrightness를 직접 곱함
custom_shader_text_opacity: 1.0
custom_shader_full_content: false  # 배경 모드: 텍스트가 위에 샤프하게 합성됨
max_fps: 60
vsync_mode: fifo
pause_shaders_on_blur: true        # 포커스 잃으면 셰이더 정지
pause_refresh_on_blur: true
unfocused_fps: 30
inactive_tab_fps: 2
window_decorations: false
snap_window_to_grid: false
tab_bar_mode: always
tab_style: minimal
tab_bar_height: 26.0
window_padding: 4.0
status_bar_enabled: false
```

---

## 4. 은하 셰이더 — `tilted-spiral.glsl`

| | |
| --- | --- |
| 소스 (편집 기준) | `C:\Users\jky72\par-term\galaxy-work\shaders\tilted-spiral.glsl` |
| 설치본 | `C:\Users\jky72\AppData\Roaming\par-term\shaders\tilted-spiral.glsl` (동일, sha256 `224f0cf0902e…`) |
| 크기 | **19,101 bytes / 471줄** |
| 컨트롤 | **float 16 + int 5 = 21** (par-term은 float 16개까지만 노출 — 한계에 딱 맞춤) |

### 4.1 par-term 셰이더 계약

- `void mainImage(out vec4 fragColor, in vec2 fragCoord)` — GLSL, WGSL로 자동 트랜스파일
- Shadertoy 호환. 단 `iResolution`이 **`vec2`** (+ 별도 `float iResolutionZ`), Shadertoy의 `vec3`와 다름
- **`fragCoord`는 물리 픽셀** (4K 전체화면 스크린샷 3827×2114로 검증) → 1px 별 = 물리 1px
- **`iBrightness`는 앱이 자동 적용하지 않음** → 셰이더가 직접 곱해야 함 (0.15와 1.0 출력이 완전 동일함을 A/B로 확인)
- 튜너블: `// control slider min= max= step= label="..."` 를 uniform 선언 **바로 앞**에, 기본값은 metadata `defaults.uniforms`에
- 부작용: 셰이더가 **매 프레임 픽셀당 4개 필드를 fbm으로 계산**한다. `iQuality=0`이 가장 싸다.

### 4.2 좌표 파이프라인

```
p = (px - center) / screenHeight          // 높이 정규화 → 종횡비 무관
q = R(-positionAngle) · p                 // 장축을 x축에 정렬
d = R(-orbitAngle) · (q.x, q.y / inclination)   // 회전하는 원반 좌표 (모든 장이 여기서 정의)
```

- 각도는 **화면 기준 도(度)**로 지정 (uv 기울기가 아님) → 창 종횡비가 달라도 각도 유지
- 별 렌더링 시 역변환 `diskToScreen`으로 별의 원반 좌표를 화면으로 되돌림

### 4.3 은하 필드 구성 (mainImage 안)

| 요소 | 구현 |
| --- | --- |
| **팔** | 로그 나선. `ph = th - iWinding·log(max(rn, 0.30))`. **중심부 감김을 0.30에서 포화**시켜 과도한 감김을 방지 |
| 팔 거리 | `arc = arcDist(ph, PI) * rn`, 폭 `w = iArmWidth·(0.55+0.95·rn)` |
| 팔 봉투 | `armEnvelope(rn)` = `smoothstep(0.10,0.42,rn) · (1-smoothstep(0.92,1.22,rn))` — 팔이 팽대부 위에서 켜지고 원반 끝에서 사라짐 |
| 팔 대칭 | 두 번째 팔은 상수 0.55 배율 (컨트롤 슬롯을 다른 곳에 양보) |
| 팔 흔들림 | 저주파 fbm으로 중심선과 폭을 흔들어 "매끈한 리본" 탈피 |
| 세 번째 팔 | 다른 위상 오프셋 + 노이즈 게이트로 **부분적으로만** 나타남 |
| **별구름** | `clus` (저주파) × `clus2` (고주파)로 팔 밀도 변조 |
| **암부** | 팔 중심선에서 안쪽으로 오프셋된 가우시안 레인 2줄 (`lane1`, `lane2`) × fbm. 팔을 끊는 넓은 틈(`gap`)도 별도 |
| **핵/팽대부** | `nucleus = exp(-(rnB/0.075)²)`, `bulge = exp(-(rnB/0.24)^1.45)` — **`rnB`는 원반과 다른 더 둥근 지표**(`CORE_ROUND = 2.10`)로 측정 → 3D 회전타원체 느낌 |
| **내부 나선** | `phIn = th - iWinding·1.9·log(max(rn,0.13))` 로 더 촘촘한 내부 구조를 별도 추가, `rn 0.16~0.52`에서만 |
| **발광 결절** | `knot` = 고주파 fbm × 팔 밀도. 밝기를 올리는 게 아니라 **색으로 더함** (외곽 청록, 내부 장미금색) |
| **확산 헤일로** | 자체 노이즈에 smoothstep을 걸어 **약 30%를 0으로** 만든 헤일로 → 빛무리 사이에 진짜 검정이 남음 |
| **가스 성운** | 반투명 베일 (`gasN` × `gasHoles` 구멍) — 팔에 붙고 반경 감쇠. 외곽 남보라, 내부 장미빛 |

### 4.4 색과 명암

- **램프 2종**: `rampCool`(남색→청색→청록→옅은청록) / `rampWarm`(어두운 갈색→금색→샴페인)
- **두 램프의 0 지점은 순수 검정** ← 이게 중요. 처음에 0 지점을 남색으로 뒀더니 밀도 0인 픽셀도 luma 6.8이 되어 **원반 전체가 평평한 남색 판**으로 보였음
- **하이라이트 롤오프**: `v = v / (1.0 + 0.45·v²)` — 핵이 흰색으로 뭉개지지 않게 (초안 0.85는 과했음: 코어가 색 램프 중간으로 내려가 탁해짐)
- **소프트 플로어**: `smoothstep(0.030, 0.80, dens)` — 희미한 팔 꼬리가 첫 팔레트 단계로 올라가 판이 되는 것을 방지
- **팔레트 양자화**: `iPaletteSteps`(기본 10) 단계 + **해시 기반 비반복 디더** (±0.11단계). 규칙적 Bayer 아님
- **별구름 블록**: `iCloudPixel`(기본 3) 픽셀 블록 격자에서 필드를 평가 → 청키한 픽셀 면
- **웜/쿨 혼합**: `warm = exp(-(rn/0.36)^1.7)` — 내부 금빛, 외곽 청색

### 4.5 별 렌더링 (핵심 기법)

**별은 회전하는 원반 격자에 살고, 화면으로 변환한 뒤 정수 픽셀로 스냅해서 축정렬 사각형을 그린다.**

1. 셀 크기 `cs = max(iStarCellPx, 2.6/inclination) / screenHeight`
2. 프래그먼트의 원반 좌표로 **3×3 이웃 셀** 조회 (후보 9개)
3. 후보 별의 원반 좌표 → `diskToScreen` → **`floor()`로 정수 픽셀 스냅**
4. 스냅된 좌상단 기준 **축정렬 하드 사각형** — 판정이 정수 비교라 AA가 구조적으로 불가능
5. 별 ID·크기·색은 원반 셀 해시에서 나오므로 **회전해도 불변**

- **3×3 탐색 정당성**: 화면 2px에 대응하는 원반 거리는 단축 방향 `2/(H·inclination)`. 셀을 `max(cellPx, 2.6/inclination)`로 강제하면 항상 셀보다 작아 3×3으로 충분
- **정지 배경 별밭**: 화면 격자 **2겹**(23px / 47px, 공통 주기 없음). **위치가 절대 안 움직이고 밝기만 맥동**. 별마다 위상·주기 각각 다름
- **반짝임**: `smoothstep`으로 사인파를 다듬어 "느린 페이드"가 아니라 "펄스"로. 깊이는 `0.85 × iTwinkle` (0이면 완전 정지)
- **감쇠 일관성**: 암부 감쇠를 프래그먼트 단위로 한 번 계산해 별 후보에 재사용. 별의 원반 좌표가 시간에 대해 불변이므로 **회전 중에 별이 켜졌다 꺼지지 않음**

### 4.6 컨트롤 21개 (기본값)

**float 16**
`iCenterX` 0.62 · `iCenterY` 0.58 · `iScale` 0.62 · `iPositionAngle` −25 · `iInclination` 0.48 ·
`iWinding` 2.6 · `iArmWidth` 0.27 · `iCoreGain` 0.80 · `iCloudGain` 0.64 · `iDustStrength` 0.66 ·
`iGasGain` 0.22 · `iStarDensity` 0.5 · `iStarGain` 1.0 · `iSkyDensity` 0.22 · `iOrbitSpeed` 0.015 · `iTwinkle` 0.55

**int 5**
`iCloudPixel` 3 · `iPaletteSteps` 10 · `iQuality` 1 · `iSeed` 7 · `iStarCellPx` 7

**상수로 굳힌 것** (float 슬롯 16개 제한 때문에): `CORE_ROUND` 2.10 · `ARM_ASYM` 0.55 · `CLUSTER_AMOUNT` 0.60

---

## 5. 파일 경로 전체

### 셰이더 작업 폴더 `C:\Users\jky72\par-term\galaxy-work\`

| 경로 | 내용 |
| --- | --- |
| `shaders\tilted-spiral.glsl` | **은하 셰이더 (편집 기준, 471줄)** |
| `shaders\bench-probe.glsl` | GPU 시간 캘리브레이션용 (1000회 sin/cos) |
| `work\render_check.py` | **4K 렌더 + GPU 시간 + 명암 통계 하네스** |
| `work\test_motion.py` | **애니메이션 검증 (9항목)** |
| `work\verify_patched.ps1` | 창 드래그/리사이즈 검증 (은하와 무관) |
| `work\runtime\` | 벤더링된 moderngl 5.12 |
| `outputs\validation.json` | 최신 GPU/통계 결과 |
| `outputs\tilted-spiral-4k.png` / `-half.png` | 최신 4K 렌더 / 절반 크기 |
| `outputs\compare-compositions.png` | 구도 3안 비교 |
| `outputs\compare-faint.png` | 희미함 3단계 비교 (선명 → 과도 → 적정) |
| `outputs\pixel-detail.png` | 픽셀 질감 확대 (NEAREST) |
| `outputs\par-term-final.png` | 실제 par-term 스크린샷 |
| `outputs\dbg-*.png` | 필드별 디버그 렌더 (dens / armA / bulge / dust / clus) |

### 렌더 확인 방법 (재현용)

```powershell
cd C:\Users\jky72\par-term\galaxy-work\work
# 기본: 4K 렌더 + GPU 시간 + 통계 → outputs\validation.json
python render_check.py tilted-spiral.glsl
# 태그 지정 (출력 파일명 접미사)
python render_check.py tilted-spiral.glsl tag=v11
# 유니폼 오버라이드로 진단 (예: 구름 제거)
python render_check.py tilted-spiral.glsl tag=diag iCloudGain=0.0
# 애니메이션 검증 9항목
python test_motion.py
```

### 그 외

| 경로 | 내용 |
| --- | --- |
| `C:\Users\jky72\par-term\build\` | 패치한 par-term 소스 + `tab-bar-drag.patch` + `PATCH-NOTES.md` |
| `C:\Users\jky72\par-term\docs\BRIEFING.md` | 이전 단계 브리핑 (구버전 셰이더 기준, 참고용) |
| `C:\Users\jky72\AppData\Roaming\par-term\config.yaml` | 설정 (백업: `.bak-orig`, `.bak-before-tilted-spiral`, `.bak-before-notile` 등) |
| `C:\Users\jky72\par-term\par-term-official-0.45.0.exe` | 공식 바이너리 백업 (복원용) |
| `C:\Users\jky72\.wezterm.lua`, `wezterm-galaxy\` | 이전 WezTerm 자산 (미사용) |
| `C:\Users\jky72\milkyway.hlsl` | 이전 Windows Terminal 셰이더 (미사용) |

---

## 6. 시도 이력 (왜 여기까지 왔나 — 짧게)

1. **Windows Terminal 픽셀 셰이더 → 폐기.** `Time` 참조 시 **강제 연속 전체창 리페인트**(PR #13903), 비활성 탭·최소화 창에서도 렌더(#15440), fps 제한 없음(#11581). 4K에서 8~9% GPU. **결정적 증거: 별 0개 셰이더가 같은 비용** → 비용은 그래픽이 아니라 리페인트 구조.
2. **WezTerm → 동작하지만 한계.** 셰이더 훅 없음(`BackgroundSource` = Gradient|File|Color, `BackgroundAttachment` = Fixed|Scroll|Parallax — 시간 기반 오프셋 부재). 애니메이션은 프리렌더 이미지 프레임뿐.
3. **par-term 채택.** 배경 셰이더 슬롯 + `max_fps` + `pause_shaders_on_blur`(기본 true) + `inactive_tab_fps`(기본 2).
4. **1차 셰이더**: "가늘고 희미한 대각선 은하수 띠" (`milkyway.glsl`, 이후 병행 에이전트가 `Astral Rift`로 튜닝).
5. **2차 셰이더(현재)**: **기울어진 나선은하**로 구도 교체 (`tilted-spiral.glsl`).

---

## 7. 실측 / 검증된 사실

### GPU 시간 (RTX 5090, 독립 OpenGL, 3840×2160, 워밍업 4회 + 측정 10회)

| 셰이더 | 중앙값 | p95 |
| --- | --- | --- |
| `tilted-spiral` (현재) | **0.541 ms** | 0.549 ms |
| 이전 `milkyway` (Astral Rift) | 0.437 ms | 0.441 ms |

목표 1.0 ms 이하. 캘리브레이션: 1000회 sin/cos 프로브가 4K에서 3.78 ms, 1080p에서 0.84 ms로 **픽셀 수에 정확히 비례**함을 확인 (moderngl `Query.elapsed`는 나노초).

### 정지 화면 통계 (4K, 현재)

완전 검정 **0.716** · 밝기 중간값 **0.0** · p95 **44.7** · p99 **118.4** · 최대 255

### 애니메이션 검증 (9항목 전부 통과)

| 검증 | 결과 |
| --- | --- |
| `iBrightness = 0` → 전 채널 0 | PASS |
| **강체 회전 불변성** | PASS — 정확한 각도로 워프 시 mean\|diff\| **1.249**, 틀린 각도 **5.206** |
| 핵이 중심에 밝은 점으로 유지 (0–900초) | PASS — peak luma 192×4 |
| **회전 후 별 형태** | PASS — 고립 별 전부 1×1/1×2/2×1/2×2 축정렬 사각형, 불량 0 |
| 1시간 회전 후 팔 밝기 | PASS — 평균 6.43 → 6.63 |
| **반짝임 끄면 400초 후 픽셀 완전 동일** | PASS — max\|diff\| **0** |
| **반짝임 켜도 별 픽셀 집합 불변** | PASS — 별 1227개, 다른 픽셀 0 |
| 반짝임이 실제로 밝기를 바꿈 | PASS — max\|diff\| 209 |
| 별이 빛을 빼지 않음 | PASS — min 0 |

### 참고 이미지 (사용자 제공, 목표 룩)

- **7번**: 기울어진 청색 원반은하 — 흰 코어, 청록 팔, 관통하는 암부, 칠흑 배경 (구도 목표)
- **2번**: 금빛 나선팔 + 보라 외곽 (색 대비 목표)
- **5번**: 깊고 어두운 여백 (음의 공간 목표)

---

## 8. 경험적으로 확인한 함정

1. **팔레트 램프의 0 지점은 순수 검정이어야 한다.** 남색으로 두면 밀도 0인 픽셀도 luma 6.8 → 원반 전체가 평평한 판이 된다. (완전 검정 비율 0.623 고정 + 원반 안 검정 픽셀 0개로 발견)
2. **중심부 로그 나선의 감김을 약화해야 한다.** 안 하면 팔이 중심에서 겹쳐 원반이 채워진 판이 된다.
3. **양자화 + 디더는 희미한 밀도를 증폭한다.** 단계 5면 한 단계가 0.2, 디더가 ±0.275단계라 밀도 0.05가 밝기 0.2로 올라간다.
4. **밝기를 낮추면 색도 변한다.** 롤오프를 세게 걸면 코어의 v가 낮아져 팔레트 웜 램프 중간(탁한 갈색)으로 내려간다.
5. **균일한 헤일로는 배경을 죽인다.** 완전 검정 0.743 → 0.445로 무너짐. 헤일로 노이즈에 smoothstep을 걸어 ~30%를 0으로 만들어야 검정이 산다.
6. **셰이더 수정 후 par-term 캐시**: 배경 이미지가 아니라 셰이더라 즉시 반영되지만, 확실히 하려면 재시작.
7. **새 필드를 추가하면 "별만 보는" 테스트를 같이 고쳐야 한다.** 가스 성운 추가 후 테스트를 방치했더니 회전하는 가스가 별 마스크에 섞여 별 사각형/정지 별밭 검증이 동시에 실패했다(마스크 1,227 → 376,426개).
8. **par-term은 float 컨트롤을 16개까지만 노출.** 초과분은 조용히 잘리고 lint 경고가 난다. int는 별도 예산.

---

## 9. 지금 개선하고 싶은 것 (← 상담받고 싶은 부분)

현재 결과는 "기울어진 나선은하"로 읽히고 검증도 통과했지만, **실제 은하 사진 같은 자연스러움**에는 아직 부족해.

### 현재 약점 (내가 보는 것)

1. **팔이 여전히 "매끈한 리본"** — 끊기고 갈라지고 다시 이어지는 별구름이라기엔 연속적. 팔에서 뻗어나오는 **가지(spur)** 가 없다.
2. **성단(cluster)이 안 보인다** — 별이 팔에 고르게 뿌려져 있음. 실제 은하는 산개성단이 덩어리로 보인다.
3. **팽대부가 밝은 덩어리** — 3D 느낌은 났지만 내부 구조(먼지 띠가 교차하는 층)가 단조롭다.
4. **암부가 "그어진 선"** — 필라멘트가 갈라지거나 사라지는 자연스러움이 부족.
5. **색 대비가 약하다** — 참고 2번의 금빛↔보라 대비만큼 강렬하지 않음.
6. **원반 외곽이 급히 사라진다** — 실제 은하는 아주 희미한 외곽 확장이 있다.

### 구체적으로 묻고 싶은 것

1. **팔 구조**: 지금은 단일 로그 나선 + 위상 노이즈야. 가지가 뻗고 끊기는 구조를 얻으려면?
   (a) 팔 위상을 노이즈로 디스플레이스먼트, (b) 팔을 여러 개의 짧은 세그먼트로 쪼개기,
   (c) 참고 코드처럼 **겹친 회전 타원**(`applyEllipse`)으로 밀도장 만들기 — 어느 접근이 유리한가?
2. **성단 표현 (가장 큰 고민)**: 별은 **셀당 최대 1개** 격자에 있고, 셀 크기가 최소 간격을 강제한다.
   픽셀 격자를 깨지 않고 **산개성단처럼 덩어리지는** 방법? (예: 굵은 셀에서 밀도를 정하고 작은 셀에서 위치를 정하는 2단 구조)
3. **팽대부 구조**: 먼지 띠가 팽대부를 비스듬히 교차하는 층 구조를 어떻게 만들까? (팽대부를 별도 타원체로 두고 그 안에 암부를 한 겹 더? )
4. **암부 자연스러움**: 지금은 팔 중심선에서 오프셋된 가우시안 2줄 × fbm. 더 유기적으로 만들려면?
5. **미세 별 밀도와 픽셀 크기**: 4K에서 `iStarCellPx=7`이면 별이 성기게 느껴질 수 있다. 밀도를 올리면서 성단과 구분되게 하는 법?
6. **성능 예산**: 현재 0.54 ms. **1.0 ms 이하**를 유지하면서 위 기능을 넣으려면 어디를 재사용해야 하나?
   (지금은 픽셀당 fbm 4회 + 별 후보 9개 순회)
7. **색**: 참고 이미지의 "샴페인 금빛 내부 ↔ 청록·남보라 외곽" 대비를 더 강하게 하려면? 지금은 두 램프를 `warm = exp(-(rn/0.36)^1.7)`로 섞는데, 반경 외에 **팔/암부 위치에 따른 색 분화**도 넣어야 할까?

### 제약 (반드시 지킬 것)

- 픽셀아트 하드엣지 (별 1×1/2×2, AA 금지)
- 칠흑 배경 유지 (완전 검정 비율을 크게 떨어뜨리면 안 됨)
- float 컨트롤 16개 + int 5개 한계
- 텍스트가 위에 샤프하게 합성되므로 **가독성**도 고려
- 절차적 생성만 (이미지 텍스처 금지)

---

## 10. 부록 — 셰이더 전체 소스

파일: `C:\Users\jky72\par-term\galaxy-work\shaders\tilted-spiral.glsl` (471줄)

```glsl
/*! par-term shader metadata
name: Tilted Spiral Galaxy
author: pi
description: Pixel-art tilted spiral galaxy. Hard integer-pixel stars, dithered clouds, dark dust lanes, slow rigid rotation.
version: 1.0.0
safety_badges:
  - battery_friendly
defaults:
  animation_speed: 1.0
  brightness: 1.0
  text_opacity: 1.0
  full_content: false
  auto_dim_under_text: false
  uniforms:
    iCenterX: 0.62
    iCenterY: 0.58
    iScale: 0.62
    iPositionAngle: -25.0
    iInclination: 0.48
    iWinding: 2.6
    iArmWidth: 0.27
    iCoreGain: 0.80
    iCloudGain: 0.64
    iDustStrength: 0.66
    iGasGain: 0.22
    iStarDensity: 0.5
    iStarGain: 1.0
    iSkyDensity: 0.22
    iOrbitSpeed: 0.015
    iTwinkle: 0.55
    iCloudPixel: 3
    iPaletteSteps: 10
    iQuality: 1
    iSeed: 7
    iStarCellPx: 7
*/

const float TAU = 6.28318530718;
const float PI  = 3.14159265359;
const float DEG = 0.01745329252;
// The bulge is measured with a rounder metric than the disk, so the core reads
// as a spheroid sitting in the disk rather than a flat patch of it.
const float CORE_ROUND = 2.10;
const float ARM_ASYM = 0.55;
const float CLUSTER_AMOUNT = 0.60;

// ==================================================================== controls
// control slider min=0 max=1 step=0.005 label="Galaxy Center X"
uniform float iCenterX;
// control slider min=0 max=1 step=0.005 label="Galaxy Center Y"
uniform float iCenterY;
// control slider min=0.08 max=1.2 step=0.005 label="Galaxy Scale"
uniform float iScale;
// control slider min=-90 max=90 step=0.5 label="Position Angle (deg)"
uniform float iPositionAngle;
// control slider min=0.12 max=1 step=0.01 label="Inclination (minor/major)"
uniform float iInclination;
// control slider min=0.6 max=6 step=0.02 label="Spiral Winding"
uniform float iWinding;
// control slider min=0.03 max=0.5 step=0.005 label="Arm Width"
uniform float iArmWidth;
// control slider min=0 max=2 step=0.01 label="Core Gain"
uniform float iCoreGain;
// control slider min=0 max=2 step=0.01 label="Cloud Gain"
uniform float iCloudGain;
// control slider min=0 max=1 step=0.01 label="Dust Strength"
uniform float iDustStrength;
// control slider min=0 max=1.5 step=0.01 label="Gas Nebula Gain"
uniform float iGasGain;
// control slider min=0 max=1.5 step=0.01 label="Star Density"
uniform float iStarDensity;
// control slider min=0 max=3 step=0.01 label="Star Gain"
uniform float iStarGain;
// control slider min=0 max=0.5 step=0.005 label="Sky Star Density"
uniform float iSkyDensity;
// control slider min=0 max=0.2 step=0.001 label="Orbit Speed (rad/s)"
uniform float iOrbitSpeed;
// control slider min=0 max=1 step=0.01 label="Twinkle"
uniform float iTwinkle;

// control int min=1 max=8 step=1 label="Cloud Pixel Size"
uniform int iCloudPixel;
// control int min=2 max=10 step=1 label="Palette Steps"
uniform int iPaletteSteps;
// control int min=0 max=2 step=1 label="Quality"
uniform int iQuality;
// control int min=0 max=64 step=1 label="Seed"
uniform int iSeed;
// control int min=5 max=16 step=1 label="Star Cell (px)"
uniform int iStarCellPx;

// ==================================================================== hashes
float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
    float n = hash21(p);
    return vec2(n, hash21(p + n * 37.19));
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// octaves are driven by iQuality so the cost lever has no extra code path
float fbm(vec2 p, int octaves) {
    float s = 0.0;
    float a = 0.5;
    for (int i = 0; i < 3; i++) {
        float use = step(float(i) + 0.5, float(octaves));
        s += a * use * vnoise(p);
        p = p * 2.07 + 13.3;
        a *= 0.5;
    }
    return s * 1.1428571;
}

vec2 rot2(float a) {
    float c = cos(a);
    float s = sin(a);
    return vec2(c, s);
}

vec2 rotv(vec2 v, float a) {
    float c = cos(a);
    float s = sin(a);
    return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// smallest absolute distance on a circle of the given period
float arcDist(float angle, float period) {
    float m = angle - period * floor(angle / period);
    return min(m, period - m);
}

// ==================================================================== transforms
// Screen pixel space is normalised by the screen HEIGHT so the composition does
// not distort with the window aspect ratio.
// Screen -> position-angle-aligned face-on axes (inclination not applied yet).
vec2 screenToFaceOn(vec2 sx, vec2 ctr, float H, float pa) {
    vec2 p = (sx - ctr) / H;
    return rotv(p, -pa);
}

// Face-on axes -> rotating disk frame. inclScale > 1 makes the shape rounder.
vec2 faceToDisk(vec2 q, float ang, float inclScale) {
    vec2 D = vec2(q.x, q.y / max(iInclination * inclScale, 0.04));
    return rotv(D, -ang);
}

vec2 screenToDisk(vec2 sx, vec2 ctr, float H, float pa, float ang) {
    return faceToDisk(screenToFaceOn(sx, ctr, H, pa), ang, 1.0);
}

vec2 diskToScreen(vec2 d, vec2 ctr, float H, float pa, float ang) {
    vec2 D = rotv(d, ang);
    vec2 q = vec2(D.x, D.y * max(iInclination, 0.05));
    vec2 p = rotv(q, pa);
    return p * H + ctr;
}

// ==================================================================== galaxy fields
// The winding is softened near the centre. An unmodified log spiral wraps so
// tightly there that the arms overlap into a filled plate instead of spirals.
float armPhase(float rn, float th) {
    return th - iWinding * log(max(rn, 0.30));
}

// Perpendicular distance to the nearest arm centreline, in normalised-radius units.
float armArc(float rn, float ph) {
    return arcDist(ph, PI) * rn;
}

// Arms fade in above the bulge and fade out at the disk edge, so no flat plate
// of arm light is left behind anywhere.
float armEnvelope(float rn) {
    return smoothstep(0.10, 0.42, rn) * (1.0 - smoothstep(0.92, 1.22, rn));
}

float armProfile(float rn, float ph, float widthScale) {
    float w = iArmWidth * widthScale * (0.55 + 0.95 * rn);
    float arc = armArc(rn, ph);
    return exp(-pow(arc / max(w, 0.004), 2.0)) * armEnvelope(rn);
}

// Analytic (cheap) density used for STAR EXISTENCE. It is a function of the
// star's own disk position, which never changes with time, so stars do not
// switch on and off as the galaxy rotates.
float starDensityAt(vec2 d) {
    float rn = length(d) / max(iScale, 0.02);
    if (rn > 1.35) { return 0.0; }
    float th = atan(d.y, d.x);
    float ph = armPhase(rn, th);
    float armId = step(PI, ph - TAU * floor(ph / TAU));
    float gain = 1.0 - armId * 0.55;
    float arm = armProfile(rn, ph, 1.0) * gain;
    float bulge = exp(-pow(rn / 0.22, 1.5));
    float nucleus = exp(-pow(rn / 0.075, 2.0));
    float d0 = mix(0.45, 1.0, vnoise(d * (11.0 / max(iScale, 0.02))));
    return clamp((arm * 0.95 + bulge * 0.55 + nucleus * 0.9) * d0 * iStarDensity, 0.0, 1.0);
}

// Colour ramps. Outer disk is cyan/blue, the inner disk is champagne gold.
vec3 rampCool(float v) {
    vec3 a = vec3(0.0);
    vec3 b = vec3(0.045, 0.150, 0.420);
    vec3 c = vec3(0.190, 0.560, 0.760);
    vec3 d = vec3(0.620, 0.930, 0.980);
    vec3 o = mix(a, b, smoothstep(0.06, 0.52, v));
    o = mix(o, c, smoothstep(0.45, 0.80, v));
    o = mix(o, d, smoothstep(0.76, 1.00, v));
    return o;
}

vec3 rampWarm(float v) {
    vec3 a = vec3(0.0);
    vec3 b = vec3(0.420, 0.290, 0.180);
    vec3 c = vec3(0.900, 0.790, 0.590);
    vec3 d = vec3(1.000, 0.975, 0.910);
    vec3 o = mix(a, b, smoothstep(0.06, 0.52, v));
    o = mix(o, c, smoothstep(0.45, 0.80, v));
    o = mix(o, d, smoothstep(0.76, 1.00, v));
    return o;
}

// ==================================================================== stars
vec3 starColour(float m) {
    vec3 c1 = vec3(1.00, 0.66, 0.42);
    vec3 c2 = vec3(1.00, 0.90, 0.72);
    vec3 c3 = vec3(1.00, 1.00, 0.98);
    vec3 c4 = vec3(0.78, 0.92, 1.00);
    vec3 c = mix(c1, c2, smoothstep(0.00, 0.35, m));
    c = mix(c, c3, smoothstep(0.32, 0.72, m));
    c = mix(c, c4, smoothstep(0.70, 1.00, m));
    return c;
}

// Disk stars live on a grid that rotates rigidly with the galaxy, so a star
// keeps its identity, size and colour. Each candidate is transformed to screen
// space and snapped to a whole pixel, then drawn as an axis-aligned hard square.
vec3 diskStars(vec2 px, vec2 dExact, vec2 ctr, float H, float pa, float ang, float densGate) {
    if (densGate < 0.004) { return vec3(0.0); }

    float incl = max(iInclination, 0.15);
    // Cell width must exceed 2/inclination so that a 3x3 search cannot miss a
    // star whose square overlaps this pixel.
    float cellPx = max(float(iStarCellPx), 2.6 / incl);
    float cs = cellPx / H;

    vec2 cid = floor(dExact / cs);
    float seed = float(iSeed) * 13.0;

    vec3 acc = vec3(0.0);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 c = cid + vec2(float(i), float(j));
            vec2 rnd = hash22(c + seed);
            vec2 dStar = (c + rnd) * cs;

            vec2 sPos = diskToScreen(dStar, ctr, H, pa, ang);
            vec2 tl = floor(sPos);

            vec2 rel = px - tl;
            float occ = hash21(c + seed + 3.1);
            float m = hash21(c + seed + 23.3);
            float sz = 1.0 + step(0.88, m);
            float inside = step(0.0, rel.x) * step(rel.x, sz - 0.5)
                         * step(0.0, rel.y) * step(rel.y, sz - 0.5);

            float amp = pow(m, 2.6);
            float a = (0.28 + 0.72 * amp) * step(occ, densGate);
            // mild twinkle so disk stars pulse as well; identity, size and colour
            // are untouched, only the brightness breathes
            float dp = smoothstep(0.0, 1.0,
                        0.5 + 0.5 * sin(iTime * 2.3 + m * TAU + hash21(c + seed + 71.3) * TAU));
            float tw = 1.0 - 0.60 * iTwinkle * (1.0 - dp);
            acc += starColour(clamp(m * 0.7 + hash21(c + seed + 17.9) * 0.3, 0.0, 1.0))
                 * (a * tw * inside);
        }
    }
    return acc;
}

// Static background stars. Positions are fixed integer pixels on a screen grid
// and nothing drifts; each star only pulses, with its own phase and period, so
// the sky twinkles without ever moving. Hard 1x1 / 2x2 squares, no AA.
vec3 skyStars(vec2 px, float t, float dens, float cell, float seedOff, float brightScale) {
    vec2 cid = floor(px / cell);
    vec2 inCell = px - cid * cell;
    float seed = seedOff + float(iSeed);

    float occ = hash21(cid + seed);
    float m = hash21(cid + seed + 23.3);
    float sz = 1.0 + step(0.93, m);
    vec2 sp = floor(hash22(cid + seed + 3.7) * (cell - sz + 1.0));
    vec2 rel = inCell - sp;
    float inside = step(0.0, rel.x) * step(rel.x, sz - 0.5)
                 * step(0.0, rel.y) * step(rel.y, sz - 0.5);

    float amp = pow(m, 2.4);
    float a = (0.24 + 0.76 * amp) * brightScale * step(occ, dens);

    float phase = hash21(cid + seed + 41.7) * TAU;
    float rate = 0.30 + 1.70 * hash21(cid + seed + 57.1);
    // Smoothstep on the sine sharpens both extremes, so the twinkle reads as a
    // pulse instead of a slow fade. Depth is 0 at Twinkle 0 and 0.85 at 1.
    float pulse = smoothstep(0.0, 1.0, 0.5 + 0.5 * sin(t * rate + phase));
    float tw = 1.0 - 0.85 * iTwinkle * (1.0 - pulse);

    return starColour(clamp(m * 0.55 + 0.25, 0.0, 1.0)) * (a * tw * inside);
}

// ==================================================================== compose
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 px = floor(fragCoord);
    float H = max(iResolution.y, 1.0);
    vec2 ctr = vec2(iCenterX, iCenterY) * iResolution;
    float pa = radians(iPositionAngle);
    float ang = iOrbitSpeed * iTime;

    // Clouds are evaluated on a coarse block grid: that is what gives the
    // chunky dithered faces instead of a smooth airbrush.
    float blk = float(iCloudPixel);
    vec2 qpx = (floor(px / blk) + 0.5) * blk;
    vec2 qC = screenToFaceOn(qpx, ctr, H, pa);
    vec2 dC = faceToDisk(qC, ang, 1.0);
    vec2 dB = faceToDisk(qC, ang, CORE_ROUND);

    float rn = length(dC) / max(iScale, 0.02);
    float rnB = length(dB) / max(iScale, 0.02);
    float th = atan(dC.y, dC.x);
    float ph = armPhase(rn, th);
    float along = log(max(rn, 0.075));

    int oct = 2 + iQuality;

    vec3 col = vec3(0.0);

    if (rn < 1.45) {
        // ---- arm identity and asymmetry ----
        float armId = step(PI, ph - TAU * floor(ph / TAU));
        float asym = 1.0 - armId * ARM_ASYM;

        // ---- low frequency warp so the arms are not perfect spirals ----
        float warp = fbm(vec2(along * 2.2, 7.3 + float(iSeed)), oct) - 0.5;
        float phW = ph + warp * 0.55;

        float armA = armProfile(rn, phW, 1.0) * asym;

        // The arm centreline and width shimmer along its length so an arm never
        // reads as a smooth painted ribbon.
        float wob = fbm(vec2(along * 9.0, 3.7 + float(iSeed)), oct) - 0.5;
        armA = max(armA, armProfile(rn, phW + wob * 0.45, 1.0 + wob * 0.60) * asym * 0.92);
        // a third arm appears only in patches
        float armC = armProfile(rn, phW - 1.15, 0.8)
                   * smoothstep(0.42, 0.78, fbm(vec2(along * 3.4, 19.1), oct)) * 0.5;

        // ---- clusters: large-scale clumping along the arms ----
        float clus = mix(1.0, fbm(vec2(along * 6.5, phW * 2.4), oct) * 1.5, CLUSTER_AMOUNT);
        float clus2 = mix(1.0, fbm(vec2(along * 17.0, phW * 7.0 + 29.0), oct) * 1.35,
                          CLUSTER_AMOUNT * 0.70);
        clus *= clus2;

        // ---- dust: a lane hugging the inner edge of each arm ----
        float arc = armArc(rn, phW);
        float laneW = 0.045 + 0.075 * rn;
        float lane1 = exp(-pow((arc - 0.085 - 0.10 * rn) / laneW, 2.0));
        float lane2 = exp(-pow((arc - 0.235 - 0.16 * rn) / (laneW * 0.8), 2.0));
        float dustN = fbm(vec2(along * 7.5, phW * 3.1 + 41.0), oct);
        float dust = 1.0 - iDustStrength * clamp(lane1 + 0.6 * lane2, 0.0, 1.0)
                   * smoothstep(0.22, 0.72, dustN);
        // broad gaps that break the arms apart
        float gap = smoothstep(0.60, 0.94, fbm(vec2(along * 3.2, phW * 1.6 + 67.0), oct));
        armA *= 1.0 - 0.80 * gap;
        armC *= 1.0 - 0.80 * gap;

        // ---- bulge and nucleus: measured with the rounder metric for volume ----
        float nucleus = exp(-pow(rnB / 0.075, 2.0));
        float bulge = exp(-pow(rnB / 0.24, 1.45));
        float mottle = mix(0.42, 1.05, fbm(vec2(along * 4.2, th * 2.6), oct));

        // ---- tighter inner spiral so the core has structure of its own ----
        float phIn = th - iWinding * 1.9 * log(max(rn, 0.13));
        float innerArm = armProfile(rn, phIn, 0.55)
                       * (1.0 - smoothstep(0.16, 0.52, rn)) * 0.85;

        // ---- H II / emission knots: compact bright clumps strung along the arms ----
        float knot = smoothstep(0.60, 0.93, fbm(vec2(along * 26.0, phW * 11.0 + 53.0), oct))
                   * clamp(armA * 0.9 + armC, 0.0, 1.0);

        // A broad, smoothly decaying disk so the galaxy reads as a luminous
        // plate that fades into black, not a hard-edged shape. The zero point of
        // the palette ramps is pure black, so low density really does go black.
        float disk = exp(-pow(rn / 0.62, 1.8)) * 0.55;

        float dens = nucleus * 1.15 * iCoreGain
                   + bulge * 0.34 * iCoreGain * mottle
                   + disk * iCloudGain * (0.45 + 0.55 * clus)
                   + innerArm * iCloudGain * 0.75
                   + (armA * 0.95 + armC) * iCloudGain * clus;
        dens *= dust;

        // A soft floor stops the faint tails of the arms from being lifted into
        // the first palette step, which used to flatten the disk into a plate.
        float v = smoothstep(0.030, 0.80, clamp(dens, 0.0, 1.4));
        // Soft highlight roll-off. A real galaxy does not have a large flat white
        // nucleus, so the top end is compressed instead of clipping to white.
        v = v / (1.0 + 0.45 * v * v);

        // ---- limited palette + non-repetitive dither ----
        float steps = float(iPaletteSteps);
        float dith = (hash21(px * 1.37 + float(iSeed)) - 0.5) * (0.22 / steps);
        float vq = floor(v * steps + 0.5 + dith * steps) / steps;
        vq = clamp(vq, 0.0, 1.0);

        // ---- inner warm / outer cool ----
        float warm = exp(-pow(rn / 0.36, 1.7));
        vec3 cold = rampCool(vq);
        vec3 hotv = rampWarm(vq);
        col = mix(cold, hotv, warm);

        // faint unresolved glow: a broad, textured halo so the disk reads as a
        // cloud of unresolved light rather than a hard-edged shape. The smoothstep
        // on its own noise punches holes, so true black still survives between
        // the wisps instead of the whole disk getting a flat wash.
        float haze = fbm(vec2(along * 4.6, phW * 2.7 + 89.0), oct);
        float halo = smoothstep(0.42, 0.88, haze)
                   * exp(-pow(rn / 0.66, 2.0))
                   * (0.50 + 0.50 * dust);
        col += mix(vec3(0.008, 0.016, 0.045), vec3(0.045, 0.032, 0.016), warm) * (v * v);
        col += mix(vec3(0.055, 0.105, 0.235), vec3(0.235, 0.170, 0.130), warm)
             * (halo * iCloudGain * 0.30);

        // emission knots are added as colour rather than as a brightness lift,
        // so they read as bright compact clumps on top of the arms
        vec3 knotCol = mix(vec3(0.52, 0.95, 1.00), vec3(1.00, 0.74, 0.64), warm);
        col += knotCol * (knot * iCloudGain * 1.25) * dust;

        // ---- translucent gas: a soft veil full of holes, so black shows through ----
        float gasN = fbm(vec2(along * 3.2, phW * 1.9 + 71.0), oct);
        float gasHoles = fbm(vec2(along * 9.0, phW * 5.4 + 113.0), oct);
        float veil = smoothstep(0.34, 0.86, gasN) * (1.0 - smoothstep(0.30, 0.82, gasHoles));
        // the veil hugs the arms and fades well before the region boundary, so it
        // can never become a flat oval of light covering the whole frame
        float veilShape = (0.12 + 0.88 * clamp(armA + armC, 0.0, 1.0))
                        * (1.0 - smoothstep(0.55, 1.10, rn));
        vec3 gasCol = mix(vec3(0.16, 0.22, 0.58), vec3(0.74, 0.40, 0.78), warm);
        col += gasCol * (veil * iGasGain * veilShape);
    }

    // ---- stars ----
    float densGate = starDensityAt(screenToDisk(px, ctr, H, pa, ang));
    col += diskStars(px, screenToDisk(px, ctr, H, pa, ang), ctr, H, pa, ang, densGate) * iStarGain;
    // Static background sky: two interleaved grids at different scales. Cell 23
    // and 47 do not share a common period, so no repeat pattern is visible.
    col += skyStars(px, iTime, iSkyDensity, 23.0, 411.0, 1.00) * iStarGain;
    col += skyStars(px, iTime, iSkyDensity * 0.45, 47.0, 907.0, 1.30) * iStarGain;

    col = min(col, vec3(1.0)) * iBrightness;
    fragColor = vec4(col, 1.0);
}
```
