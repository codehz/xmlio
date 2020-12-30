import unittest

import xmlio
import xmlio/typeid_default

declareXmlElement:
  type MyData {.id: "71ea5d8c-32fc-4757-a7a6-cd4245cef13f".} = object of RootObj
    value: int

declareXmlElement:
  type MyRoot {.id: "175f7482-b642-4440-a61e-04ad5a2789b9".} = object of RootObj
    name: string
    children: seq[ref MyData]

var registry = new SimpleRegistry
var rootns = new SimpleXmlnsHandler

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
