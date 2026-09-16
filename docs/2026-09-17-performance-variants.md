# 2026-09-17 — 성능 개선 패스와 변형(shader variants) 라인업

## 무엇이 바뀌었나

- **구조물(structures) 연출 추가** — `kanagawa-starbound-before-structures-20260917.glsl`(104,824 B) 이후 작업
- **성능 최적화 패스** — `before-performance-20260917.glsl`(111,015 B) 이후 `-optimized`/`-eco`/`-igpu` 변형 생성
- 설치본(`config/shaders/kanagawa-starbound.glsl`)은 **최적화본과 동일**(111,103 B, `version: 6.1.0`)

## 실측 (4K, 독립 OpenGL 하네스, RTX 5090)

| 시점 | 셰이더 | GPU 중앙값 | p95 |
| --- | --- | --- | --- |
| 2026-09-15 | 원본 최신본(v6.1.0 계열, 104,824 B) | 1.435 ms | 1.447 ms |
| 2026-09-17 | 설치본(최적화본, 111,103 B) | **0.983 ms** | **0.987 ms** |

→ **약 31% 개선** (기능은 오히려 늘어난 상태에서).
측정 명령: `python galaxy-work/work/render_check.py <shader> tag=<tag>` (결과는 `galaxy-work/outputs/validation.json`).

## 변형 라인업 (설치 폴더에도 함께 배치)

| 파일 | 크기 | 용도 |
| --- | --- | --- |
| `kanagawa-starbound.glsl` | 111,103 B | **기본 = 최적화본** |
| `kanagawa-starbound-optimized.glsl` | 111,103 B | 위와 동일(이름만 명시) |
| `kanagawa-starbound-eco.glsl` | 111,089 B | 저전력 지향 |
| `kanagawa-starbound-igpu.glsl` | 108,721 B | **내장그래픽용 경량** |
| `kanagawa-starbound-before-structures-20260917.glsl` | 104,824 B | 구조물 추가 전 백업 |
| `kanagawa-starbound-before-performance-20260917.glsl` | 111,015 B | 최적화 전 백업 |

## 변형 전환 방법

```yaml
# %APPDATA%\par-term\config.yaml
custom_shader: kanagawa-starbound-igpu.glsl   # 또는 -eco / -optimized
```

저장 후 par-term 재시작(또는 셰이더 재선택). **백엔드는 Vulkan 우선**이어야 합니다(참고: `docs/2026-09-15-vulkan-backend-and-starbound.md`).

## iGPU 환산(개략)

5090 대비 5~20배 느리다고 보면: `-igpu` 변형이 0.98 ms의 절반 이하로 측정될 경우 4K 60fps(16.7 ms) 안에 여유 있게 들어옵니다.
추가로 **동적 렌더 스케일**(`docs/PLAN-render-scale.md`)을 적용하면 배율 1/2에서 프래그먼트 비용이 4배 줄어듭니다.
