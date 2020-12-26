import typeid

type TypedProxy* = object
  id: TypeId
  rawptr*: pointer

proc id*(proxy: TypedProxy): TypeId = proxy.id

proc createProxy*[T](p: ptr T): TypedProxy =
  result.id = typeid T
  result.rawptr = p

proc createProxy*[T](p: var T): TypedProxy =
  result.id = typeid T
  result.rawptr = addr p

proc verify*(proxy: TypedProxy, T: typedesc): bool = proxy.id == typeid(T)

proc assign*[T](proxy: TypedProxy, val: T) =
  if not proxy.verify T:
    raise newException(ValueError, "typeid not matched")
  cast[ptr T](proxy.rawptr)[] = val

proc get*(proxy: TypedProxy, T: typedesc): T =
  if not proxy.verify T:
    raise newException(ValueError, "typeid not matched")
  cast[ptr T](proxy.rawptr)[]
