import htmlparser, strutils

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
  cache: string
  proxy: TypedProxy

impl StringHandler, XmlAttributeHandler:
  method addText*(self: ref StringHandler, text: string) =
    self.cache.add text
  method addEntity*(self: ref StringHandler, entity: string) =
    self.cache.add entityToUtf8 entity
  method verify*(self: ref StringHandler) =
    # empty is valid
    self.proxy.assign self.cache

proc createAttributeHandlerConcrete*(str: var string): ref StringHandler =
  new result
  result[].proxy = createProxy str

template buildTypedAttributeHandler*(T: static typedesc, body: untyped) =
  type TypedHandler* {.gensym.} = object of RootObj
    cache: string
    proxy: ptr T
  impl TypedHandler, XmlAttributeHandler:
    method addText*(self: ref TypedHandler, text: string) =
      self.cache.add text
    method addEntity*(self: ref TypedHandler, entity: string) =
      self.cache.add entityToUtf8 entity
    method verify*(self: ref TypedHandler) {.nimcall.} =
      body

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

proc createAttributeHandlerConcrete*[T: SomeInteger](val: var T): ref SomeIntegerHandler[T] =
  new result
  result[] = SomeIntegerHandler[T](cache: "", proxy: addr val)

type SeqHandler*[T] = object of RootObj
  proxy: ptr seq[T]

forall do (T: typed):
  impl SeqHandler[T], XmlAttributeHandler:
    method getChildProxy*(self: ref SeqHandler[T]): TypedProxy =
      let len = self.proxy[].len
      self.proxy[].setLen(len + 1)
      createProxy addr self.proxy[][len]
    method verify*(self: ref SeqHandler[T]) =
      discard

proc createAttributeHandlerConcrete*[T](val: var seq[T]): ref SeqHandler[T] =
  new result
  result.proxy = addr val

type ProxyHandler* = object of RootObj
  used: bool
  proxy: TypedProxy

impl ProxyHandler, XmlAttributeHandler:
  method getChildProxy*(self: ref ProxyHandler): TypedProxy =
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