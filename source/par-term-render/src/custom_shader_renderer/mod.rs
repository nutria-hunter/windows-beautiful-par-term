//! Custom shader renderer for post-processing effects
//!
//! Supports Ghostty/Shadertoy-style GLSL shaders with the following uniforms:
//! - `iTime`: Time in seconds (animated or fixed at 0.0)
//! - `iResolution`: Viewport resolution (width, height, 1.0)
//! - `iChannel0-3`: User texture channels (Shadertoy compatible)
//! - `iChannel4`: Terminal content texture
//! - `iTimeKeyPress`: Time when last key was pressed (same timebase as iTime)
//!
//! Ghostty-compatible cursor uniforms (v1.2.0+):
//! - `iCurrentCursor`: Current cursor position (xy) and size (zw) in pixels
//! - `iPreviousCursor`: Previous cursor position and size
//! - `iCurrentCursorColor`: Current cursor RGBA color (with opacity baked in)
//! - `iPreviousCursorColor`: Previous cursor RGBA color
//! - `iTimeCursorChange`: Time when cursor last moved (same timebase as iTime)

use anyhow::{Context, Result};
use par_term_emu_core_rust::cursor::CursorStyle;
use std::collections::BTreeMap;
use std::path::Path;
use std::time::Instant;
use wgpu::util::DeviceExt;
use wgpu::*;

mod builtin_textures;
mod cubemap;
mod cursor;
mod hot_reload;
pub mod pipeline;
mod scaled_background;
mod state;
pub mod textures;
pub mod transpiler;
pub mod types;
mod uniforms;

use cubemap::CubemapTexture;
use pipeline::{
    BindGroupInputs, create_bind_group, create_bind_group_layout, create_render_pipeline,
};
use textures::{ChannelTexture, load_channel_textures};
use transpiler::transpile_glsl_to_wgsl;

/// Path the transpiled WGSL is dumped to for shader debugging.
///
/// Resolved through [`crate::shader_debug`] so the renderer, the transpiler and the
/// paths reported by shader diagnostics all name the same file: `$TMPDIR` on Unix (a
/// per-user directory on macOS, `/tmp` on Linux), `%TEMP%` on Windows. A hardcoded
/// `/tmp` was wrong on Windows, where it resolves against the current drive.
#[cfg_attr(not(debug_assertions), allow(dead_code))]
fn debug_shader_wgsl_filename(shader_name: &str) -> String {
    crate::shader_debug::transpiled_wgsl_path(shader_name)
        .to_string_lossy()
        .into_owned()
}

/// Dump the transpiled WGSL next to the transpiler's wrapped-GLSL dump.
///
/// Debug builds only, matching the wrapped-GLSL dump in
/// [`transpiler::wgsl_emit`], and written owner-only: on Linux the temp directory
/// is the shared, world-writable `/tmp`, so a predictable filename there is both a
/// disclosure and a symlink hazard. `create_new` gives `O_CREAT | O_EXCL`, which
/// POSIX requires to fail rather than follow a symlink, so a pre-planted link is
/// rejected atomically; the preceding unlink is what lets a real dump be refreshed
/// on the next shader load.
fn write_debug_shader_wgsl(shader_name: &str, wgsl_source: &str) {
    #[cfg(debug_assertions)]
    {
        let debug_filename = debug_shader_wgsl_filename(shader_name);

        // Removes our own previous dump, and a symlink planted in its place (this
        // unlinks the link itself, never its target). Losing the race is handled by
        // `create_new` below failing rather than writing through the attacker's link.
        let _ = std::fs::remove_file(&debug_filename);

        let mut opts = std::fs::OpenOptions::new();
        opts.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            opts.mode(0o600);
        }

        let result = opts
            .open(&debug_filename)
            .and_then(|mut f| std::io::Write::write_all(&mut f, wgsl_source.as_bytes()));

        match result {
            Ok(()) => log::info!("Wrote debug shader to {}", debug_filename),
            Err(e) => log::warn!("Failed to write debug shader: {}", e),
        }
    }
    #[cfg(not(debug_assertions))]
    {
        let _ = (shader_name, wgsl_source);
    }
}

fn animation_start_after_enabled_update(
    currently_enabled: bool,
    enabled: bool,
    current_start: Instant,
    now: Instant,
) -> Instant {
    if enabled && !currently_enabled {
        now
    } else {
        current_start
    }
}

/// Custom shader renderer that applies post-processing effects
pub struct CustomShaderRenderer {
    integrated_gpu: bool,
    /// When the background renders into its own scaled texture the compositor can reuse it,
    /// so the artwork is redrawn a few times a second instead of every frame.
    /// `None` means it has not been drawn into the current target yet.
    last_background_render: Option<Instant>,
    scaled_background: Option<scaled_background::ScaledBackground>,
    /// The render pipeline for the custom shader. `None` until the background compile lands: the
    /// driver takes seconds on a shader this size, and none of that needs the UI thread, so the
    /// window paints while the pipeline is still being built.
    pub(crate) pipeline: Option<RenderPipeline>,
    /// Receives the finished pipeline - or the message explaining why there is none - from that
    /// worker thread. wgpu reports a rejected pipeline by panicking, so a plain `RenderPipeline`
    /// channel could only ever say "closed", which is why a failed shader used to render nothing
    /// with nothing in the log.
    pub(crate) pipeline_rx: Option<std::sync::mpsc::Receiver<Result<RenderPipeline, String>>>,
    /// Bind group for shader uniforms and textures
    pub(crate) bind_group: BindGroup,
    /// Uniform buffer for shader parameters
    pub(crate) uniform_buffer: Buffer,
    /// Uniform buffer for custom shader control values
    pub(crate) custom_uniform_buffer: Buffer,
    /// Intermediate texture to render terminal content into
    pub(crate) intermediate_texture: Texture,
    /// View of the intermediate texture
    pub(crate) intermediate_texture_view: TextureView,
    /// Start time for animation
    pub(crate) start_time: Instant,
    /// Whether animation is enabled
    pub(crate) animation_enabled: bool,
    /// Animation speed multiplier
    pub(crate) animation_speed: f32,
    /// Current texture dimensions
    pub(crate) texture_width: u32,
    pub(crate) texture_height: u32,
    /// Surface format for compatibility
    pub(crate) surface_format: TextureFormat,
    /// Bind group layout for recreating bind groups on resize
    pub(crate) bind_group_layout: BindGroupLayout,
    /// Sampler for the intermediate texture
    pub(crate) sampler: Sampler,
    /// Display scale factor for DPI scaling (e.g., 2.0 on Retina)
    pub(crate) scale_factor: f32,
    /// Window opacity for transparency
    pub(crate) window_opacity: f32,
    /// When true, text is always rendered at full opacity (overrides text_opacity)
    pub(crate) keep_text_opaque: bool,
    /// Full content mode - shader receives and can manipulate full terminal content
    pub(crate) full_content_mode: bool,
    /// Brightness multiplier for shader output (0.05-1.0)
    pub(crate) brightness: f32,
    /// Whether to dim shader output under terminal content.
    pub(crate) auto_dim_under_text: bool,
    /// Strength of dimming under terminal content.
    pub(crate) auto_dim_strength: f32,
    /// Frame counter for iFrame uniform
    pub(crate) frame_count: u32,
    /// Last frame time for calculating time delta
    pub(crate) last_frame_time: Instant,
    /// Current mouse position in pixels (xy)
    pub(crate) mouse_position: [f32; 2],
    /// Last click position in pixels (zw)
    pub(crate) mouse_click_position: [f32; 2],
    /// Whether mouse button is currently pressed (affects sign of zw)
    pub(crate) mouse_button_down: bool,
    /// Frame rate tracking: time accumulator for averaging
    pub(crate) frame_time_accumulator: f32,
    /// Frame rate tracking: frames in current second
    pub(crate) frames_in_second: u32,
    /// Current smoothed frame rate
    pub(crate) current_frame_rate: f32,

    // ============ Cursor tracking (Ghostty-compatible) ============
    /// Current cursor position in cell coordinates (col, row)
    pub(crate) current_cursor_pos: (usize, usize),
    /// Previous cursor position in cell coordinates
    pub(crate) previous_cursor_pos: (usize, usize),
    /// Current cursor RGBA color
    pub(crate) current_cursor_color: [f32; 4],
    /// Previous cursor RGBA color
    pub(crate) previous_cursor_color: [f32; 4],
    /// Current cursor opacity (0.0 = invisible, 1.0 = fully visible)
    pub(crate) current_cursor_opacity: f32,
    /// Previous cursor opacity
    pub(crate) previous_cursor_opacity: f32,
    /// Time when cursor position last changed (same timebase as iTime)
    pub(crate) cursor_change_time: f32,
    /// Current cursor style (for size calculation)
    pub(crate) current_cursor_style: CursorStyle,
    /// Previous cursor style
    pub(crate) previous_cursor_style: CursorStyle,
    /// Cell width in pixels (for cursor position calculation)
    pub(crate) cursor_cell_width: f32,
    /// Cell height in pixels (for cursor position calculation)
    pub(crate) cursor_cell_height: f32,
    /// Window padding in pixels (for cursor position calculation)
    pub(crate) cursor_window_padding: f32,
    /// Vertical content offset in pixels (e.g., tab bar height)
    pub(crate) cursor_content_offset_y: f32,
    /// Horizontal content offset in pixels (e.g., tab bar on left)
    pub(crate) cursor_content_offset_x: f32,

    // ============ Cursor shader configuration ============
    /// User-configured cursor color for shader effects [R, G, B, A]
    pub(crate) cursor_shader_color: [f32; 4],
    /// Cursor trail duration in seconds
    pub(crate) cursor_trail_duration: f32,
    /// Cursor glow radius in pixels
    pub(crate) cursor_glow_radius: f32,
    /// Cursor glow intensity (0.0-1.0)
    pub(crate) cursor_glow_intensity: f32,

    // ============ Key press tracking ============
    /// Time when a key was last pressed (same timebase as iTime)
    pub(crate) key_press_time: f32,

    // ============ Channel textures (iChannel0-3) ============
    /// Texture channels 0-3 (placeholders or loaded textures, Shadertoy compatible)
    pub(crate) channel_textures: [ChannelTexture; 4],

    // ============ Cubemap texture (iCubemap) ============
    /// Cubemap texture for environment mapping (placeholder or loaded)
    pub(crate) cubemap: CubemapTexture,

    // ============ Background image as iChannel0 ============
    /// When true, use the background image texture as iChannel0 instead of the configured texture
    pub(crate) use_background_as_channel0: bool,
    /// Background texture to use as iChannel0 when use_background_as_channel0 is true
    /// This is a reference texture (view + sampler + dimensions) from the cell renderer
    pub(crate) background_channel_texture: Option<ChannelTexture>,
    /// Blend mode hint exposed to shaders for background-as-iChannel0 composition.
    pub(crate) background_channel0_blend_mode: par_term_config::ShaderBackgroundBlendMode,

    // ============ Solid background color ============
    /// Solid background color [R, G, B, A] for shader compositing.
    /// When A > 0, the shader uses this color as background instead of shader output.
    /// RGB values are NOT premultiplied.
    pub(crate) background_color: [f32; 4],

    // ============ Progress bar state ============
    /// Progress bar data [state, percent, isActive, activeCount]
    pub(crate) progress_data: [f32; 4],

    // ============ Command state ============
    /// Command state data [state, exitCode, eventTime, running]
    pub(crate) command_data: [f32; 4],

    // ============ Focused pane bounds ============
    /// Focused pane bounds [x, y, width, height] in bottom-left-origin pixels.
    pub(crate) focused_pane: [f32; 4],

    // ============ Scrollback context ============
    /// Scrollback context [offset, visibleLines, scrollbackLines, normalizedDepth]
    pub(crate) scroll_data: [f32; 4],

    // ============ Content inset for panels ============
    /// Right content inset in pixels (e.g., AI Inspector panel).
    /// The shader renders to a viewport offset by this amount from the left.
    pub(crate) content_inset_right: f32,

    // ============ Custom shader controls ============
    /// Custom controls parsed from `// control ...` shader comments.
    pub(crate) custom_controls: Vec<par_term_config::ShaderControl>,
    /// Current custom uniform values keyed by control name.
    pub(crate) custom_uniform_values: BTreeMap<String, par_term_config::ShaderUniformValue>,
}

/// Parameters for creating a new [`CustomShaderRenderer`].
pub struct CustomShaderRendererConfig<'a> {
    pub surface_format: TextureFormat,
    pub shader_path: &'a Path,
    pub width: u32,
    pub height: u32,
    pub animation_enabled: bool,
    pub animation_speed: f32,
    pub window_opacity: f32,
    pub full_content_mode: bool,
    pub channel_paths: &'a [Option<std::path::PathBuf>; 4],
    pub cubemap_path: Option<&'a Path>,
    pub custom_uniforms: &'a BTreeMap<String, par_term_config::ShaderUniformValue>,
    pub background_channel0_blend_mode: par_term_config::ShaderBackgroundBlendMode,
}

impl CustomShaderRenderer {
    /// Create a new custom shader renderer from a GLSL shader file.
    pub fn new(
        device: &Device,
        queue: &Queue,
        config: CustomShaderRendererConfig<'_>,
    ) -> Result<Self> {
        let CustomShaderRendererConfig {
            surface_format,
            shader_path,
            width,
            height,
            animation_enabled,
            animation_speed,
            window_opacity,
            full_content_mode,
            channel_paths,
            cubemap_path,
            custom_uniforms,
            background_channel0_blend_mode,
        } = config;
        // Load the GLSL shader
        let glsl_source = std::fs::read_to_string(shader_path)
            .with_context(|| format!("Failed to read shader file: {}", shader_path.display()))?;

        let control_parse = par_term_config::parse_shader_controls(&glsl_source);
        for warning in &control_parse.warnings {
            log::warn!(
                "Shader control warning line {}: {}",
                warning.line,
                warning.message
            );
        }
        let custom_controls = control_parse.controls;
        let custom_uniform_values = custom_uniforms.clone();

        // Transpile GLSL to WGSL
        let wgsl_source = transpile_glsl_to_wgsl(&glsl_source, shader_path)?;

        log::info!(
            "Loaded custom shader from {} ({} bytes GLSL -> {} bytes WGSL)",
            shader_path.display(),
            glsl_source.len(),
            wgsl_source.len()
        );
        log::debug!("Generated WGSL:\n{}", wgsl_source);

        // DEBUG: Write generated WGSL to file for inspection
        let shader_name = shader_path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("unknown");
        write_debug_shader_wgsl(shader_name, &wgsl_source);

        // Pre-validate WGSL
        let module = naga::front::wgsl::parse_str(&wgsl_source)
            .context("Custom shader WGSL parse failed")?;
        let _info = naga::valid::Validator::new(
            naga::valid::ValidationFlags::all(),
            naga::valid::Capabilities::empty(),
        )
        .validate(&module)
        .context("Custom shader WGSL validation failed")?;
        let shader_module = device.create_shader_module(ShaderModuleDescriptor {
            label: Some("Custom Shader Module"),
            source: ShaderSource::Wgsl(wgsl_source.clone().into()),
        });
        // Create intermediate texture for terminal content
        let (intermediate_texture, intermediate_texture_view) =
            Self::create_intermediate_texture(device, surface_format, width, height);

        // Create sampler for the intermediate texture (terminal content)
        // Use Nearest filtering to keep text crisp and pixel-perfect
        let sampler = device.create_sampler(&SamplerDescriptor {
            label: Some("Custom Shader Sampler"),
            address_mode_u: AddressMode::ClampToEdge,
            address_mode_v: AddressMode::ClampToEdge,
            address_mode_w: AddressMode::ClampToEdge,
            mag_filter: FilterMode::Nearest,
            min_filter: FilterMode::Nearest,
            mipmap_filter: MipmapFilterMode::Nearest,
            ..Default::default()
        });

        // Load channel textures (iChannel0-3)
        let channel_textures = load_channel_textures(device, queue, channel_paths);

        // Load cubemap texture (iCubemap)
        let cubemap = match cubemap_path {
            Some(path) => match CubemapTexture::from_prefix(device, queue, path) {
                Ok(cm) => cm,
                Err(e) => {
                    log::error!("Failed to load cubemap '{}': {}", path.display(), e);
                    CubemapTexture::placeholder(device, queue)
                }
            },
            None => CubemapTexture::placeholder(device, queue),
        };

        // Create uniform buffers
        let uniform_buffer = Self::create_uniform_buffer(device);
        let custom_uniform_data =
            crate::custom_shader_renderer::types::CustomShaderControlUniforms::from_controls(
                &custom_controls,
                &custom_uniform_values,
            );
        let custom_uniform_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Custom Shader Control Uniform Buffer"),
            contents: bytemuck::cast_slice(&[custom_uniform_data]),
            usage: BufferUsages::UNIFORM | BufferUsages::COPY_DST,
        });

        // Create bind group layout and bind group
        let bind_group_layout = create_bind_group_layout(device);
        let bind_group = create_bind_group(
            device,
            BindGroupInputs {
                layout: &bind_group_layout,
                uniform_buffer: &uniform_buffer,
                intermediate_texture_view: &intermediate_texture_view,
                custom_uniform_buffer: &custom_uniform_buffer,
                sampler: &sampler,
                channel_textures: &channel_textures,
                cubemap: &cubemap,
            },
        );

        // Build the pipeline on a worker thread. Measured on an RTX 5090: ~40 ms for a small
        // shader, but 6-9 s for a large one, every single launch, scaling with shader size. The
        // compile needs only the device, module and layout - never the window - so the window comes
        // up immediately and the shader blends in when it is ready.
        let (pipeline_tx, pipeline_rx) = std::sync::mpsc::channel();
        let pipeline_label = "Custom Shader Pipeline";
        {
            let device = device.clone();
            let shader_module = shader_module.clone();
            let bind_group_layout = bind_group_layout.clone();
            std::thread::Builder::new()
                .name("custom-shader-pipeline".into())
                .spawn(move || {
                    // A rejected pipeline panics inside wgpu (the message names the naga/wgpu error).
                    // Catching it is what turns "no background, no log" into a readable reason.
                    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                        create_render_pipeline(
                            &device,
                            &shader_module,
                            &bind_group_layout,
                            surface_format,
                            Some(pipeline_label),
                        )
                    }))
                    .map_err(|payload| {
                        payload
                            .downcast_ref::<String>()
                            .cloned()
                            .or_else(|| payload.downcast_ref::<&str>().map(|s| (*s).to_string()))
                            .unwrap_or_else(|| {
                                "pipeline thread panicked with a non-string payload".to_owned()
                            })
                    });
                    // A closed window drops the receiver first; that is not an error.
                    let _ = pipeline_tx.send(result);
                })
                .context("Failed to spawn custom shader pipeline thread")?;
        }
        let now = Instant::now();
        Ok(Self {
            integrated_gpu: device.adapter_info().device_type == DeviceType::IntegratedGpu,
            last_background_render: None,
            scaled_background: None,
            pipeline: None,
            pipeline_rx: Some(pipeline_rx),
            bind_group,
            uniform_buffer,
            custom_uniform_buffer,
            intermediate_texture,
            intermediate_texture_view,
            start_time: now,
            animation_enabled,
            animation_speed,
            texture_width: width,
            texture_height: height,
            surface_format,
            bind_group_layout,
            sampler,
            window_opacity,
            keep_text_opaque: false,
            scale_factor: 1.0,
            full_content_mode,
            brightness: 1.0,
            auto_dim_under_text: false,
            auto_dim_strength: 0.35,
            frame_count: 0,
            last_frame_time: now,
            mouse_position: [0.0, 0.0],
            mouse_click_position: [0.0, 0.0],
            mouse_button_down: false,
            frame_time_accumulator: 0.0,
            frames_in_second: 0,
            current_frame_rate: 60.0,
            current_cursor_pos: (0, 0),
            previous_cursor_pos: (0, 0),
            current_cursor_color: [1.0, 1.0, 1.0, 1.0],
            previous_cursor_color: [1.0, 1.0, 1.0, 1.0],
            current_cursor_opacity: 1.0,
            previous_cursor_opacity: 1.0,
            cursor_change_time: 0.0,
            current_cursor_style: CursorStyle::SteadyBlock,
            previous_cursor_style: CursorStyle::SteadyBlock,
            cursor_cell_width: 10.0,
            cursor_cell_height: 20.0,
            cursor_window_padding: 0.0,
            cursor_content_offset_y: 0.0,
            cursor_content_offset_x: 0.0,
            cursor_shader_color: [1.0, 1.0, 1.0, 1.0],
            cursor_trail_duration: 0.5,
            cursor_glow_radius: 80.0,
            cursor_glow_intensity: 0.3,
            key_press_time: 0.0,
            channel_textures,
            cubemap,
            use_background_as_channel0: false,
            background_channel_texture: None,
            background_channel0_blend_mode,
            background_color: [0.0, 0.0, 0.0, 0.0], // No solid background by default
            progress_data: [0.0, 0.0, 0.0, 0.0],
            command_data: [0.0, 0.0, 0.0, 0.0],
            focused_pane: [0.0, 0.0, width as f32, height as f32],
            scroll_data: [0.0, 0.0, 0.0, 0.0],
            content_inset_right: 0.0,
            custom_controls,
            custom_uniform_values,
        })
    }

    /// Get a view of the intermediate texture for rendering terminal content into
    pub fn intermediate_texture_view(&self) -> &TextureView {
        &self.intermediate_texture_view
    }

    /// Render the custom shader effect to the output texture
    ///
    /// # Arguments
    /// * `device` - The GPU device
    /// * `queue` - The command queue
    /// * `output_view` - The texture view to render to
    /// * `apply_opacity` - Whether to apply window opacity. Set to `false` when rendering
    ///   to an intermediate texture that will be processed by another shader (to avoid
    ///   double-applying opacity).
    pub fn render(
        &mut self,
        device: &Device,
        queue: &Queue,
        output_view: &TextureView,
        apply_opacity: bool,
    ) -> Result<()> {
        self.render_with_clear_color(
            device,
            queue,
            output_view,
            apply_opacity,
            Color::TRANSPARENT,
        )
    }

    /// Render the custom shader with a specified clear color.
    /// Use this for solid background colors where the clear color provides the background.
    /// Whether the background pipeline compile has landed. Until it has, the shader must not be
    /// drawn at all: its render pass clears the target, so "drawing nothing" would erase the frame.
    pub fn is_ready(&self) -> bool {
        self.pipeline.is_some()
    }

    /// Install the pipeline once the worker thread finishes. One non-blocking receive per frame.
    /// Returns true when a pipeline was installed, so the caller can repaint: the frames drawn while
    /// the compile was in flight used the ordinary opaque background, and without a repaint the
    /// shader would land behind an image that is never redrawn - the "toggle the shader and it stays
    /// covered" symptom.
    pub fn poll_pipeline(&mut self) -> bool {
        let Some(rx) = self.pipeline_rx.as_ref() else {
            return false;
        };
        match rx.try_recv() {
            Ok(Ok(pipeline)) => {
                log::info!(
                    "[SHADER] custom shader pipeline compiled in background; shader is live"
                );
                self.pipeline = Some(pipeline);
                self.pipeline_rx = None;
                true
            }
            Ok(Err(message)) => {
                // The transpiler accepted the shader but the driver rejected the pipeline. Nothing
                // will be drawn until the shader is fixed, so this must never be silent again.
                log::error!(
                    "[SHADER] pipeline creation failed; no background will be drawn: {message}"
                );
                self.pipeline_rx = None;
                false
            }
            Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                log::error!(
                    "[SHADER] pipeline thread died without reporting; no background will be drawn"
                );
                self.pipeline_rx = None;
                false
            }
            Err(std::sync::mpsc::TryRecvError::Empty) => false,
        }
    }

    pub fn render_with_clear_color(
        &mut self,
        device: &Device,
        queue: &Queue,
        output_view: &TextureView,
        apply_opacity: bool,
        clear_color: Color,
    ) -> Result<()> {
        self.poll_pipeline();
        if self.pipeline.is_none() {
            // Still compiling: skip the pass entirely rather than enter it with no draw.
            return Ok(());
        }
        let now = Instant::now();

        // Calculate time value
        let time = if self.animation_enabled {
            self.start_time.elapsed().as_secs_f32() * self.animation_speed.max(0.0)
        } else {
            0.0
        };

        // Calculate time delta
        let time_delta = now.duration_since(self.last_frame_time).as_secs_f32();
        self.last_frame_time = now;

        // Update frame rate calculation
        self.frame_time_accumulator += time_delta;
        self.frames_in_second += 1;
        if self.frame_time_accumulator >= 1.0 {
            self.current_frame_rate = self.frames_in_second as f32 / self.frame_time_accumulator;
            self.frame_time_accumulator = 0.0;
            self.frames_in_second = 0;
        }

        self.frame_count = self.frame_count.wrapping_add(1);

        // Calculate uniforms
        let size = scaled_background::target_size(
            self.texture_width,
            self.texture_height,
            self.integrated_gpu,
            self.full_content_mode,
        );
        let scaled = size != (self.texture_width, self.texture_height);
        if scaled
            && self
                .scaled_background
                .as_ref()
                .is_none_or(|target| target.size != size)
        {
            log::info!(
                "Background render target: {}x{} -> {}x{} (native text)",
                self.texture_width,
                self.texture_height,
                size.0,
                size.1
            );
            self.scaled_background = Some(scaled_background::ScaledBackground::new(
                device,
                self.surface_format,
                size,
            ));
            // A fresh target holds nothing yet, so the next frame must draw into it.
            self.last_background_render = None;
        } else if !scaled {
            self.scaled_background = None;
        }
        let mut uniforms = self.build_uniforms(time, time_delta, apply_opacity);
        if scaled {
            uniforms.readability[2] = self.texture_width as f32 / size.0 as f32;
            uniforms.readability[3] = self.texture_height as f32 / size.1 as f32;
        }
        queue.write_buffer(&self.uniform_buffer, 0, bytemuck::cast_slice(&[uniforms]));
        let custom_uniforms =
            crate::custom_shader_renderer::types::CustomShaderControlUniforms::from_controls(
                &self.custom_controls,
                &self.custom_uniform_values,
            );
        queue.write_buffer(
            &self.custom_uniform_buffer,
            0,
            bytemuck::cast_slice(&[custom_uniforms]),
        );

        // Integrated GPUs shade this background on their own: the artwork is a slow nebula, so
        // redrawing it 30 times a second halves the cost while still reading as motion. A
        // non-animated shader only needs a redraw when something else changes, so it leans on
        // the same texture for a second at a time. The scaled path owns its texture, which is
        // what makes reuse safe; the direct path draws straight into the output view.
        let interval = if self.animation_enabled {
            1.0 / 30.0
        } else {
            1.0
        };
        let background_due = !scaled
            || self
                .last_background_render
                .is_none_or(|last| last.elapsed().as_secs_f32() >= interval);
        if background_due {
            self.last_background_render = Some(now);
        }

        // Create command encoder and render
        let mut encoder = device.create_command_encoder(&CommandEncoderDescriptor {
            label: Some("Custom Shader Encoder"),
        });

        if background_due {
            let mut render_pass = encoder.begin_render_pass(&RenderPassDescriptor {
                label: Some("Custom Shader Render Pass"),
                color_attachments: &[Some(RenderPassColorAttachment {
                    view: self
                        .scaled_background
                        .as_ref()
                        .map_or(output_view, |target| &target.view),
                    resolve_target: None,
                    ops: Operations {
                        load: LoadOp::Clear(if scaled {
                            Color::TRANSPARENT
                        } else {
                            clear_color
                        }),
                        store: StoreOp::Store,
                    },
                    depth_slice: None,
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
                multiview_mask: None,
            });

            // Note: We intentionally do NOT set a viewport here to exclude the panel area.
            // The viewport approach doesn't work because fragCoord in WGSL is relative to
            // the render target, not the viewport, causing UV coordinate mismatches.
            // The opaque panel (PANEL_BG with alpha 255) covers any shader output under it.

            if let Some(pipeline) = self.pipeline.as_ref() {
                render_pass.set_pipeline(pipeline);
                render_pass.set_bind_group(0, &self.bind_group, &[]);
                render_pass.draw(0..4, 0..1);
            }
        }

        if let Some(target) = &self.scaled_background {
            target.composite(
                device,
                &mut encoder,
                output_view,
                &self.intermediate_texture_view,
                &self.uniform_buffer,
                clear_color,
            );
        }
        queue.submit(std::iter::once(encoder.finish()));
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn enabling_animation_when_already_enabled_preserves_start_time() {
        let start_time = Instant::now() - Duration::from_secs(5);
        let now = Instant::now();

        assert_eq!(
            animation_start_after_enabled_update(true, true, start_time, now),
            start_time
        );
    }

    #[test]
    fn enabling_animation_from_disabled_starts_at_now() {
        let start_time = Instant::now() - Duration::from_secs(5);
        let now = Instant::now();

        assert_eq!(
            animation_start_after_enabled_update(false, true, start_time, now),
            now
        );
    }

    #[test]
    fn debug_shader_wgsl_filename_matches_new_renderer_output_path() {
        let path = debug_shader_wgsl_filename("matrix");
        assert_eq!(
            std::path::Path::new(&path),
            crate::shader_debug::debug_dump_dir().join("par_term_matrix_shader.wgsl")
        );
    }

    // The dump is debug-builds-only, so these exercise nothing under
    // `cargo test --release`.
    #[cfg(debug_assertions)]
    #[test]
    fn write_debug_shader_wgsl_refreshes_existing_output() {
        let shader_name = format!("par_term_test_{}", std::process::id());
        let path = debug_shader_wgsl_filename(&shader_name);
        let _ = std::fs::remove_file(&path);

        write_debug_shader_wgsl(&shader_name, "first");
        write_debug_shader_wgsl(&shader_name, "second");

        assert_eq!(
            std::fs::read_to_string(&path).expect("read debug wgsl"),
            "second"
        );
        std::fs::remove_file(&path).expect("remove debug wgsl");
    }

    /// SEC-006: on Linux the dump lands in the shared, world-writable `/tmp`, so a
    /// predictable filename must not be readable by other users.
    #[cfg(all(debug_assertions, unix))]
    #[test]
    fn write_debug_shader_wgsl_creates_owner_only_file() {
        use std::os::unix::fs::PermissionsExt;

        let shader_name = format!("par_term_mode_{}", std::process::id());
        let path = debug_shader_wgsl_filename(&shader_name);
        let _ = std::fs::remove_file(&path);

        write_debug_shader_wgsl(&shader_name, "secret");

        let mode = std::fs::metadata(&path)
            .expect("dump exists")
            .permissions()
            .mode();
        assert_eq!(mode & 0o777, 0o600, "dump must not be group/world readable");
        std::fs::remove_file(&path).expect("remove debug wgsl");
    }

    /// SEC-006: a symlink pre-planted at the dump path must not be written through.
    #[cfg(all(debug_assertions, unix))]
    #[test]
    fn write_debug_shader_wgsl_does_not_follow_a_planted_symlink() {
        let shader_name = format!("par_term_link_{}", std::process::id());
        let path = debug_shader_wgsl_filename(&shader_name);
        let target = crate::shader_debug::debug_dump_dir()
            .join(format!("par_term_link_target_{}", std::process::id()));

        std::fs::write(&target, "original").expect("seed symlink target");
        let _ = std::fs::remove_file(&path);
        std::os::unix::fs::symlink(&target, &path).expect("plant symlink");

        write_debug_shader_wgsl(&shader_name, "attacker-visible");

        assert_eq!(
            std::fs::read_to_string(&target).expect("read symlink target"),
            "original",
            "the dump must not be written through the planted symlink"
        );
        let _ = std::fs::remove_file(&path);
        std::fs::remove_file(&target).expect("remove symlink target");
    }
}
