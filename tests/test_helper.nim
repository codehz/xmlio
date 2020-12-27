import unittest

import xmlio
import xmlio/typeid_default

type MyData = object of RootObj
  value: int

type MyRoot = object of RootObj
  name: string
  children: seq[ref MyData]

generateXmlElementHandler MyData, "595b110e-50cf-484a-b06e-78291edf4aab":
  discard

generateXmlElementHandler MyRoot, "827b04b8-0925-4897-9ca0-959601afc8e8":
  if self.name == "": raise newException(ValueError, "name is empty")

var registry = newSimpleRegistry()
var rootns = newSimpleXmlnsHandler()

rootns.registerType("root", ref MyRoot)
rootns.registerType("data", ref MyData)

registry["std"] = rootns

suite "helper":
  test "simple":
    const xml = """<root xmlns="std" name="test" />"""
    let root = readXml(registry, xml, ref MyRoot)
    check root.name == "test"
  test "has children":
    const xml = """<root xmlns="std" name="test"> <data value="5" /> <data value="6" /> </root>"""
    let root = readXml(registry, xml, ref MyRoot)
    check root.name == "test"
    check root.children.len == 2
    check root.children[0].value == 5
    check root.children[1].value == 6
