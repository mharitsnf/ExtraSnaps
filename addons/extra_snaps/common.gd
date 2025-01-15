@tool
class_name ESCommon extends RefCounted

enum RootItems {
    SURFACE_TYPE_SUBMENU,
    SNAP_TYPE_SUBMENU,
    CONFIGURE_MASK
}

enum SurfaceTypes {
    COLLISION_OBJECTS,
    MESHES,
}

enum SnapTypes {
    SNAP_TO_SURFACE,
    SNAP_ALONG_NORMAL
}

const DIALOG_CONFIGURE_MASK_SCENE: PackedScene = preload("./dialog_configure_mask.tscn")
const ES_MENU_BUTTON_PSCN: PackedScene = preload("./es_menu_button.tscn")
const SETTINGS_FILE_PATH = "user://extra_snaps.cfg"

# https://github.com/godotengine/godot-proposals/issues/2411
const INT32_MAX = 4294967295
# https://docs.godotengine.org/en/stable/classes/class_float.html#
const FLOAT64_MAX = 1.79769e308

const SCENARIO_RAY_DISTANCE = 5000.
