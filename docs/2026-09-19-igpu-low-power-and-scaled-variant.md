# 2026-09-19 — 내장그래픽 100% · 렉의 진짜 원인(`power_preference`)과 `-scaled` 변형

## 증상

노트북에서 par-term이 **AMD Radeon 내장그래픽을 100%** 로 태우고 배경 셰이더가 렉을 유발.
RTX 5090은 놀고 있음.

## 원인 (실측으로 확정)

`%APPDATA%\par-term\config.yaml` 의 `power_preference: low_power`.
wgpu의 `PowerPreference::LowPower` 는 **하이브리드 시스템에서 내장그래픽을 선택**합니다.
즉 셰이더가 느린 게 아니라, 무거운 프래그먼트 셰이더가 **일부러 iGPU에서** 돌고 있었습니다.

측정 방법: 같은 바이너리를 16초 실행하면서 Windows GPU Engine 카운터의 **LUID별 3D 사용률**을 샘플링(디스플레이는 5090 = `luid_0x154ef`, 내장 = `luid_0x16a6a`).

| 설정 | 부하가 걸린 GPU | 내장그래픽 | 5090 |
| --- | --- | --- | --- |
| `low_power` (문제 상황) | 내장 `0x16a6a` | **61.7%** (실사용 시 100%) | 1.0% |
| `high_performance` | **5090 `0x154ef`** | **0.0%** | 3.7% |

같은 셰이더가 5090에서는 3.7%, 내장에서는 61.7% → **약 17배 차이**.
Windows 앱별 GPU 선호도(`HKCU\...\UserGpuPreferences` → `GpuPreference=2`)는 **효과 없음**(wgpu가 자체 preference로 어댑터를 고르므로). 설정 파일을 고쳐야 합니다.

## 해결

```yaml
# %APPDATA%\par-term\config.yaml
power_preference: high_performance   # low_power → 내장그래픽 강제 선택이 원인
```

par-term 재시작 후 반영. 배터리를 아껴야 할 때만 `low_power`로 되돌리고, 그때는 아래 경량 변형을 함께 쓰는 편이 좋습니다.

## 내장그래픽에서 써야 할 때의 권장 조합

| 항목 | 값 | 효과 |
| --- | --- | --- |
| `custom_shader` | `kanagawa-starbound-igpu.glsl` | 4K 기준 **0.431 ms** (기본 최적화본 0.983 ms 대비 **−56%**) |
| `max_fps` | `30` | 초당 프레임 절반 |
| `custom_shader_animation` | 필요 없으면 `false` | 배경 정지 = 거의 0 부하 |
| `power_preference` | `low_power` | 전력 절약(대신 위 변형 필수) |

## `kanagawa-starbound-scaled.glsl` (2026-09-19)

이름과 달리 **해상도 스케일링이 아니라** 작은 천체의 스프라이트 픽셀 풋프린트(`pixelFootprint`) 보정입니다(변경 14줄).
성능은 기본본과 동일: 4K **1.009 ms**(p95 1.259) vs 기본 최적화본 0.983 ms — 최적화 목적이면 `-igpu` 변형을 쓰세요.

## 참고 수치 (RTX 5090, 4K, 독립 OpenGL 하네스)

| 셰이더 | GPU 중앙값 | p95 |
| --- | --- | --- |
| 설치 기본(최적화본, 111,103 B) | 0.983 ms | 0.987 ms |
| `-igpu` (108,721 B) | **0.431 ms** | 0.568 ms |
| `-scaled` (111,370 B) | 1.009 ms | 1.259 ms |
| 9/15 원본(104,824 B) | 1.435 ms | 1.447 ms |
