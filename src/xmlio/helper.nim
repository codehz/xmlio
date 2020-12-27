import tables

import vtable

import traits, typed_proxy

type SimpleRegistry* = object of RootObj
  nsmap: Table[string, ref XmlnsHandler]

impl SimpleRegistry, XmlnsRegistry:
  method resolveXmlns*(self: ref SimpleRegistry, name: string): ref XmlnsHandler =
    self.nsmap[name]

proc newSimpleRegistry*(): ref SimpleRegistry =
  new result
  result[] = SimpleRegistry(nsmap: initTable[string, ref XmlnsHandler]())

proc `[]=`*(registry: ref SimpleRegistry, name: string, handler: ref XmlnsHandler) =
  registry.nsmap[name] = handler

type FactoryFunc = proc (proxy: TypedProxy): ref XmlElementHandler {.nimcall.}

type SimpleXmlnsHandler* = object of RootObj
  factory: Table[string, FactoryFunc]

impl SimpleXmlnsHandler, XmlnsHandler:
  method createElement*(self: ref SimpleXmlnsHandler, name: string, proxy: TypedProxy): ref XmlElementHandler =
    self.factory[name](proxy)

proc `[]=`*(self: ref SimpleXmlnsHandler, name: string, handler: FactoryFunc) =
  self.factory[name] = handler

proc registerType*(self: ref SimpleXmlnsHandler, name: string, desc: typedesc) =
  self.factory[name] = proc (proxy: TypedProxy): ref XmlElementHandler =
    if proxy.verify(desc):
      let tmp = new desc
      proxy.assign tmp
      tmp
    else:
      raise newException(ValueError, "invalid type for element")

proc registerType*(self: ref SimpleXmlnsHandler, name: string, desc: typedesc, ifce: typedesc) =
  self.factory[name] = proc (proxy: TypedProxy): ref XmlElementHandler =
    if proxy.verify(ifce):
      let tmp = new desc
      assign[ifce](proxy, tmp)
      tmp
    else:
      raise newException(ValueError, "invalid type for element")

proc newSimpleXmlnsHandler*(): ref SimpleXmlnsHandler =
  new result
  result[] = SimpleXmlnsHandler(factory: initTable[string, FactoryFunc]())