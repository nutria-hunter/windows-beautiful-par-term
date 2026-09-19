# 2026-09-19 — 셰이더 내부 최적화: 기능별 비용 분해와 컬링

해상도·프레임을 낮추는 것은 부하를 줄일 뿐 최적화가 아니다. 같은 그림을 더 싸게 그리려면
**어디가 비싼지 먼저 재야** 한다. `galaxy-work/work/feature_cost.py` 가 후보 함수를 하나씩
`return` 으로 잘라내고 하네스로 GPU 시간을 잰다(`galaxy-work/outputs/feature-cost.json`).

## 기능별 비용 (RTX 5090, 4K, 기준 0.980 ms)

| 기능 | 그 기능을 없앴을 때 | 비중 |
| --- | --- | --- |
| `incursionEvent` (습격 편대 + 포격) | 0.588 ms | **39.9%** |
| `shipEvent` (함대 통과) | 0.686 ms | **29.9%** |
| `operaEncounter` | 0.831 ms | 15.1% |
| `stars` | 0.881 ms | 10.0% |
| `planet` | 0.902 ms | 7.9% |
| `warshipArt` | 0.912 ms | 6.9% |
| `cometPixel` | 0.954 ms | 2.6% |
| `cityPlanet` / `structureArt` / `asteroidGroup` / `infrastructure` | ≈0.98 ms | 측정 프레임에서 무료 |

개별 절감의 합(1.08 ms)이 기준을 넘는 것은 서로 호출하기 때문이다(습격이 함대·함선 아트를 부른다).

## 적용한 최적화 — 화면공간 컬링 2개

`warshipArt` 앞에는 이미 스프라이트 바운딩 컬이 있었다. 남은 낭비는 **픽셀과 무관한 계산을 매
픽셀 수행**하는 것이었다: 편대 전체가 화면의 좁은 띠/코리도 안에서만 움직이는데, 띠 밖 픽셀도
함선 9~18척의 위치·게이트·실드·볼트 계산을 전부 치렀다.

1. `incursionEvent`: 레이더 띠(`lane`)와 목표 행성/링을 감싸는 **가로 띠** 밖이면 함수를 즉시 반환.
2. `shipEvent`: `origin` 을 지나는 **편대 코리도**(측면 0.62 화면높이, 진행 -0.85~+0.35) 밖이면 즉시 반환.

둘 다 보수적 여유를 둔 비교 1~2회이므로 **그림이 바뀌지 않는다**.

## 결과

| 측정 | 값 |
| --- | --- |
| 하네스 GPU 시간 (4K) | 0.985 ms → **0.793 ms (−19.5%)** |
| 하네스 렌더 차이 | 평균 0.000/255, 최대 0, >8 차이 픽셀 0.0000% (**픽셀 동일**) |
| 실제 앱(AMD 내장) | `shader is live` ✓, 내장 3D 약 52% → **약 41%**, 화면 정상(성운·별·행성·함대·글자) |

파일: `shaders/opt-cull.glsl`(작업본) = 설치본 `%APPDATA%\par-term\shaders\kanagawa-starbound.glsl`
원본 백업: `kanagawa-starbound-before-culling-20260919.glsl`

## 다음 후보 (측정된 상한)

- **볼트 셋업 호이스팅**: 볼트의 시작점·방향·명중점은 (seed, ship, bolt, time)에만 의존하는데
  매 픽셀 계산된다 → 이벤트당 1회 계산 또는 픽셀 무관 계산 분리. 상한은 `incursionEvent` 40%.
- **노이즈 텍스처화**: 성운 fbm 옥타브를 미리 구운 텍스처 샘플로 대체(`stars` 10% + 성운 몫).
- **`operaEncounter` 15%**: 같은 코리도/타일 컬링 적용 여부 조사.
- **unroll 축소**(`shipEvent` 18×, `asteroidGroup` 26×): 컴파일 시간·레지스터 압박 감소.
- **fp16**(`SHADER_F16`): 레지스터·대역폭 절감.
