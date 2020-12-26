import unittest, streams

import xmlio, vtable
import xmlio/[types, typeid_default]

type
  SimpleRegistry = object of RootObj
  SimpleNsHandler = object of RootObj
  RootElementHandler* = object of RootObj
    name*: string

registerTypeId(ref RootElementHandler, "ef50487c-c4ae-440b-a811-6cbe599c2d2d")

impl RootElementHandler, XmlElementHandler:
  method getAttributeHandler*(self: ref RootElementHandler, key: string): ref XmlAttributeHandler =
    case key:
    of "name": createAttributeHandler(self.name)
    else: raise newException(ValueError, "unknown attribute: " & key)
  method verify*(self: ref RootElementHandler) =
    if self.name == "":
      raise newException(ValueError, "name attribute required")

impl SimpleNsHandler, XmlnsHandler:
  method createElement*(self: ref SimpleNsHandler, name: string, proxy: TypedProxy): ref XmlElementHandler =
    case name:
    of "root":
      if proxy.verify(ref RootElementHandler):
        proxy.get(ref RootElementHandler)
      else:
        raise newException(ValueError, "invalid type")
    else:
      raise newException(ValueError, "invalid element: " & name)

impl SimpleRegistry, XmlnsRegistry:
  method resolveXmlns*(self: ref SimpleRegistry, name: string): ref XmlnsHandler =
    case name:
    of "test": new SimpleNsHandler
    else: raise newException(ValueError, "invalid xmlns")

suite "simple":
  test "simple case":
    var strs = newStringStream("""<root xmlns="test" name="test" />""")
    var ctx = newXmlContext(new SimpleRegistry, strs, "input")
    var root = new RootElementHandler
    ctx.extract root
    check root.name == "test"

  test "alternative":
    var strs = newStringStream("""<root xmlns="test"><root.name>test2</root.name></root>""")
    var ctx = newXmlContext(new SimpleRegistry, strs, "input")
    var root = new RootElementHandler
    ctx.extract root
    check root.name == "test2"

  test "html entity":
    var strs = newStringStream("""<root xmlns="test"><root.name>&lt;script&gt;</root.name></root>""")
    var ctx = newXmlContext(new SimpleRegistry, strs, "input")
    var root = new RootElementHandler
    ctx.extract root
    check root.name == "<script>"