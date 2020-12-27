import typeid

type TypedProxy* = object
  ## A proxy for access runtime unknown object
  id: TypeId
  rawptr*: pointer

proc id*(proxy: TypedProxy): TypeId =
  ## Get typeid from proxy
  proxy.id

proc createProxy*[T](p: ptr T): TypedProxy =
  ## Create proxy from pointer
  result.id = typeid T
  result.rawptr = p

proc createProxy*[T](p: var T): TypedProxy =
  ## Create proxy from variable
  result.id = typeid T
  result.rawptr = addr p

proc verify*(proxy: TypedProxy, T: typedesc): bool =
  ## Check type inside proxy
  proxy.id == typeid(T)

proc assign*[T](proxy: TypedProxy, val: T) =
  ## Assign new value with proxy
  if not proxy.verify T:
    raise newException(ValueError, "typeid not matched")
  cast[ptr T](proxy.rawptr)[] = val

proc get*(proxy: TypedProxy, T: typedesc): T =
  ## Try get typed value from proxy
  if not proxy.verify T:
    raise newException(ValueError, "typeid not matched")
  cast[ptr T](proxy.rawptr)[]

template getOrPut*[T: ref](proxy: TypedProxy, value: T): T =
  ## Try get typed value or set new value
  if not proxy.verify typeof value:
    raise newException(ValueError, "typeid not matched")
  if cast[ptr typeof value](proxy.rawptr)[] == nil:
    cast[ptr typeof value](proxy.rawptr)[] = value
  cast[ptr typeof value](proxy.rawptr)[]