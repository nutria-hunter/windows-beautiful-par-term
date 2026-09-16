# 2026-09-15 — 배경 셰이더가 사라진 원인과 수정 (Vulkan 백엔드)

## 증상

par-term을 재시작하면 커스텀 배경 셰이더가 **아무것도 그려지지 않는다**. 셰이더는 정상 설치돼 있고
`config.yaml`의 `custom_shader_enabled: true`도 그대로인데 화면은 단색 배경만 나온다.

## 원인 (측정으로 확정)

1. 셰이더 **로드/검증은 성공**한다: 로그에 `Loaded custom shader (104824 bytes GLSL -> 287597 bytes WGSL)`,
   `custom_shader_loaded=true`, ERROR 0건.
2. 그런데 **파이프라인 컴파일이 끝나지 않는다**: 95초를 기다려도
   `[SHADER] pipeline compiled in background; shader is live`가 찍히지 않는다.
3. 백엔드를 바꿔 같은 파일로 대조:

| 백엔드 | transpile | 파이프라인 | 렌더 |
| --- | --- | --- | --- |
| DX12 | 0.56s | 19초+ 미완 | 빈 화면 |
| **Vulkan** | 0.74s | **4.95초** | 정상 |
| 기본값(Vulkan 우선) | — | **0.95초** | 정상 |

1. 같은 파일이 때때로 성공/실패로 갈리는 것도 관측(1회 실패 → 2회 성공) → 딱딱한 크기 한계가 아니라
   **DX12 경로의 컴파일 지연/타임아웃**이다. wgpu의 알려진 문제와 일치:
   - gfx-rs/wgpu#7443 `dx12 shader compilation is sometimes excessively slow`
   - gfx-rs/wgpu#2722 DX12 백엔드는 FXC(`d3dcompiler_47`)를 쓰며 "Extremely slow"
   - gfx-rs/wgpu#4456 naga 검증은 통과하는데 백엔드 컴파일러가 타임아웃
   - (참고) 함수 인자가 128스칼라를 넘으면 DXC 내부 오류 가능: gfx-rs/wgpu#8057

부수 원인: 파이프라인 실패가 **조용했다**. wgpu는 실패 시 워커 스레드에서 패닉하고,
`poll_pipeline`은 `Ok`만 처리해서 스레드가 죽어도 `pipeline = None`인 채 아무 로그도 남지 않았다.

## 수정

| 커밋 | 내용 |
| --- | --- |
| `6ed0908` | DX12 하드코딩 제거 → `Backends::from_env().unwrap_or(Backends::all())` (Vulkan 우선, DX12 폴백). 워커 스레드를 `catch_unwind`로 감싸 실패 메시지를 채널로 전달, 실패/스레드사망 로깅, 파이프라인 도착 시 재그리기 |
| `b323bc0` | `custom_shader_render_scale` 설정 추가(기본 1.0 = 기존 경로) — 4K/iGPU 대비 렌더 스케일 기반 |

## 지금 상태

- `release/par-term.exe` = sha256 `a0e1d3e8…` (위 두 커밋 포함)
- `config/shaders/kanagawa-starbound.glsl` = 104,824 bytes, `version: 6.1.0` (최신 기능 100%)
- 실행 확인: `pipeline compiled in background; shader is live` + 스크린샷 잉크 15%대
- 롤백: `par-term-prev-dx12.exe` (교체 시 백업), 셰이더 변형은 `galaxy-work/shaders/`

## 재현/검증 방법

```powershell
# 백엔드 확인(기본은 Vulkan 우선)
$env:WGPU_BACKEND = 'vulkan'   # 필요 시 명시
.\release\par-term.exe --log-level debug --screenshot out.png --exit-after 12
# 로그에 [SHADER] pipeline compiled in background 가 있으면 정상, 없으면 빈 화면
```

## 남은 작업

- **동적 렌더 해상도 스케일**: `docs/PLAN-render-scale.md` 참고(코드 훅·설정 키·검증 절차 확정).
  기준선 실측: 원본 최신본 4K **1.435ms/프레임** → 1/2 배율 ≈0.36ms.
- 되돌린 실험: PipelineCache 영속화(이 드라이버는 캐시 데이터를 주지 않고, 그 상태에서 빈 화면 회귀가 있어 롤백).
