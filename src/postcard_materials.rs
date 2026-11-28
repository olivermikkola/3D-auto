//! A material pack for the wgpu renderer: KTX2 texture arrays for the
//! ground classes (docs/RENDERER.md).

use crate::engine::Engine;
use std::ops::Range;
use std::path::Path;
use wgpu::*;

const KTX2_MAGIC: &[u8] = b"\xabKTX 20\xbb\r\n\x1a\n";
const LAYERS: u32 = 8;
const VK_RGBA8_UNORM: u32 = 37;
const VK_RGBA8_SRGB: u32 = 43;

struct TextureArray {
    side: u32,
    mips: Vec<Range<usize>>,
    bytes: Vec<u8>,
}

impl TextureArray {
    fn read(path: &Path, vk_format: u32, limits: &Limits) -> Result<Self, String> {
        let bytes = std::fs::read(path).map_err(|error| format!("{}: {error}", path.display()))?;
        let invalid = || format!("{}: expected an uncompressed RGBA8 KTX2 array", path.display());
        let word = |offset| u32::from_le_bytes(bytes[offset..offset + 4].try_into().unwrap());
        if bytes.len() < 80 || !bytes.starts_with(KTX2_MAGIC) {
            return Err(invalid());
        }
        let side = word(20);
        let levels = word(40);
        if word(12) != vk_format
            || word(16) != 1
            || !matches!(side, 128 | 256 | 512)
            || word(24) != side
            || word(28) != 0
            || word(32) != LAYERS
            || word(36) != 1
            || levels != side.ilog2() + 1
            || word(44) != 0
            || limits.max_texture_dimension_2d < side
            || limits.max_texture_array_layers < LAYERS
        {
            return Err(invalid());
        }
        let index_end = 80 + levels as usize * 24;
        if bytes.len() < index_end {
            return Err(invalid());
        }
        let mut mips = Vec::new();
        // The file stores the smallest image first; the index is largest first.
        let mut next = bytes.len();
        for mip in 0..levels as usize {
            let index = 80 + mip * 24;
            let read = |offset| u64::from_le_bytes(bytes[index + offset..index + offset + 8].try_into().unwrap());
            let start = usize::try_from(read(0)).map_err(|_| invalid())?;
            let count = (side as usize >> mip).pow(2) * LAYERS as usize * 4;
            let end = start.checked_add(count).ok_or_else(invalid)?;
            if start < index_end || start % 4 != 0 || end > next || read(8) != count as u64 || read(16) != count as u64 {
                return Err(invalid());
            }
            next = start;
            mips.push(start..end);
        }
        Ok(Self { side, mips, bytes })
    }

    fn upload(&self, device: &Device, queue: &Queue, format: TextureFormat) -> TextureView {
        let texture = device.create_texture(&TextureDescriptor {
            label: Some("postcard texture array"),
            size: Extent3d { width: self.side, height: self.side, depth_or_array_layers: LAYERS },
            mip_level_count: self.mips.len() as u32,
            sample_count: 1,
            dimension: TextureDimension::D2,
            format,
            usage: TextureUsages::TEXTURE_BINDING | TextureUsages::COPY_DST,
            view_formats: &[],
        });
        for (level, range) in self.mips.iter().enumerate() {
            let side = self.side >> level;
            queue.write_texture(
                TexelCopyTextureInfo { texture: &texture, mip_level: level as u32, origin: Origin3d::ZERO, aspect: TextureAspect::All },
                &self.bytes[range.clone()],
                TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(side * 4), rows_per_image: Some(side) },
                Extent3d { width: side, height: side, depth_or_array_layers: LAYERS },
            );
        }
        texture.create_view(&TextureViewDescriptor { dimension: Some(TextureViewDimension::D2Array), ..Default::default() })
    }
}

pub fn bind(
    device: &Device,
    queue: &Queue,
    engine: &Engine,
    pack: Option<&Path>,
) -> Result<(BindGroupLayout, BindGroup, [f32; 4]), String> {
    let mut terrain_coords = [0.0; 4];
    let (albedo, surface, classes) = if let Some(pack) = pack {
        let limits = device.limits();
        let albedo = TextureArray::read(&pack.join("albedo.ktx2"), VK_RGBA8_SRGB, &limits)?;
        let surface = TextureArray::read(&pack.join("normal_roughness.ktx2"), VK_RGBA8_UNORM, &limits)?;
        if albedo.side != surface.side {
            return Err("material arrays have different sizes".into());
        }
        let t = engine.terrain.as_ref().ok_or("material packs require the heightfield")?;
        let (width, height) = (t.w as u32, t.d as u32);
        if t.w > limits.max_texture_dimension_2d as usize || t.d > limits.max_texture_dimension_2d as usize {
            return Err("terrain classes exceed the texture dimensions".into());
        }
        let classes = t.material_classes.as_deref().ok_or("material packs require a terrain class grid")?;
        if classes.len() != t.w * t.d {
            return Err("terrain class grid dimensions differ from the loaded terrain".into());
        }
        terrain_coords = [t.x0, t.z0, t.step.recip(), 1.0];
        (
            albedo.upload(device, queue, TextureFormat::Rgba8UnormSrgb),
            surface.upload(device, queue, TextureFormat::Rgba8Unorm),
            class_texture(device, queue, width, height, classes, t.material_kerbs.as_deref()),
        )
    } else {
        let array = |format| {
            device
                .create_texture(&TextureDescriptor {
                    label: Some("unused postcard texture"),
                    size: Extent3d { width: 1, height: 1, depth_or_array_layers: 1 },
                    mip_level_count: 1,
                    sample_count: 1,
                    dimension: TextureDimension::D2,
                    format,
                    usage: TextureUsages::TEXTURE_BINDING,
                    view_formats: &[],
                })
                .create_view(&TextureViewDescriptor { dimension: Some(TextureViewDimension::D2Array), ..Default::default() })
        };
        (array(TextureFormat::Rgba8UnormSrgb), array(TextureFormat::Rgba8Unorm), class_texture(device, queue, 1, 1, &[0], None))
    };
    let texture_binding = |binding, dimension, sample_type| BindGroupLayoutEntry {
        binding,
        visibility: ShaderStages::FRAGMENT,
        ty: BindingType::Texture { sample_type, view_dimension: dimension, multisampled: false },
        count: None,
    };
    let layout = device.create_bind_group_layout(&BindGroupLayoutDescriptor {
        label: Some("postcard materials"),
        entries: &[
            texture_binding(0, TextureViewDimension::D2Array, TextureSampleType::Float { filterable: true }),
            texture_binding(1, TextureViewDimension::D2Array, TextureSampleType::Float { filterable: true }),
            texture_binding(2, TextureViewDimension::D2, TextureSampleType::Uint),
            BindGroupLayoutEntry {
                binding: 3,
                visibility: ShaderStages::FRAGMENT,
                ty: BindingType::Sampler(SamplerBindingType::Filtering),
                count: None,
            },
        ],
    });
    let repeat = device.create_sampler(&SamplerDescriptor {
        address_mode_u: AddressMode::Repeat,
        address_mode_v: AddressMode::Repeat,
        mag_filter: FilterMode::Linear,
        min_filter: FilterMode::Linear,
        mipmap_filter: MipmapFilterMode::Linear,
        ..Default::default()
    });
    let group = device.create_bind_group(&BindGroupDescriptor {
        label: Some("postcard materials"),
        layout: &layout,
        entries: &[
            BindGroupEntry { binding: 0, resource: BindingResource::TextureView(&albedo) },
            BindGroupEntry { binding: 1, resource: BindingResource::TextureView(&surface) },
            BindGroupEntry { binding: 2, resource: BindingResource::TextureView(&classes) },
            BindGroupEntry { binding: 3, resource: BindingResource::Sampler(&repeat) },
        ],
    });
    Ok((layout, group, terrain_coords))
}

/// The class grid with each point's kerb distance beside it (red: class,
/// green: 128 + signed distance in 2 cm steps, 0 = no kerb near).
fn class_texture(device: &Device, queue: &Queue, width: u32, height: u32, classes: &[u8], kerbs: Option<&[u8]>) -> TextureView {
    let texels: Vec<u8> = match kerbs.filter(|k| k.len() == classes.len()) {
        Some(k) => classes.iter().zip(k).flat_map(|(&c, &d)| [c, d]).collect(),
        None => classes.iter().flat_map(|&c| [c, 0]).collect(),
    };
    let size = Extent3d { width, height, depth_or_array_layers: 1 };
    let texture = device.create_texture(&TextureDescriptor {
        label: Some("terrain class grid"),
        size,
        mip_level_count: 1,
        sample_count: 1,
        dimension: TextureDimension::D2,
        format: TextureFormat::Rg8Uint,
        usage: TextureUsages::TEXTURE_BINDING | TextureUsages::COPY_DST,
        view_formats: &[],
    });
    queue.write_texture(
        texture.as_image_copy(),
        &texels,
        TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(2 * width), rows_per_image: None },
        size,
    );
    texture.create_view(&TextureViewDescriptor::default())
}
