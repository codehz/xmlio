import unittest, streams

import xmlio
import xmlio/typeid_default

type MyData = object of RootObj
  value: int

type MyRoot = object of RootObj
  name: string
  children: seq[ref MyData]

generateXmlELementHandler MyData, "595b110e-50cf-484a-b06e-78291edf4aab":
  discard

generateXmlELementHandler MyRoot, "827b04b8-0925-4897-9ca0-959601afc8e8":
  if self.name == "": raise newException(ValueError, "name is empty")

var registry = newSimpleRegistry()
var rootns = newSimpleXmlnsHandler()

rootns["root"] = ref MyRoot
rootns["data"] = ref MyData

registry["std"] = rootns

suite "helper":
  test "simple":
    var root = new MyRoot
    var strs = newStringStream("""<root xmlns="std" name="test" />""")
    var ctx = newXmlContext(registry, strs, "input")
    ctx.extract root
    check root.name == "test"
  test "has children":
    var root = new MyRoot
    var strs = newStringStream("""<root xmlns="std" name="test"> <data value="5" /> <data value="6" /> </root>""")
    var ctx = newXmlContext(registry, strs, "input")
    ctx.extract root
    check root.name == "test"
    check root.children.len == 2
    check root.children[0].value == 5
    check root.children[1].value == 6
