import unittest

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
        let tmp = new RootElementHandler
        proxy.assign tmp
        tmp
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
    let root = readXml(new SimpleRegistry, """<root xmlns="test" name="test" />""", ref RootElementHandler)
    check root.name == "test"

  test "alternative":
    const xml = """<root xmlns="test"><root.name>test2</root.name></root>"""
    let root = readXml(new SimpleRegistry, xml, ref RootElementHandler)
    check root.name == "test2"

  test "whitespace":
    const xml = """<root xmlns="test">   <root.name>test3</root.name></root>"""
    let root = readXml(new SimpleRegistry, xml, ref RootElementHandler)
    check root.name == "test3"

  test "html entity":
    const xml = """<root xmlns="test"><root.name>&lt;script&gt;</root.name></root>"""
    let root = readXml(new SimpleRegistry, xml, ref RootElementHandler)
    check root.name == "<script>"

  test "duplicated key":
    const xml = """<root xmlns="test" name="123"><root.name>456</root.name></root>"""
    expect XmlError:
      discard readXml(new SimpleRegistry, xml, ref RootElementHandler)