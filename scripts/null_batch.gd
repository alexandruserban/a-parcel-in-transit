extends "res://scripts/batch.gd"
## A batch that draws nothing: houses.gd sends the parts it already stamped from its template here.

func quad(_xf: Transform3D, _a: Vector3, _b: Vector3, _c: Vector3, _d: Vector3, _mat: Material, _out := Vector3.ZERO, _uv := 1.0, _sh := true) -> void: pass
func tri(_xf: Transform3D, _a: Vector3, _b: Vector3, _c: Vector3, _mat: Material, _out := Vector3.ZERO, _uv := 1.0, _sh := true) -> void: pass
func tri_uv(_xf: Transform3D, _a: Vector3, _b: Vector3, _c: Vector3, _ua: Vector2, _ub: Vector2, _uc: Vector2, _mat: Material, _out := Vector3.ZERO, _sh := true) -> void: pass
func box(_xf: Transform3D, _c: Vector3, _s: Vector3, _mat, _uv := 1.0, _sh := true, _bottom := false) -> void: pass
func mesh(_xf: Transform3D, _m: Mesh, _mat: Material, _sh := true, _flat := false, _uv := Vector2.ONE) -> void: pass
func polygon(_xf: Transform3D, _p: PackedVector2Array, _mat: Material, _uv := 1.0, _sh := true, _fit := Rect2()) -> void: pass
func prism(_xf: Transform3D, _p: PackedVector2Array, _d: float, _mat: Material, _uv := 1.0, _sh := true) -> void: pass
func ring_walls(_xf: Transform3D, _p: PackedVector2Array, _d: float, _mat: Material, _closed := true, _uv := 1.0, _sh := true, _in := false) -> void: pass
func strip(_xf: Transform3D, _o: PackedVector2Array, _i: PackedVector2Array, _mat: Material, _f := Vector3.BACK, _uv := 1.0, _sh := true) -> void: pass
func cylinder(_xf: Transform3D, _b: Vector3, _r0: float, _r1: float, _h: float, _segs: int, _mat: Material, _cap := true, _uv := 1.0, _sh := true, _st := 0.0, _sw := TAU) -> void: pass
