# 터미널 픽셀아트 은하수 배경 — 작업 브리핑

작성: pi (coding agent) / 용도: 기술 상담

---

## 1. 최종 목표 (하드 요구사항)

터미널 창 **뒤에 항상 떠 있는** 애니메이션 은하수 배경. 아래는 협상 불가.

1. **진짜 픽셀아트**: 별은 1x1 / 2x2 하드엣지 정사각형, 정수 픽셀에 스냅, **안티앨리어싱 금지**.
   둥글거나 부드러운 점은 명시적으로 거부됨.
2. **칠흑 배경** (#000000). 밴드는 **매우 희미하고 가늘게** ("희미하게", "은은하게").
   중심에 **약간의 웜 코어(은하 중심 팽대부)**.
3. 별은 **밴드 방향을 따라** 흐르고, **여러 개의 서로 다른 속도**(시차/parallax)를 가짐.
4. **타일 반복 격자가 보이면 안 됨**.
5. **GPU 비용 최소** — 게임/작업 중에도 부담이 없어야 함.
6. **영상 / GIF / 프리렌더 프레임 금지.** 진짜 절차적(per-pixel) 렌더링이어야 함.

---

## 2. 환경

- Windows 11 x64, 3840x2160 @ 120Hz, 시스템 DPI 100%
- RTX 5090 (dGPU) + AMD Radeon Graphics (iGPU)
- 도구: PowerShell 7, git bash, Python(Pillow + numpy), nvidia-smi

---

## 3. 시도 이력 (왜 현재 위치까지 왔는가)

### 3.1 Windows Terminal 픽셀 셰이더 — 폐기

- `experimental.pixelShaderPath` (HLSL). 파일: `C:\Users\jky72\milkyway.hlsl` (7,408 bytes)
- **구조적 문제**: 셰이더가 `Time` 상수를 참조하면 AtlasEngine이 **강제 연속 전체창 리페인트**를 함
  (microsoft/terminal PR #13903 "only enable continuous redraw if the shader needs it").
  비활성 탭과 최소화된 창에서도 계속 렌더링함 (issue #15440).
  fps 제한 옵션은 요청만 되고 미구현 (issue #11581).
- 4K에서 약 **8~9% GPU**.
- **결정적 증거**: 별을 **0개로 만든 셰이더**가 별 포함 버전과 **동일한 비용**이었음
  → 비용은 셰이더 연산이 아니라 "강제 전체창 리페인트" 구조에서 나옴.
  ALU 최적화(170 → 87 slots)는 11% 개선에 그침.
- 추가 확인: `experimental.pixelShaderImagePath`는 **존재하지 않음** (공식 스키마 grep 결과 0).
- 조치: `settings.json`에서 셰이더 제거 (현재 `pixelShaderPath` 항목 0개).
  백업: `.pi\tmp\settings.json.bak-*`

### 3.2 WezTerm — 동작했지만 구조적 한계

- `C:\Program Files\WezTerm\wezterm.exe` 버전 `20240203-110809-5046fc22`
- 설정: `C:\Users\jky72\.wezterm.lua` (6,766 bytes)
- 자산: `C:\Users\jky72\wezterm-galaxy\` (PNG 30개).
  생성기: `C:\Users\jky72\.pi\tmp\gen_band.py` (13,174 bytes)
- 구현: **4레이어 합성** — 정적 base(black+glow) / `band_far`(241px 타일) /
  `band_near`(256px 타일) / 정적 전체화면 overlay(3840x2160)
- 애니메이션: **APNG 프레임 duration에 속도를 baked** (33ms = 30fps). 근거리 60 px/s, 원거리 20 px/s
- **한계**: WezTerm에는 **셰이더 훅이 없음**. 소스 확인 결과
  `BackgroundSource` = `Gradient | File | Color`,
  `BackgroundAttachment` = `Fixed | Scroll | Parallax(f32)` — 시간 기반 오프셋이 존재하지 않음.
  애니메이션은 프리렌더 이미지 프레임의 재생이므로 매 프레임 전체창 재합성이 필요.
- **장점**: 창이 포커스를 잃으면 렌더를 완전히 멈춤
  (실측: 두 스크린샷 간 픽셀 변화 0.00%). 자체 GPU 점유 0.11%.
- 상태: `.wezterm.lua`와 자산은 남아 있으나 현재 사용하지 않음.

### 3.3 후보 조사 결과

- **Ghostty** — `custom-shader` (진짜 프래그먼트 셰이더 배경)가 있으나 **Windows 미지원**
  (1.3.0 릴리스 노트: Windows "still not planned").
- **Wintty** — Ghostty 코어를 Windows로 옮긴 것 (WinUI 3 + DirectX 12).
  "Terminal shaders" 기능과 브라우저 GLSL 플레이그라운드 제공.
  iResolution / iTime / iChannel0 / cursor 유니폼. 단 후원/Pro 티어 존재.
- **Rio 0.5.26** — RetroArch `.slang` 필터 체인 (librashader, wgpu 백엔드).
  전용 "배경 슬롯"이 아니라 후처리 필터 체인.
- **kitty** — 커스텀 셰이더 RFC #10344 (open). Windows 없음.
- **contour** — GPU 렌더링, Windows 지원. 커스텀 셰이더 기능은 불명확.
- **par-term** — 채택.

### 3.4 par-term 선택 이유

WT를 떠난 원인이었던 3가지를 **기본 제공**함:

| 문제 | par-term 설정 | 기본값 |
| --- | --- | --- |
| 프레임레이트 캡 | `max_fps` (+ `vsync_mode`) | 60 |
| 포커스 잃으면 셰이더 정지 | `pause_shaders_on_blur` | **true** |
| 비활성 탭 비용 | `inactive_tab_fps` / `unfocused_fps` | 2 / 30 |

---

## 4. 현재 구현

### 4.1 파일 경로 전체

| 종류 | 경로 | 크기 |
| --- | --- | --- |
| par-term 실행파일 | `C:\Users\jky72\par-term\par-term.exe` | 45,897,216 B (v0.45.0) |
| 설정 | `C:\Users\jky72\AppData\Roaming\par-term\config.yaml` | 14,309 B |
| 설정 원본 백업 | `C:\Users\jky72\AppData\Roaming\par-term\config.yaml.bak-orig` | 13,676 B |
| **은하수 셰이더** | `C:\Users\jky72\AppData\Roaming\par-term\shaders\milkyway.glsl` | 10,309 B / 288줄 |
| 번들 셰이더 73개 | `C:\Users\jky72\AppData\Roaming\par-term\shaders\` | 총 74개 .glsl |
| 이 브리핑 문서 | `C:\Users\jky72\par-term\docs\BRIEFING.md` | - |
| WT HLSL (미사용) | `C:\Users\jky72\milkyway.hlsl` | 7,408 B |
| WezTerm 설정 (미사용) | `C:\Users\jky72\.wezterm.lua` | 6,766 B |
| WezTerm 자산 (미사용) | `C:\Users\jky72\wezterm-galaxy\` | PNG 30개 |
| WezTerm 생성기 | `C:\Users\jky72\.pi\tmp\gen_band.py` | 13,174 B |
| 렌더 검증 도구 | `C:\Users\jky72\.pi\tmp\zoomcrop.py` | 433 B |
| 성능 측정 스크립트 | `C:\Users\jky72\.pi\tmp\parterm_perf.ps1` | 2,754 B |
| 테스트 스크린샷 | `C:\Users\jky72\par-term\*.png` | 13개 |

### 4.2 par-term 셰이더 계약

- GLSL. 진입점 `void mainImage(out vec4 fragColor, in vec2 fragCoord)`.
  WGSL로 자동 트랜스파일.
- Shadertoy 호환. **단 `iResolution`이 `vec2`** 이고 종횡비는 별도 `float iResolutionZ`
  (Shadertoy의 `vec3 iResolution`과 다름).
- **`fragCoord`는 물리 픽셀**.
  검증: 4K 전체화면 스크린샷이 3827x2114로 나옴 → 1px 별 = 물리 1픽셀. (1:1 매핑 요구사항 충족)
- `custom_shader_full_content: false` (기본) = **셰이더 출력이 배경이고 텍스트가 그 위에 샤프하게 합성**됨.
- **`iBrightness`는 앱이 자동 적용하지 않음** → 셰이더가 직접 곱해야 함.
  A/B로 확인: 설정 0.15와 1.0이 **완전히 동일한 프레임**을 생성.
  번들 73개 중 스스로 적용하는 것은 2개뿐.
- 튜너블 노출: `// control slider min= max= step= label="..."` 를 uniform 선언 **바로 앞**에.
  기본값은 metadata `defaults.uniforms` 에 (컨트롤 주석이 아니라).
- **float 컨트롤 16개 제한** — 초과분은 조용히 잘리고 lint 경고가 나옴.
  `uniform int` 컨트롤은 별도 예산.

### 4.3 핵심 기법 — 픽셀아트를 어떻게 보장하는가

1. **별 배치 = 셀 해시.** `cid = floor(ipx / cell)`, 셀마다 `hash22` 로 **정수 픽셀 오프셋**을 결정.
   셀당 최대 1개 별 → 셀 크기가 별 간 최소 거리를 강제.
2. **별 판정 = 정수 비교.** `step(0,rel) * step(rel, sz - 0.5)`.
   부동소수 경계 판정이 없으므로 **AA가 구조적으로 불가능**.
3. **크기는 정수** (1~3px), 등급(magnitude)과 상관됨 → 밝은 별이 더 큼.
4. **이동은 축별로 따로 floor 한 정수 오프셋.**
   `off = vec2(floor(t*sx), floor(t*sy))` → 별이 정수 격자에 붙은 채 1px씩 이동 → 뭉개짐 없음.
   (비정수 방향벡터를 쓰면 격자가 깨짐)
5. **타일 없음.** 절차적 무한 해시장이므로 반복 격자 문제가 원천적으로 존재하지 않음.

### 4.4 밴드 구조

- **각도를 화면 기준 도(degree)로 지정** → uv 기울기 = `tan(angle) * W/H`.
  이렇게 해야 창 종횡비가 달라도 각도가 유지됨.
- 밴드 평면 = 포물선: `v = 0.5 + slope*(u-0.5) + curve*(u-0.5)^2`
- 거리를 `cosT = 1/sqrt(1+slope^2)` 로 보정해 **밴드 수직 두께** 기준으로 정규화
  (안 하면 각도가 급할수록 밴드가 얇아 보임).
- **2성분 프로파일**: 좁은 inner lane(시그마 0.42) + 넓은 outer arm(시그마 0.82)을
  서로 오프셋해서 겹침 → 단일 평면 스트라이프가 아니라 **층 구조**로 읽힘.
- **star clouds**: `fbm3` 저주파로 밴드를 따라 길게 늘어진 밝은 덩어리 (해상되지 않은 별빛).
- **great rift**: `fbm3` + 가우시안 윈도우로 밴드 평면에 붙은 암부 필라멘트.
- **웜 코어**: `coreBulge(u) = exp(-((u-0.5)/width)^2)` →
  밴드 폭 확장 + cool→warm 색 혼합 + 별 밝기 부스트.

### 4.5 별

- **4개 레이어**: near(60 px/s, 셀 9px) / mid(34.8 px/s, 셀 7px) / far(20 px/s, 셀 6px) /
  sky(정적, 셀 22px)
- 거리감: far x0.62, mid x0.82, near x1.0
- **흑체복사 근사 색 램프**(참고 코드에서 채택):
  m(0..1, 1=가장 밝음) → 깊은 주황 → 주황 → 온백 → 백 → 청백 (5개 앵커 smoothstep 블렌드)
  - 별별 랜덤 산포 25%를 섞어 4개 평면 구간처럼 보이지 않게 함
- 등급: `m = 1 - hash`, 밝기 `amp = pow(m, 3.0)` → 어두운 별 다수, 밝은 별 소수
- twinkle: `sin(iTime*1.7 + m*TAU)` — 위상은 별 해시
- sparkle: 밝고 큰 별에만 십자 (여전히 하드 픽셀, AA 없음)

### 4.6 파라미터 22개 (float 16 + int 6)

**float**

`iStarDensity` 0.45 · `iSkyDensity` 0.055 · `iStarGain` 1.0 · `iTwinkle` 0.35 · `iSparkle` 0.10 ·
`iNearSpeed` 60 · `iFarSpeed` 20 · `iSkySpeed` 0 · `iBandWidth` 0.052 · `iBandAngle` 32 ·
`iBandCurve` 0.10 · `iCoreWidth` 0.17 · `iCoreGain` 0.55 · `iGlowGain` 0.40 ·
`iCloudAmount` 0.75 · `iRiftAmount` 0.70

**int**

`iCellNear` 9 · `iCellMid` 7 · `iCellFar` 6 · `iCellSky` 22 · `iStarSize` 1 · `iMagSize` 1

### 4.7 설정 및 성능

```
custom_shader: milkyway.glsl
custom_shader_enabled: true
custom_shader_animation: true
custom_shader_brightness: 1.0
custom_shader_text_opacity: 1.0
custom_shader_full_content: false
max_fps: 60
vsync_mode: fifo
pause_shaders_on_blur: true
pause_refresh_on_blur: true
unfocused_fps: 30
inactive_tab_fps: 2
window_type: normal
```

- 사용자가 직접 체감 확인: **성능 문제 없음**.
- **측정 함정 (중요)**: `nvidia-smi utilization.gpu` 는 **유휴 다운클럭 때문에 부풀려짐**
  (측정 당시 SM 1072MHz / 49W 상태에서 14~15% 로 표시됨).
  진짜 지표는 **전력(W)** 과 **프로세스별 GPU 엔진 카운터**.
- 참고: WezTerm 자체 점유 0.11%(비포커스), WT 셰이더 8~9%(4K).

---

## 5. 실측으로 검증된 사실

| 항목 | 결과 |
| --- | --- |
| 별 픽셀 형태 | 4K에서 1x1 / 2x2 **하드 사각형, AA 없음** (NEAREST 8배 확대 확인) |
| 흐름 방향 | 상호상관 실측 **32.2도 vs 설정 32.0도** → 밴드와 나란히 흐름. 속도 60px/s 일치 (약 118px / 2s) |
| 배경 밝기 | **중간값 0.0** (칠흑), p99 7.3, 최대 255 |
| 번들 `galaxy.glsl` | 중간값 **14.5**, 최대 51.2 → 화면 전체가 보라 안개. **칠흑 배경 없음** |
| 번들 `solarized_nebula.glsl` | 중간값 **41.7**, 최대 65.8 → 훨씬 밝은 청록 안개 |
| 번들 `galaxy.glsl` 의 별 | 부드러운 다중픽셀 얼룩 → **픽셀아트 아님** |
| `iBrightness` 자동 적용 | **없음** (0.15 vs 1.0 출력 완전 동일) |

---

## 6. 경험적으로 확인한 함정

1. par-term 은 float 컨트롤을 **16개까지만** 노출. 초과분은 조용히 잘림.
2. par-term 은 `custom_shader_brightness` 를 셰이더 출력에 **자동 적용하지 않음** → 직접 곱해야 함.
3. 번들 셰이더는 **전면 장식 씬**이지 배경이 아님 (칠흑 배경 없음, 캔버스 전체를 덮음).
4. `--exit-after` 가 `audio stream error: device no longer available` 와 함께 **멈출 수 있음**
   → 헤드리스 실행은 항상 `timeout N` 으로 감쌀 것.
5. 전체화면 테스트는 화면을 점유함 → **실패해도 반드시 `window_type` 을 복원**해야 함.
6. PowerShell 에 MSYS 경로(`/c/Users/...`)를 넘기면 해석 실패 (`path not found`).

---

## 7. 지금 상담받고 싶은 것

1. **밴드 형태의 사실성.** 현재는 포물선 평면 + fbm 윈도우. 더 유기적인 은하수 형태를 만들려면?
   참고 코드(Cewein, 2023)는 **겹친 회전 타원**(`applyEllipse`)으로 은하를 구성했음.
   - 나선팔 구조를 넣으려면 2D 나선 밀도 함수를 쓰는 게 맞나?
   - 밴드 중심선을 스플라인으로 두고 노이즈로 디스플레이스먼트하는 접근이 더 나을까?
2. **별 배치의 통계적 한계 (가장 큰 고민).**
   셀당 최대 1개 구조라서 **두 별의 최소 거리가 셀 크기(6~9px)로 강제됨.**
   실제 별밭에는 성단(cluster)과 이중성이 있는데, **픽셀 격자를 깨지 않으면서**
   클러스터링을 얻으려면? (예: 2단 셀 — 굵은 셀에서 밀도를 정하고 작은 셀에서 위치를 정하는 방식?)
3. **밀도 상한.** 셀당 1개 구조에서 별을 더 촘촘히 넣으려면 서로 다른 오프셋의 레이어를
   여러 장 겹치는 게 맞나? 아니면 더 나은 표준 기법이 있나?
4. **great rift(암부) 표현.** 지금은 fbm + 가우시안 윈도우. 더 자연스러운 방법?
5. **픽셀아트 별 렌더링의 대안.** 셀 해시 + 정수 판정 대신, 프리렌더 별 아틀라스 텍스처를
   nearest 샘플링하는 방식이 더 싸거나 더 예쁠까? (대신 색/크기 다양성이 제한될 것으로 예상)
6. **성능 구조.** 현재 픽셀당 4 레이어 x 해시 약 24회 + fbm 3회 x 3옥타브.
   4K 60fps 에서 최적인가? 더 싼 구조가 있나?
7. **색 램프의 물리적 타당성.** 5개 앵커 smoothstep 블렌드로 흑체복사를 흉내내는 게 합리적인가?
   더 정확하면서 저렴한 근사가 있나?
8. **가독성 정량 기준.** "터미널 텍스트 뒤 배경"으로서 밝기의 정량적 상한이 있나?
   (현재 중간값 0.0, p99 7.3, 최대 255)

---

## 8. 부록 — 셰이더 전체 소스

파일: `C:\Users\jky72\AppData\Roaming\par-term\shaders\milkyway.glsl`

```glsl
/*! par-term shader metadata
name: Milky Way (pixel art)
author: pi
description: Faint pixel-art Milky Way band. Hard 1x1/2x2 square stars, star clouds, great rift, warm core, black-body star colours.
version: 3.0.0
safety_badges:
  - battery_friendly
defaults:
  animation_speed: 1.0
  brightness: 1.0
  text_opacity: 1.0
  full_content: false
  auto_dim_under_text: false
  uniforms:
    iStarDensity: 0.45
    iSkyDensity: 0.055
    iStarGain: 1.0
    iTwinkle: 0.35
    iSparkle: 0.10
    iNearSpeed: 60.0
    iFarSpeed: 20.0
    iSkySpeed: 0.0
    iBandWidth: 0.052
    iBandAngle: 32.0
    iBandCurve: 0.10
    iCoreWidth: 0.17
    iCoreGain: 0.55
    iGlowGain: 0.40
    iCloudAmount: 0.75
    iRiftAmount: 0.70
    iCellNear: 9
    iCellMid: 7
    iCellFar: 6
    iCellSky: 22
    iStarSize: 1
    iMagSize: 1
*/

const float TAU = 6.28318530718;
const float DEG = 0.01745329252;

// ============================================================ controls (16 floats max)
// control slider min=0 max=1.5 step=0.01 label="Band Star Density"
uniform float iStarDensity;
// control slider min=0 max=0.4 step=0.005 label="Sky Star Density"
uniform float iSkyDensity;
// control slider min=0 max=3 step=0.01 label="Star Gain"
uniform float iStarGain;
// control slider min=0 max=1 step=0.01 label="Twinkle"
uniform float iTwinkle;
// control slider min=0 max=0.5 step=0.01 label="Sparkle Cross Chance"
uniform float iSparkle;
// control slider min=0 max=240 step=1 label="Near Speed (px/s)"
uniform float iNearSpeed;
// control slider min=0 max=240 step=1 label="Far Speed (px/s)"
uniform float iFarSpeed;
// control slider min=0 max=60 step=0.5 label="Sky Speed (px/s)"
uniform float iSkySpeed;
// control slider min=0.01 max=0.30 step=0.002 label="Band Thickness"
uniform float iBandWidth;
// control slider min=-80 max=80 step=0.5 label="Band Angle (deg from horizontal, + descends to the right)"
uniform float iBandAngle;
// control slider min=-0.6 max=0.6 step=0.005 label="Band Curve"
uniform float iBandCurve;
// control slider min=0.02 max=0.60 step=0.005 label="Core Width"
uniform float iCoreWidth;
// control slider min=0 max=1.5 step=0.01 label="Core Widening"
uniform float iCoreGain;
// control slider min=0 max=2 step=0.01 label="Glow Gain"
uniform float iGlowGain;
// control slider min=0 max=1 step=0.01 label="Star Clouds"
uniform float iCloudAmount;
// control slider min=0 max=1 step=0.01 label="Great Rift"
uniform float iRiftAmount;

// control int min=4 max=24 step=1 label="Near Cell (px)"
uniform int iCellNear;
// control int min=4 max=24 step=1 label="Mid Cell (px)"
uniform int iCellMid;
// control int min=4 max=24 step=1 label="Far Cell (px)"
uniform int iCellFar;
// control int min=8 max=48 step=1 label="Sky Cell (px)"
uniform int iCellSky;
// control int min=1 max=3 step=1 label="Base Star Size (px)"
uniform int iStarSize;
// control int min=0 max=2 step=1 label="Extra Size from Magnitude"
uniform int iMagSize;

// ============================================================ hashes
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

float fbm3(vec2 p) {
    float s = 0.0;
    float a = 0.5;
    for (int i = 0; i < 3; i++) {
        s += a * vnoise(p);
        p = p * 2.07 + 13.3;
        a *= 0.5;
    }
    return s * 1.1428571;
}

// ============================================================ band geometry
// The band angle is given in SCREEN degrees, so it looks the same at any
// window aspect. slopePx is dy/dx in pixels (positive = descends rightwards,
// i.e. enters at the top-left and leaves at the bottom-right).
float bandSlopePx() {
    return tan(clamp(iBandAngle, -80.0, 80.0) * DEG);
}

float slopeToUv() {
    return bandSlopePx() * (iResolution.x / max(iResolution.y, 1.0));
}

float bandPlane(float u) {
    float x = u - 0.5;
    return 0.5 + slopeToUv() * x + iBandCurve * x * x;
}

float coreBulge(float u) {
    float x = (u - 0.5) / max(iCoreWidth, 0.001);
    return exp(-x * x);
}

float bandHalfWidth(float u) {
    return iBandWidth * (1.0 + iCoreGain * coreBulge(u));
}

// Perpendicular-normalised signed distance. cosT makes the thickness measured
// across the band rather than vertically, so steep angles do not look thinner.
float bandSigned(float u, float v) {
    float sp = bandSlopePx();
    float cosT = inversesqrt(1.0 + sp * sp);
    return (v - bandPlane(u)) * cosT / max(bandHalfWidth(u), 0.0005);
}

// Two-component profile: a narrow inner lane plus a broad outer arm, offset
// from each other so the band reads as layered rather than one flat stripe.
float bandShape(float sd) {
    float inner = exp(-pow((sd + 0.10) / 0.42, 2.0)) * 0.85;
    float outer = exp(-pow((sd - 0.18) / 0.82, 2.0)) * 0.55;
    return clamp(inner + outer, 0.0, 1.0);
}

float cloudField(float u, float sd) {
    float n = fbm3(vec2(u * 2.0, sd * 1.6 + u * 1.3));
    return mix(1.0 - 0.65 * iCloudAmount, 1.0 + 0.55 * iCloudAmount, n);
}

float riftField(float u, float sd) {
    float fil = exp(-pow((sd - 0.06) / 0.34, 2.0));
    float n = fbm3(vec2(u * 3.0, sd * 1.5 + u * 0.8));
    return 1.0 - iRiftAmount * fil * smoothstep(0.22, 0.78, n);
}

vec3 bandGlow(float u, float sd, float cloud, float rift) {
    vec3 cool = vec3(0.046, 0.052, 0.086);
    vec3 warm = vec3(0.105, 0.078, 0.048);
    float b = coreBulge(u);
    float hue = fbm3(vec2(u * 1.6, 4.7));
    vec3 tint = mix(cool * 1.15, cool, hue);
    vec3 col = mix(tint, warm, clamp(b * (0.75 + 0.35 * hue), 0.0, 1.0));
    float g = bandShape(sd);
    // breaking the glow up with the cloud field makes it read as unresolved
    // starlight rather than one smooth gradient
    return col * (g * iGlowGain) * rift * mix(1.0, cloud, 0.80) * (0.55 + 0.90 * b);
}

// ============================================================ star colour
// Poor-man's black body: dim stars are deep orange, bright ones white-blue.
// A little per-star scatter keeps the ramp from looking like four flat bins.
vec3 starColour(float m) {
    vec3 c1 = vec3(1.00, 0.42, 0.22);
    vec3 c2 = vec3(1.00, 0.72, 0.45);
    vec3 c3 = vec3(1.00, 0.92, 0.78);
    vec3 c4 = vec3(1.00, 1.00, 1.00);
    vec3 c5 = vec3(0.74, 0.83, 1.00);
    vec3 c = mix(c1, c2, smoothstep(0.00, 0.35, m));
    c = mix(c, c3, smoothstep(0.30, 0.62, m));
    c = mix(c, c4, smoothstep(0.58, 0.82, m));
    c = mix(c, c5, smoothstep(0.78, 1.00, m));
    return c;
}

// ============================================================ pixel-art stars
// Membership is an exact integer test, so every star is a crisp NxN block of
// pixels: no anti-aliasing, no soft edges, no sub-pixel positions.
vec3 starLayer(vec2 px, vec2 off, float cell, float seed, float isBand, float dens, float cloudRift) {
    vec2 ipx = floor(px - off);
    vec2 cid = floor(ipx / cell);
    vec2 inCell = ipx - cid * cell;

    float rOcc = hash21(cid + seed);
    float m = 1.0 - hash21(cid + seed + 23.3);   // magnitude: 1 = brightest

    float sz = float(iStarSize);
    if (iMagSize >= 1 && m > 0.62) { sz += 1.0; }
    if (iMagSize >= 2 && m > 0.88) { sz += 1.0; }
    sz = min(sz, cell - 1.0);

    vec2 sp = floor(hash22(cid + seed + 3.7) * (cell - sz + 1.0));

    vec2 spos = cid * cell + sp + off;
    vec2 suv = (spos + 0.5) / max(iResolution.xy, vec2(1.0));

    float d;
    if (isBand > 0.5) {
        d = dens * bandShape(bandSigned(suv.x, suv.y)) * cloudRift;
    } else {
        d = dens;
    }

    vec2 rel = inCell - sp;
    float inside = step(0.0, rel.x) * step(rel.x, sz - 0.5)
                 * step(0.0, rel.y) * step(rel.y, sz - 0.5);

    float spark = 0.0;
    if (iSparkle > 0.0 && sz >= 2.0 && m > 0.80) {
        float crossOn = step(1.0 - iSparkle, hash21(cid + seed + 61.7));
        float mid = floor((sz - 1.0) * 0.5);
        float cx = sp.x + mid;
        float cy = sp.y + mid;
        float inAx = step(sp.x - 1.0, rel.x) * step(rel.x, sp.x + sz);
        float inAy = step(sp.y - 1.0, rel.y) * step(rel.y, sp.y + sz);
        float armH = inAx * step(abs(rel.y - cy), 0.5);
        float armV = inAy * step(abs(rel.x - cx), 0.5);
        spark = crossOn * clamp(armH + armV, 0.0, 1.0) * 0.45;
    }

    float alive = step(rOcc, d);

    vec3 col = starColour(clamp(m * 0.75 + hash21(cid + seed + 17.9) * 0.25, 0.0, 1.0));

    float amp = pow(m, 3.0);
    float coreBoost = 1.0 + 0.55 * coreBulge(suv.x) * isBand;
    float a = (0.22 + 0.78 * amp) * iStarGain * coreBoost;
    float tw = mix(1.0, 0.55 + 0.45 * sin(iTime * 1.7 + m * TAU), iTwinkle);

    float mask = clamp(inside + spark, 0.0, 1.0);
    return col * (a * tw) * (mask * alive);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 px = floor(fragCoord);
    vec2 uv = fragCoord / max(iResolution.xy, vec2(1.0));

    float sd = bandSigned(uv.x, uv.y);
    float cloud = cloudField(uv.x, sd);
    float rift = riftField(uv.x, sd);
    float cloudRift = cloud * rift;

    // Drift follows the band. The offset is floored to whole pixels on each
    // axis, so stars stay locked to the pixel lattice while they flow.
    float rise = bandSlopePx();
    float kNear = floor(iTime * iNearSpeed);
    float kMid = floor(iTime * iNearSpeed * 0.58);
    float kFar = floor(iTime * iFarSpeed);
    float kSky = floor(iTime * iSkySpeed);

    vec3 col = bandGlow(uv.x, sd, cloud, rift);
    col += starLayer(px, vec2(kFar, floor(kFar * rise)), float(iCellFar), 17.0, 1.0, iStarDensity * 0.80, cloudRift) * 0.62;
    col += starLayer(px, vec2(kMid, floor(kMid * rise)), float(iCellMid), 59.0, 1.0, iStarDensity * 0.92, cloudRift) * 0.82;
    col += starLayer(px, vec2(kNear, floor(kNear * rise)), float(iCellNear), 91.0, 1.0, iStarDensity, cloudRift);
    col += starLayer(px, vec2(kSky, floor(kSky * rise * 0.45)), float(iCellSky), 233.0, 0.0, iSkyDensity, 1.0) * 0.85;

    col = min(col, vec3(1.0)) * iBrightness;
    fragColor = vec4(col, 1.0);
}
```
