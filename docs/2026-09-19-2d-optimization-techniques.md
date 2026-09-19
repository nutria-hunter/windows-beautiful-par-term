# 2026-09-19 — 2D/풀스크린 최적화 기법 조사와 적용 결과

목표: AMD 내장그래픽에서 배경 셰이더가 GPU를 100% 포화시키지 않게 하면서 **현재 화질을 유지**.
(별개로 `power_preference: high_performance` 로 RTX 5090을 쓰면 내장은 0%가 된다 — `2026-09-19-igpu-low-power-and-scaled-variant.md`.)

## 조사한 기법과 판정

| 기법 | 출처 | 판정 |
| --- | --- | --- |
| 저해상도 렌더 + 업스케일 (FSR1 = EASU+RCAS; "naive 업스케일은 흐릿") | GPUOpen FSR1/CAS, Babylon.js FSR1 문서 | **적용**: 4K→정수 2배(1920×1080) 축소 + `textureLoad` nearest |
| 텍스트는 네이티브 합성, 셰이더 좌표는 배율로 보정(`iReadability.zw`) | 구현 설계 | **적용**: 셰이더는 여전히 4K로 인식 → 픽셀 그리드/디더 유지, 글자 무손실 |
| 텍스처 캐싱("cache as texture": 안 변하는 레이어는 재렌더 안 함) | PixiJS `cacheAsTexture`, 정적 타일맵 프레임버퍼 캐시 | **적용**: 축소 배경 텍스처를 재사용해 애니메이션 30fps, 정지 시 1fps |
| CAS/FSR 샤프닝 | GPUOpen CAS/RCAS | **제외**: 이 아트워크는 의도된 디더+블록 그리드 → 정수배수+nearest가 정합적, 샤프닝은 블록 경계 증폭 |
| VRS(가변 셰이딩 레이트) | Intel Xe-LP 최적화 가이드 | **불가**: wgpu가 `VK_KHR_fragment_shading_rate` 미노출 |
| fp16 정밀도 | wgpu PR#5701, gpuweb#2524/#3524 | **보류**: `SHADER_F16` 요청 + 셰이더 변환 필요 |
| 정적 레이어 분리(패럴랙스) | 패럴랙스 레이어 기법 | **보류**: 단일 프로시저 셰이더 분해는 대공사, 잠재 이득 최대 |
| 단일 패스/오버드로 회피 | Intel 개발자 가이드 | 이미 준수(셰이더 1패스 + 합성 1패스) |

## 실측 (AMD Radeon 내장, 창 2360×1412, `power_preference: low_power`, 프로브가 포커스 상태)

| 구성 | 내장 3D 사용률 |
| --- | --- |
| 셰이더 끔(셀/egui만) | **6.6%** |
| 이전 빌드: 풀해상도 · 60fps | **97.0%** |
| 새 빌드: 0.5배 축소 · 30fps 스로틀 | **51.4%** |
| 새 빌드 + `custom_shader_animation: false`(1회/초 재렌더) | **13.5%** |

읽는 법:

- 앱 자체 바닥값 6.6% + 매 프레임 전체해상도 합성 ≈ 7% → **바닥 ~13.5%**
- 애니메이션 30fps·0.5배 상태에서 셰이더 몫 ≈ 38%
- 이전(60fps·풀해상도) 셰이더 몫 ≈ 90%

## 정직한 한계

픽셀 수 기준으로는 0.5배(4배) + 30fps(2배) = 8배를 기대했지만 **총 사용률은 1.9배 감소(97→51)** 에 그쳤습니다.
측정상 감소폭은 시간축(30fps) 몫과 일치하며, **공간축(해상도) 절감이 기대만큼 나타나지 않았습니다.**
남은 비용이 픽셀 수에 비례하지 않는다는 뜻이므로(예: 화면 미분 `fwidth` 기반 루프 반복 증가, 워프 발산, 프레임 단위 고정비),
다음 단계는 **프로파일링**(Radeon GPU Profiler 또는 `rocprof`)으로 실제 병목을 확정하는 것입니다.
그 전까지 확실한 선택지: ① 5090 사용(`high_performance`, 내장 0%) ② 정지 배경(`custom_shader_animation: false`, 13.5%) ③ `max_fps: 30`.

## 적용한 코드

- `par-term-render/src/custom_shader_renderer/scaled_background.rs` + `.wgsl` (축소 타깃 + 네이티브 합성)
- `par-term-render/src/custom_shader_renderer/mod.rs`: 축소 타깃 생성/합성 배선 + **배경 재사용 스로틀**
  (애니메이션 30fps·정지 1fps, 새 타깃 생성 시 즉시 재렌더, 직접 출력 경로는 무변경)
- `par-term-render/src/cell_renderer/mod.rs`: `Selected GPU: <이름> (<종류>, <백엔드>); preference=<설정>` 로그
