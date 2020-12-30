import tables

import vtable

import traits, typed_proxy, typeid

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
  factory: Table[string, TableRef[TypeId, FactoryFunc]]

impl SimpleXmlnsHandler, XmlnsHandler:
  method createElement*(self: ref SimpleXmlnsHandler, name: string, proxy: TypedProxy): ref XmlElementHandler =
    result = self.factory[name][proxy.id](proxy)
    if result == nil:
      raise newException(ValueError, "unsupported element")

proc `[]=`*(self: ref SimpleXmlnsHandler, key: (string, TypeId), fn: FactoryFunc) =
  let (name, id) = key
  let subtab = if not (name in self.factory):
    let tmp = newTable[TypeId, FactoryFunc]()
    self.factory[name] = tmp
    tmp
  else:
    self.factory[name]
  subtab[id] = fn

proc registerType*(self: ref SimpleXmlnsHandler, name: string, desc: typedesc) =
  self[(name, typeid desc)] = proc (proxy: TypedProxy): ref XmlElementHandler =
    let tmp = new desc
    proxy.assign tmp
    tmp

proc registerType*(self: ref SimpleXmlnsHandler, name: string, desc: typedesc, ifce: typedesc) =
  self[(name, typeid ifce)] = proc (proxy: TypedProxy): ref XmlElementHandler =
    let tmp = new desc
    assign[ifce](proxy, tmp)
    tmp

proc newSimpleXmlnsHandler*(): ref SimpleXmlnsHandler =
  new result
  result[] = SimpleXmlnsHandler(factory: initTable[string, TableRef[TypeId, FactoryFunc]]())