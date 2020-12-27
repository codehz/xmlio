import unittest, streams, os

import xmlio
import xmlio/typeid_default

import vtable

trait Repository:
  method getName*(self: ref Repository): string
  method fetchPackageLists*(self: ref Repository): seq[string]

registerTypeId(ref Repository, "e71dc461-8af1-4206-a3a4-d5fe55985fd7")

type RootDocument = object of RootObj
  version: int
  children: seq[ref Repository]

generateXmlElementHandler RootDocument, "9afd3387-f6c9-4361-a279-e87b26862140":
  if self.version != 1: raise newException(ValueError, "version mismatch")

type LocalRepo = object of RootObj
  name: string
  path: string

impl LocalRepo, Repository:
  method getName(self: ref LocalRepo): string = self.name
  method fetchPackageLists(self: ref LocalRepo): seq[string] = @[]

generateXmlElementHandler LocalRepo, "f11bdf51-eb0b-4d2d-9d2c-e0e0394cb64c":
  if self.name == "": raise newException(ValueError, "name is empty")
  if self.path == "": raise newException(ValueError, "path is empty")

type RemoteRepo = object of RootObj
  name: string
  url: string

impl RemoteRepo, Repository:
  method getName(self: ref RemoteRepo): string = self.name
  method fetchPackageLists(self: ref RemoteRepo): seq[string] = @[]

generateXmlElementHandler RemoteRepo, "22187be0-4aea-4b78-9a73-fc03c7b948c5":
  if self.name == "": raise newException(ValueError, "name is empty")
  if self.url == "": raise newException(ValueError, "url is empty")

type PrefixRepo = object of RootObj
  prefix: string
  children: ref Repository

impl PrefixRepo, Repository:
  method getName(self: ref PrefixRepo): string = self.prefix & self.children.getName()
  method fetchPackageLists(self: ref PrefixRepo): seq[string] = self.children.fetchPackageLists()

generateXmlElementHandler PrefixRepo, "a701c97a-45f2-4326-96af-58808fdc49fe":
  if self.prefix == "": raise newException(ValueError, "prefix is empty")
  if self.children == nil: raise newException(ValueError, "no children")

var registry = newSimpleRegistry()
var rootns = newSimpleXmlnsHandler()
var customns = newSimpleXmlnsHandler()

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
