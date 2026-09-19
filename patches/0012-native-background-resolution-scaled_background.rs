//! Background-only downsampling on integrated GPUs. Text stays in the native pane pass.
use wgpu::*;

/// Coarsest background scale the adaptive policy will pick. Beyond a third of the native size the
/// authored pixel grid stops reading as a grid, and the redraw-rate lever covers the rest.
pub(super) const MAX_DIVISOR: u32 = 3;

/// Background redraw rate the policy starts from, and the floor it may fall to. Once the picture is
/// as coarse as it goes, redrawing less often is the only lever left: the eye reads that as slower
/// motion rather than as a coarser image, and the engine load falls in proportion.
pub(super) const DEFAULT_BACKGROUND_FPS: f32 = 30.0;
pub(super) const MIN_BACKGROUND_FPS: f32 = 5.0;

/// Resolution-derived starting point. Only a window that is genuinely 4K starts scaled: the integer
/// divisors available below that are 1 (native) or 2 (a quarter of the pixels), and a 2560-wide
/// window landing on 1280 is a bigger loss than the load it saves. A machine that cannot hold the
/// frame rate still gets scaled by the policy itself.
pub(super) fn floor_divisor(width: u32, height: u32) -> u32 {
    if width >= 3840 || height >= 2160 {
        2
    } else {
        1
    }
}

/// Integer division preserves the authored pixel grid.
pub(super) fn target_size(width: u32, height: u32, divisor: u32) -> (u32, u32) {
    let divisor = divisor.max(1);
    (
        width.div_ceil(divisor).max(1),
        height.div_ceil(divisor).max(1),
    )
}

/// Picks the divisor from the frame rate the app is actually managing.
///
/// Integrated GPUs differ by an order of magnitude and a window size cannot tell a fast one from
/// a slow one, so a background that cannot keep up gets coarser. It goes finer again only with real
/// headroom (`FAST_FPS`, held for `FAST_SECONDS`) and never twice inside `COOLDOWN_SECONDS`: the
/// first version flipped between two scales every four seconds on a Radeon iGPU (2 -> 3 -> 4 ->
/// 3 -> 2 ...), which re-created the render target each time, and the version after that refused to
/// recover at all, which left the background stuck at a quarter resolution. A resized window or a
/// new shader starts from the resolution floor.
pub(super) const SLOW_FPS: f32 = 30.0;
pub(super) const SLOW_SECONDS: u32 = 5;
pub(super) const FAST_FPS: f32 = 50.0;
pub(super) const FAST_SECONDS: u32 = 3;
pub(super) const COOLDOWN_SECONDS: f32 = 3.0;

pub(super) fn coarser(current: u32, floor: u32) -> u32 {
    let current = current.clamp(floor.clamp(1, MAX_DIVISOR), MAX_DIVISOR);
    (current + 1).min(MAX_DIVISOR)
}

/// One step finer, never past the resolution floor.
pub(super) fn finer(current: u32, floor: u32) -> u32 {
    let floor = floor.clamp(1, MAX_DIVISOR);
    current
        .clamp(floor, MAX_DIVISOR)
        .saturating_sub(1)
        .max(floor)
}

pub(super) struct ScaledBackground {
    pub size: (u32, u32),
    pub view: TextureView,
    pipeline: RenderPipeline,
    layout: BindGroupLayout,
}

impl ScaledBackground {
    pub fn new(device: &Device, format: TextureFormat, size: (u32, u32)) -> Self {
        let texture = device.create_texture(&TextureDescriptor {
            label: Some("Scaled background"),
            size: Extent3d {
                width: size.0,
                height: size.1,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: TextureDimension::D2,
            format,
            usage: TextureUsages::RENDER_ATTACHMENT | TextureUsages::TEXTURE_BINDING,
            view_formats: &[],
        });
        let view = texture.create_view(&TextureViewDescriptor::default());
        let module = device.create_shader_module(ShaderModuleDescriptor {
            label: Some("Native background composition"),
            source: ShaderSource::Wgsl(include_str!("scaled_background.wgsl").into()),
        });
        let pipeline = device.create_render_pipeline(&RenderPipelineDescriptor {
            label: Some("Native background composition"),
            layout: None,
            vertex: VertexState {
                module: &module,
                entry_point: Some("vs_main"),
                buffers: &[],
                compilation_options: Default::default(),
            },
            fragment: Some(FragmentState {
                module: &module,
                entry_point: Some("fs_main"),
                targets: &[Some(ColorTargetState {
                    format,
                    blend: Some(BlendState::PREMULTIPLIED_ALPHA_BLENDING),
                    write_mask: ColorWrites::ALL,
                })],
                compilation_options: Default::default(),
            }),
            primitive: PrimitiveState::default(),
            depth_stencil: None,
            multisample: MultisampleState::default(),
            multiview_mask: None,
            cache: None,
        });
        let layout = pipeline.get_bind_group_layout(0);
        Self {
            size,
            view,
            pipeline,
            layout,
        }
    }

    pub fn composite(
        &self,
        device: &Device,
        encoder: &mut CommandEncoder,
        output: &TextureView,
        terminal: &TextureView,
        uniforms: &Buffer,
        clear_color: Color,
    ) {
        // Recreate bindings to use the current terminal texture after a resize or pane change.
        let group = device.create_bind_group(&BindGroupDescriptor {
            label: Some("Native background composition"),
            layout: &self.layout,
            entries: &[
                BindGroupEntry {
                    binding: 0,
                    resource: BindingResource::TextureView(&self.view),
                },
                BindGroupEntry {
                    binding: 1,
                    resource: BindingResource::TextureView(terminal),
                },
                BindGroupEntry {
                    binding: 2,
                    resource: uniforms.as_entire_binding(),
                },
            ],
        });
        let mut pass = encoder.begin_render_pass(&RenderPassDescriptor {
            label: Some("Native background composition"),
            color_attachments: &[Some(RenderPassColorAttachment {
                view: output,
                resolve_target: None,
                depth_slice: None,
                ops: Operations {
                    load: LoadOp::Clear(clear_color),
                    store: StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            timestamp_writes: None,
            occlusion_query_set: None,
            multiview_mask: None,
        });
        pass.set_pipeline(&self.pipeline);
        pass.set_bind_group(0, &group, &[]);
        pass.draw(0..3, 0..1);
    }
}

#[cfg(test)]
mod tests {
    use super::{MAX_DIVISOR, coarser, finer, floor_divisor, target_size};

    #[test]
    fn floor_keeps_everything_but_4k_native() {
        assert_eq!(floor_divisor(1920, 1080), 1);
        assert_eq!(floor_divisor(2560, 1440), 1);
        assert_eq!(floor_divisor(3440, 1440), 1);
        assert_eq!(floor_divisor(3840, 2160), 2);
        assert_eq!(floor_divisor(2160, 3840), 2);
        assert_eq!(floor_divisor(3841, 2161), 2);
        assert_eq!(floor_divisor(0, 0), 1);
    }

    #[test]
    fn target_size_divides_and_never_reaches_zero() {
        assert_eq!(target_size(3840, 2160, 2), (1920, 1080));
        assert_eq!(target_size(2160, 3840, 2), (1080, 1920));
        assert_eq!(target_size(3841, 2161, 3), (1281, 721));
        assert_eq!(target_size(0, 0, 1), (1, 1));
    }

    #[test]
    fn divisor_gets_coarser_but_stops_at_the_cap() {
        assert_eq!(coarser(1, 1), 2);
        assert_eq!(coarser(2, 1), 3);
        // Capped, and never finer than the resolution floor.
        assert_eq!(coarser(3, 1), MAX_DIVISOR);
        assert_eq!(coarser(1, 2), 3);
        assert_eq!(coarser(0, 1), 2);
    }

    #[test]
    fn divisor_recovers_but_never_past_the_floor() {
        assert_eq!(finer(3, 1), 2);
        assert_eq!(finer(2, 1), 1);
        // The resolution floor is the best it may get back to.
        assert_eq!(finer(2, 2), 2);
        assert_eq!(finer(3, 2), 2);
        assert_eq!(finer(1, 1), 1);
    }
}
