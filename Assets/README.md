# App icon

Generated with the built-in image_gen tool, then packaged into the standard macOS icon sizes with `scripts/build-icon.sh`.

Source: `AppIcon.png`. Bundle asset: `AppIcon.icns`.

Original generation prompt:

> Create one polished native macOS application icon for Simple Video Recorder, a private live mirror and video recording app for speech practice. Square 1024x1024 PNG with truly transparent background outside a centered rounded-square tile occupying 88% of canvas. Deep midnight navy tile with subtle blue/teal glass gradient and restrained dimensional edge lighting. Center a simple luminous ivory rounded speech bubble containing three rounded vertical audio waveform bars, with a small coral-red recording dot integrated at its upper right. Bold minimal silhouette, premium macOS craftsmanship, readable at 32px. Straight-on orthographic view, no perspective tilt. No text, letters, screenshots, mockup device, watermark, or extra objects. Deliver only the finished icon asset.

Matte revision (built-in image_gen, September 6, 2026):

> Use case: style-transfer. Edit the attached Simple Video Recorder macOS app icon. Preserve its recognizable layout: blue rounded-square tile, ivory white speech bubble, three blue vertical waveform bars, small red recording dot at upper right. Make it understated and native macOS in style: matte medium blue tile with only a very gentle tonal gradient, clean nearly flat white bubble, flat blue bars, solid coral-red dot with a simple white ring. Remove neon cyan edge lights, shiny specular highlights, glass reflections, glowing halos, thick bevels and inflated 3D surfaces. Keep only very subtle soft depth/shadow. Straight-on square app icon with consistent rounded corners and transparent outer margins, crisp readable silhouette at small sizes. No text or extra objects. Output square PNG with actual transparency outside tile.

Transparency cleanup prompt:

> Use case: background-extraction. Keep this exact matte blue macOS Simple Video Recorder icon unchanged. Remove ONLY the gray-and-white checkerboard background outside the rounded blue tile. Output real PNG alpha transparency outside the icon, NOT a painted checkerboard and NOT an opaque background. Preserve the tile, speech bubble, waveform bars and recording dot exactly, with crisp antialiased edge. Transparent background is essential for installed macOS app icon.
