# Extra Snaps

Godot 4.X plugin that adds extra snapping functionalities for Node3D objects.


https://github.com/mharitsnf/ExtraSnaps/assets/22760908/5541ceac-db8f-43ee-b863-8a9438ad166b


# Installation
There are two approaches to install the plugin as provided below. Whichever method you choose, if the plugin does not appear / work after the installation, try reloading the current project.

## Asset Library
The plugin is available in the asset library for 4.2 projects.
1. Search for "Extra Snaps" in the asset library and download the plugin.
2. Enable the project from the project settings.

## Manual installation
Use the manual installation for 4.1 or 4.0 projects: 
1. Download the project as ZIP.
2. Move the `extra_snaps` folder inside the `res://addons` folder into your `res://addons` folder in your project.
3. Enable the plugin from the project settings.

# How to Use
## Moving Objects
- Select a `Node3D` object.
- While pressing `CTRL` / `CMD` + `W`, move your cursor around to snap the selected object onto other `PhysicsBody3D` or `CSGShape3D` objects (any objects with collisions, basically).
- Release `CTRL` / `CMD` + `W` to confirm.

## Snapping Modes

![Screenshot 2024-05-06 142219](https://github.com/mharitsnf/ExtraSnaps/assets/22760908/aadf828b-54c4-4c90-a8b7-faac2686848e)

Currently, the plugin supports two snapping modes: *Snap to Surface* and *Snap Along Normals*.
*Snap to surface* allows the selected object to snap to a specific surface, while *Snap Along Normals* also aligns the selected object along the surface normal.
