class_name BackgroundMusic
extends AudioStreamPlayer

## 背景音乐：循环播放、开局淡入，菜单里的「音乐」按钮通过 set_enabled() 让它淡出 / 淡入。
##
## 这个节点挂在 main.tscn 的根下（不在开始界面里），所以幕布收起来之后音乐照常播。
## 换曲子只改本节点检查器里的 Stream；音量、渐入渐出的时长都在下面几个 @export 上调，
## 不用碰代码。开关状态变化会发 enabled_changed 信号，菜单按钮靠它刷新文字。

## 音乐最响时的音量（分贝）。背景音乐别盖过水声，默认压低到 -8。
@export_range(-60.0, 6.0, 0.5) var max_volume_db: float = -8.0
## 开局是否自动播放。关掉 = 一开始处于关闭状态，等别处调 set_enabled(true)。
## 注意：AudioStreamPlayer 原生也有个 autoplay，名字不能撞，所以这里叫 play_on_start。
@export var play_on_start: bool = true
## 淡入时长（秒）。填 0 = 一开声就是最大音量。
@export_range(0.0, 10.0, 0.05) var fade_in_time: float = 1.5
## 淡出时长（秒）。填 0 = 一按开关立刻安静。
@export_range(0.0, 10.0, 0.05) var fade_out_time: float = 0.8
## 「安静」的音量（分贝）。-60 dB 已经听不见，再小只会让淡出的尾巴拖得更久。
@export_range(-80.0, -20.0, 1.0) var silent_db: float = -60.0

## 开关状态变化时发一次，参数是「现在开着没有」。菜单按钮靠它刷新文字。
signal enabled_changed(enabled: bool)

var _enabled: bool = false   # 玩家想要的状态（淡出还在走时它已经是 false 了）
var _fade: Tween = null      # 正在跑的淡入 / 淡出；来回切开关时先掐掉旧的


func _ready() -> void:
	# MP3 的循环标记在导入时默认是关的，这里在运行时补上，换别的 mp3 也不用改 .import。
	var mp3: AudioStreamMP3 = stream as AudioStreamMP3
	if mp3 != null:
		mp3.loop = true
	volume_db = silent_db
	if play_on_start:
		_enabled = true
		play()
		_fade_to(max_volume_db, fade_in_time)


## 现在音乐是不是开着。淡出还没走完时就已经是 false 了。
func is_enabled() -> bool:
	return _enabled


## 开 / 关背景音乐。
## 开：从当前音量淡入（如果之前是关的，会接着原来的位置继续放）。
## 关：淡到听不见之后暂停，不丢播放位置。
func set_enabled(on: bool) -> void:
	if on == _enabled:
		return
	_enabled = on
	if on:
		if not playing:
			play()
		stream_paused = false
		_fade_to(max_volume_db, fade_in_time)
	else:
		_fade_to(silent_db, fade_out_time)
		if _fade == null:
			# 淡出时长填了 0，已经安静了，直接暂停
			stream_paused = true
		else:
			# 淡完再暂停；中途又开回来时 _fade_to() 会掐掉这条补间，不会误暂停
			_fade.finished.connect(_pause_playback, CONNECT_ONE_SHOT)
	enabled_changed.emit(_enabled)


## 开关按钮按一下就调它，返回切换后的状态。
func toggle() -> bool:
	set_enabled(not _enabled)
	return _enabled


## 淡出并彻底停住（退游戏前用）。已经关着就立刻返回，不白等。
func fade_out_and_stop() -> void:
	if not _enabled and not playing:
		return
	_enabled = false
	enabled_changed.emit(false)
	_fade_to(silent_db, fade_out_time)
	if _fade != null:
		await _fade.finished
	stop()
	_fade = null


## 把音量补间到目标值；时长为 0 时直接赋值。新的淡入淡出会掐掉上一条。
func _fade_to(target_db: float, duration: float) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	if duration <= 0.0:
		volume_db = target_db
		_fade = null
		return
	_fade = create_tween()
	_fade.tween_property(self, "volume_db", target_db, duration)


## 淡出结束：暂停播放但保留播放位置，下次打开能接着放。
func _pause_playback() -> void:
	stream_paused = true
