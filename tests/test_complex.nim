import unittest, streams, os

import xmlio
import xmlio/typeid_default

import vtable

trait Repository:
  method getName*(self: ref Repository): string
  method fetchPackageLists*(self: ref Repository): seq[string]

registerTypeId(ref Repository, "e71dc461-8af1-4206-a3a4-d5fe55985fd7")

declareXmlElement:
  type RootDocument {.id: "9afd3387-f6c9-4361-a279-e87b26862140".} = object of RootObj
    version {.check(value != 1, r"version mismatch").}: int
    children: seq[ref Repository]

declareXmlElement:
  type LocalRepo {.id: "f11bdf51-eb0b-4d2d-9d2c-e0e0394cb64c".} = object of RootObj
    name {.check(value == "", r"name is empty").}: string
    path {.check(value == "", r"path is empty").}: string

impl LocalRepo, Repository:
  method getName(self: ref LocalRepo): string = self.name
  method fetchPackageLists(self: ref LocalRepo): seq[string] = @[]

declareXmlElement:
  type RemoteRepo {.id: "22187be0-4aea-4b78-9a73-fc03c7b948c5".} = object of RootObj
    name {.check(value == "", r"name is empty").}: string
    url {.check(value == "", r"url is empty").}: string

impl RemoteRepo, Repository:
  method getName(self: ref RemoteRepo): string = self.name
  method fetchPackageLists(self: ref RemoteRepo): seq[string] = @[]

declareXmlElement:
  type PrefixRepo {.
      id: "a701c97a-45f2-4326-96af-58808fdc49fe",
      children: child.} = object of RootObj
    prefix {.check(value == "", r"prefix is empty").}: string
    child {.check(value == nil, r"no children").}: ref Repository

impl PrefixRepo, Repository:
  method getName(self: ref PrefixRepo): string = self.prefix & self.child.getName()
  method fetchPackageLists(self: ref PrefixRepo): seq[string] = self.child.fetchPackageLists()

var registry = new SimpleRegistry
var rootns = new SimpleXmlnsHandler
var customns = new SimpleXmlnsHandler

rootns.registerType("root", ref RootDocument)
rootns.registerType("local", ref LocalRepo, ref Repository)
rootns.registerType("remote", ref RemoteRepo, ref Repository)
customns.registerType("prefix", ref PrefixRepo, ref Repository)

registry["std"] = rootns
registry["custom"] = customns

suite "helper":
  test "empty":
    var root = readXml(registry, """<root xmlns="std" version="1" />""", ref RootDocument)
    check root.version == 1
    check root.children.len == 0

  test "from files":
    var strs = openFileStream(currentSourcePath / ".." / "complex.xml")
    var root = readXml(registry, strs, "complex.xml", ref RootDocument)
    check root.version == 1
    require root.children.len == 3
    check root.children[0].getName() == "local"
    check root.children[1].getName() == "local 2"
    check root.children[2].getName() == "remote"

  test "custom xmlns":
    var strs = openFileStream(currentSourcePath / ".." / "custom.xml")
    var root = readXml(registry, strs, "custom.xml", ref RootDocument)
    check root.version == 1
    require root.children.len == 2
    check root.children[0].getName() == "local"
    check root.children[1].getName() == "test-local 2"
