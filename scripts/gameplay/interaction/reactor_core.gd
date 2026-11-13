class_name ReactorCore
extends Node3D
## Реактор — украшение карты. На клиентах, пока идёт саботаж, ядро (сетка Glow внутри
## модели) и свет (узел Light) краснеют и пульсируют. На сервере и без окна ничего не делает.

## Цвет тревоги.
const ALERT_COLOR: Color = Color(1.0, 0.12, 0.08)
## Частота пульса, рад/с.
const PULSE_SPEED: float = 7.0
## Во сколько раз ядро и свет ярче на пике пульса.
const ALERT_ENERGY_BOOST: float = 2.5
## Насколько ядро тускнеет между пиками (доля обычной яркости).
const ALERT_ENERGY_FLOOR: float = 0.6

var _time: float = 0.0
## Свои копии материалов ядра и их обычные цвета: общие материалы модели не трогаем.
var _materials: Array[StandardMaterial3D] = []
var _calm_emissions: Array[Color] = []
var _calm_energies: Array[float] = []
var _calm_light_color: Color = Color.WHITE
var _calm_light_energy: float = 0.0

@onready var _glow: MeshInstance3D = get_node_or_null(^"Model/Glow") as MeshInstance3D
@onready var _light: OmniLight3D = get_node_or_null(^"Light") as OmniLight3D


func _ready() -> void:
	set_process(false)
	if Net.is_server() or DisplayServer.get_name() == "headless":
		return
	_copy_glow_materials()
	if _light != null:
		_calm_light_color = _light.light_color
		_calm_light_energy = _light.light_energy
	Game.sabotage.started.connect(_on_sabotage_changed)
	Game.sabotage.ended.connect(_on_sabotage_changed.unbind(1))
	# Опоздавший мог получить карту уже во время саботажа.
	_on_sabotage_changed()


func _process(delta: float) -> void:
	_time += delta
	# 0..1: ноль — между пиками, единица — пик.
	var pulse: float = 0.5 + 0.5 * sin(_time * PULSE_SPEED)
	var boost: float = lerpf(ALERT_ENERGY_FLOOR, ALERT_ENERGY_BOOST, pulse)
	for index: int in _materials.size():
		_materials[index].emission = ALERT_COLOR
		_materials[index].emission_energy_multiplier = _calm_energies[index] * boost
	if _light != null:
		_light.light_color = ALERT_COLOR
		_light.light_energy = _calm_light_energy * boost


func _on_sabotage_changed() -> void:
	var is_alert: bool = Game.sabotage.active
	set_process(is_alert)
	if is_alert:
		_time = 0.0
		return
	for index: int in _materials.size():
		_materials[index].emission = _calm_emissions[index]
		_materials[index].emission_energy_multiplier = _calm_energies[index]
	if _light != null:
		_light.light_color = _calm_light_color
		_light.light_energy = _calm_light_energy


func _copy_glow_materials() -> void:
	if _glow == null or _glow.mesh == null:
		return
	for surface: int in _glow.mesh.get_surface_count():
		var source: StandardMaterial3D = _glow.mesh.surface_get_material(surface) as StandardMaterial3D
		if source == null:
			continue
		var copy: StandardMaterial3D = source.duplicate() as StandardMaterial3D
		copy.emission_enabled = true
		_glow.set_surface_override_material(surface, copy)
		_materials.append(copy)
		_calm_emissions.append(copy.emission)
		_calm_energies.append(copy.emission_energy_multiplier)
