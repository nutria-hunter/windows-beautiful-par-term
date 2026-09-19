//! Background-only downsampling on integrated GPUs. Text stays in the native pane pass.
use wgpu::*;

pub(super) fn target_size(
    width: u32,
    height: u32,
    integrated: bool,
    full_content: bool,
) -> (u32, u32) {
    // Integer division preserves the authored pixel grid. Do not scale cursor/full-content effects.
    let divisor = if integrated && !full_content {
        width.div_ceil(1920).max(height.div_ceil(1080)).max(1)
    } else {
        1
    };
    (
        width.div_ceil(divisor).max(1),
        height.div_ceil(divisor).max(1),
    )
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
    use super::target_size;
    #[test]
    fn native_text_and_full_content_are_never_downscaled() {
        assert_eq!(target_size(3840, 2160, true, true), (3840, 2160));
        assert_eq!(target_size(3840, 2160, false, false), (3840, 2160));
        assert_eq!(target_size(1920, 1080, true, false), (1920, 1080));
    }
    #[test]
    fn integrated_background_handles_portrait_odd_and_zero_sizes() {
        assert_eq!(target_size(3840, 2160, true, false), (1920, 1080));
        assert_eq!(target_size(2160, 3840, true, false), (540, 960));
        assert_eq!(target_size(3841, 2161, true, false), (1281, 721));
        assert_eq!(target_size(0, 0, true, false), (1, 1));
    }
}
