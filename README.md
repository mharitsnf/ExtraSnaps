# Extra Snaps

Godot 4.X plugin that adds extra snapping functionalities for Node3D objects.

# Installation
1. Download the project as ZIP.
2. Move the `extra_snaps` folder inside the `res://addons` folder into your `res://addons` folder in your project.
3. Enable the plugin from the project settings.

# How to Use
## Moving Objects
- Select a `Node3D` object.
- While selecting `CTRL` / `CMD` + `W`, move your cursor around to snap the selected object onto other `PhysicsBody3D` or `CSGShape3D` objects (any objects with collisions basically).
- Release `CTRL` / `CMD` + `W` to confirm your new transform.

## Snapping Modes
Currently, the plugin supports two snapping modes: *Snap to Surface* and *Snap Along Normals*.
*Snap to surface* allows the selected object to snap to a specific surface, while *Snap Along Normals* also aligns the selected object along the surface normal.