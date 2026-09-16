# B: 동적 렌더 해상도 스케일 — 구조 계획 (확정판)

작성 2026-09-15. 앞선 `PLAN-render-scale.md`를 코드 확인 결과로 **구체화**한 확정 계획.
이 문서 하나로 다음 세션이 구현을 바로 시작할 수 있게 하는 것이 목적이다.

## 목표

배경 커스텀 셰이더를 창 크기에 맞춰 **낮은 해상도로 렌더**하고 **nearest 업스케일**로 합성 →
프래그먼트 비용 4~16배 절감. 텍스트는 기존 경로(`custom_shader_full_content=false`)로 네이티브 합성이라
**글자 선명도 무영향**.

기준선(원본 최신본, 4K, RTX 5090): **1.435ms/프레임**(p95 1.447) → 1/2 배율 ≈0.36ms, 1/4 ≈0.09ms.
iGPU(5090 대비 5~20배)에서 4K 60fps(16.7ms) 확보가 목적.

## 확인된 코드 구조 (2026-09-15 실측)

| 위치 | 사실 |
| --- | --- |
| `par-term-render/src/custom_shader_renderer/mod.rs` `render_with_clear_color()` | 유니폼 빌드 → `queue.write_buffer` → 자체 `CommandEncoder` → `output_view`로 렌더 패스(`LoadOp::Clear(clear_color)`) |
| `custom_shader_renderer/uniforms.rs:31,74,127` | **`iResolution` = `self.texture_width/height`** 에서 만들어짐 (즉 이 두 필드를 잠시 바꾸면 셰이더가 작은 화면으로 인식) |
| `custom_shader_renderer/textures.rs:390` `resize(device,width,height)` | `texture_width/height` 갱신 + 중간 텍스처 재생성 |
| `par-term-render/src/renderer/rendering.rs:365` | `custom_shader.render_with_clear_color(device, queue, content_view, apply_opacity, clear_color)` 호출 (여기 손대지 않고 모듈 내부에서 처리 가능) |
| WGSL 포함 방식 | `include_str!` 로 각 파이프라인에서 직접 include (예: `cell_renderer/*.rs`) → **새 `.wgsl` 파일 추가만으로 확장 가능**, build.rs 수정 불필요 |
| `src/app/window_state/renderer_init.rs` `RendererInitParams` | `custom_shader_enabled`, `custom_shader_brightness`, `custom_shader_full_content` … 설정값이 여기로 모임 → 여기에 `custom_shader_render_scale` 추가 |
| `par-term-config/.../global_shader_config.rs` | **이미 추가됨**: `custom_shader_render_scale: f32` (기본 1.0, `crate::defaults::shader_render_scale()`) |

## 구현 4단계 (각 단계마다 빌드 + 렌더 검증)

### 1단계 — 설정 키 (완료 ✅)

- `global_shader_config.rs` 필드 + Default, `defaults/misc.rs`의 `shader_render_scale()`, `defaults/mod.rs` 재export
- 검증: 빌드 성공, 기본값 1.0에서 렌더 회귀 없음(live, 잉크 15.03%)

### 2단계 — 스케일 렌더 타깃

`CustomShaderRenderer`에 추가:

```rust
pub(crate) render_scale: f32,                        // clamp(0.25, 1.0)
pub(crate) scale_target: Option<(Texture, TextureView)>,
pub(crate) scale_size: (u32, u32),
```

`render_with_clear_color` 안에서:

```rust
let scaled = self.render_scale.clamp(0.25, 1.0) < 0.999;
let (real_w, real_h) = (self.texture_width, self.texture_height);
let target_view = if scaled {
    let sw = ((real_w as f32 * self.render_scale).round() as u32).max(1);
    let sh = ((real_h as f32 * self.render_scale).round() as u32).max(1);
    if self.scale_size != (sw, sh) { /* 재생성 */ }
    // 셰이더가 작은 화면이라고 인식하도록 유니폼용 크기를 잠시 교체
    self.texture_width = sw; self.texture_height = sh;
    self.scale_target.as_ref().unwrap().1.clone()
} else { output_view.clone() };
let _ = scaled;  // 유니폼 write 후 self.texture_width/height 원복
```

- 유니폼 write는 함수 초반에 이미 일어나므로, **write 직전에 교체 → 직후 원복**하면 다른 소비자(mouse, cursor area, auto-dim)에 영향 없음.

### 3단계 — nearest 업스케일 블리트

- 신규 `par-term-render/src/shaders/upscale.wgsl` (`include_str!`):

```wgsl
@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
struct VsOut { @builtin(position) pos: vec4<f32>, @location(0) uv: vec2<f32> };
@vertex fn vs_main(@builtin(vertex_index) i: u32) -> VsOut {
  var p = array<vec2<f32>,3>(vec2(-1.0,-1.0), vec2(3.0,-1.0), vec2(-1.0,3.0));
  var o: VsOut; o.pos = vec4(p[i],0.0,1.0);
  o.uv = vec2(p[i].x*0.5+0.5, 0.5 - p[i].y*0.5); return o;
}
@fragment fn fs_main(in: VsOut) -> @location(0) vec4<f32> { return textureSample(src, samp, in.uv); }
```

- `CustomShaderRenderer`에 `upscale_pipeline`, `upscale_layout`, `upscale_sampler`(**FilterMode::Nearest**), `upscale_bind_group`
- 셰이더 패스(스케일 타깃) 후 **같은 encoder에 두 번째 패스**를 열어 `output_view`로 블리트:
  `LoadOp::Clear(clear_color)`, 바인드 그룹 = {스케일 텍스처 뷰, nearest 샘플러}, `draw(0..3, 0..1)`

### 4단계 — 적응 정책 + 로그

- 고정 배율만 우선(v1): `render_scale` 은 설정값, 변경 시 재시작 필요 → 이후 필요하면 런타임 반영
- 로그: 파이프라인 준비 시 `[SHADER] render scale {s} target {sw}x{sh}` 1회
- (선택) 프레임 GPU 시간이 `custom_shader_target_gpu_ms` 초과 시 0.25 단계 하향 — **히스테리시스 2단계**로 진동 방지

## 검증 절차 (필수, 각 단계마다)

1. `cargo build --release`
2. `par-term-vulkan.exe --screenshot ... --exit-after 12` → `[SHADER] pipeline compiled in background` +
   **잉크 12~18%**(빈 화면 0%와 구분). 이 검증을 건너뛰면 "live인데 빈 화면" 회귀를 놓친다(실제 사례 있음).
3. 배율 1.0 / 0.5 / 0.25 각각 잉크% + GPU ms 비교(`work/render_check.py <shader> tag=perf`)
4. 회귀: 1.0에서 기존과 동일
5. 실패 시: 배율 기능만 비활성(기본 1.0) → 셰이더·백엔드 수정은 건드리지 않음

## 롤백/백업

- 원본 4파일: `galaxy-work/work/backups-b/` (rendering.rs, custom_shader texts/mod.rs, global_shader_config.rs)
- 되돌린 실험(재시도 금지): PipelineCache 영속화 — 이 드라이버는 `get_data()`가 None이고,
  그 상태에서 렌더가 빈 화면이 되는 회귀가 있었다(롤백 완료).
