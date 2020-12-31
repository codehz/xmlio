import htmlparser, strutils, tables, options

import vtable

import traits, typed_proxy, typeid

type
  HasToXmlAttributeHandler = concept ref v
    toXmlAttributeHandler(v)
  HasConcrete = concept var v
    createAttributeHandlerConcrete(v)

proc createAttributeHandler*(val: ref XmlAttributeHandler): ref XmlAttributeHandler = val
proc createAttributeHandler*(val: ref HasToXmlAttributeHandler): ref XmlAttributeHandler =
  mixin toXmlAttributeHandler
  toXmlAttributeHandler val
proc createAttributeHandler*(val: var HasConcrete): ref XmlAttributeHandler =
  mixin toXmlAttributeHandler
  mixin createAttributeHandlerConcrete
  toXmlAttributeHandler createAttributeHandlerConcrete val

type StringHandler* = object of RootObj
  proxy: ptr string

impl StringHandler, XmlAttributeHandler:
  method addText*(self: ref StringHandler, text: string) =
    self.proxy[].add text
  method addEntity*(self: ref StringHandler, entity: string) =
    self.proxy[].add entityToUtf8 entity
  method verify*(self: ref StringHandler) =
    discard

proc createAttributeHandlerConcrete*(str: var string): ref StringHandler =
  new result
  result[].proxy = addr str

type BoolHandler* = object of RootObj
  cache: string
  proxy: ptr bool

impl BoolHandler, XmlAttributeHandler:
  method addText*(self: ref BoolHandler, text: string) =
    self.cache.add text
  method addEntity*(self: ref BoolHandler, entity: string) =
    self.cache.add entityToUtf8 entity
  method verify*(self: ref BoolHandler) {.nimcall.} =
    self.proxy[] = parseBool(self.cache)

proc createAttributeHandlerConcrete*(val: var bool): ref BoolHandler =
  new result
  result[].proxy = addr val

template buildTypedAttributeHandler*(body: untyped) =
  type T {.gensym.} = typeof(body(""))
  type TypedHandler* {.gensym.} = object of RootObj
    cache: string
    proxy: ptr T
  impl TypedHandler, XmlAttributeHandler:
    method addText*(self: ref TypedHandler, text: string) =
      self.cache.add text
    method addEntity*(self: ref TypedHandler, entity: string) =
      self.cache.add entityToUtf8 entity
    method verify*(self: ref TypedHandler) {.nimcall.} =
      self.proxy[] = body(self.cache)

  proc createAttributeHandlerConcrete*(val: var T): ref TypedHandler =
    new result
    result[].proxy = addr val

type SomeIntegerHandler*[T] = object of RootObj
  cache: string
  proxy: ptr T

forall do (T: typed):
  impl SomeIntegerHandler[T], XmlAttributeHandler:
    method addText*(self: ref SomeIntegerHandler[T], text: string) =
      self.cache.add text
    method addEntity*(self: ref SomeIntegerHandler[T], entity: string) =
      self.cache.add entityToUtf8 entity
    method verify*(self: ref SomeIntegerHandler[T]) =
      when T is SomeSignedInt:
        self.proxy[] = T parseInt(self.cache.strip())
      elif T is SomeUnsignedInt:
        self.proxy[] = T parseUInt(self.cache.strip())
      else:
        discard

proc createAttributeHandlerConcrete*[T: SomeInteger](val: var T):
    ref SomeIntegerHandler[T] =
  new result
  result[] = SomeIntegerHandler[T](cache: "", proxy: addr val)

type SeqHandler*[T] = object of RootObj
  proxy: ptr seq[T]

forall do (T: typed):
  impl SeqHandler[T], XmlAttributeHandler:
    method getChildProxy*(self: ref SeqHandler[T]): XmlChild =
      let len = self.proxy[].len
      self.proxy[].setLen(len + 1)
      createProxy addr self.proxy[][len]
    method verify*(self: ref SeqHandler[T]) =
      discard

proc createAttributeHandlerConcrete*[T: ref](val: var seq[T]): ref SeqHandler[T] =
  new result
  result.proxy = addr val

type StringTableHandler*[T] = object of RootObj
  proxy: ptr Table[string, T]

type StringTableProxy[T] = object of RootObj
  proxy: ptr Table[string, T]
  name: Option[string]

forall do (T: typed):
  impl StringTableProxy[T], XmlAttachedAttributeHandler:
    method setAttribute(
      self: ref StringTableProxy[T],
      key: string,
      value: string) =
      if key == "key":
        if self.name.isSome():
          raise newException(ValueError, "duplicated attached attribute")
        if value in self.proxy[]:
          raise newException(ValueError, "duplicated key")
        self.name = some value
      else:
        raise newException(ValueError, "invalid attached attribute")
    method generateProxy(self: ref StringTableProxy[T]): TypedProxy =
      if self.name.isSome():
        self.proxy[][self.name.get()] = nil
        createProxy self.proxy[][self.name.get()]
      else:
        raise newException(ValueError, "attached attribute key not set")
  impl StringTableHandler[T], XmlAttributeHandler:
    method getChildProxy*(self: ref StringTableHandler[T]): XmlChild =
      let tmp = new StringTableProxy[T]
      tmp.proxy = self.proxy
      toXmlAttachedAttributeHandler tmp
    method verify*(self: ref StringTableHandler[T]) =
      discard

proc createAttributeHandlerConcrete*[T: ref](val: var Table[string, T]): ref StringTableHandler[T] =
  new result
  result.proxy = addr val

type ProxyHandler* = object of RootObj
  used: bool
  proxy: TypedProxy

impl ProxyHandler, XmlAttributeHandler:
  method getChildProxy*(self: ref ProxyHandler): XmlChild =
    if self.used:
      raise newException(ValueError, "already used")
    self.used = true
    return self.proxy
  method verify*(self: ref ProxyHandler) =
    if not self.used:
      raise newException(ValueError, "not used")

proc createAttributeHandlerConcrete*[T: ref](val: var T): ref ProxyHandler =
  new result
  result.proxy = createProxy val
