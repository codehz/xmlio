import unittest

import xmlio
import xmlio/typeid_default

declareXmlElement:
  type MyRoot {.id: "175f7482-b642-4440-a61e-04ad5a2789b9".} = object of RootObj
    name: string
    xtype {.name: "type".}: string

var registry = new SimpleRegistry
var rootns = new SimpleXmlnsHandler

rootns.registerType("root", ref MyRoot)

registry["std"] = rootns

suite "reserved word":
  test "simple":
    const xml = """<root xmlns="std" name="test" type="value" />"""
    let root = readXml(registry, xml, ref MyRoot)
    check root.name == "test"
    check root.xtype == "value"