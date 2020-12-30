import unittest, streams, os, tables

import xmlio
import xmlio/typeid_default

import vtable

trait Task:
  method execute(self: ref Task): string

registerTypeId(ref Task, "1bcbfd7b-c4d5-44ee-9b24-f259707bf67d")

declareXmlElement:
  type Document {.
      id: "b0633984-9832-483e-a61d-a2b7943471f1"
      children: tasks.} = object of RootObj
    tasks: Table[string, ref Task]

declareXmlElement:
  type HelloTask {.id: "e8c6a635-7ce3-4efc-af0a-173434fc71f1".} = object of RootObj

impl HelloTask, Task:
  method execute(self: ref HelloTask): string = "hello world"

declareXmlElement:
  type SayTask {.
      id: "e8c6a635-7ce3-4efc-af0a-173434fc71f1",
      children: content.} = object of RootObj
    content {.check(value == "", r"invalid content").}: string

impl SayTask, Task:
  method execute(self: ref SayTask): string = self.content

declareXmlElement:
  type TableTask {.id: "604f7189-cfe6-469b-a29d-0f7ea7975b3b".} = object of RootObj
    table: Table[string, ref Task]

impl TableTask, Task:
  method execute(self: ref TableTask): string =
    for key, subtask in self.table:
      result.add key & ":" & subtask.execute() & ";"

var registry = new SimpleRegistry
var rootns = new SimpleXmlnsHandler

rootns.registerType("root", ref Document)
rootns.registerType("hello", ref HelloTask, ref Task)
rootns.registerType("say", ref SayTask, ref Task)
rootns.registerType("kv", ref TableTask, ref Task)

registry["std"] = rootns

suite "attached":
  test "empty":
    var root = readXml(registry, """<root xmlns="std" />""", ref Document)
    check root.tasks.len == 0

  test "basic":
    var strs = openFileStream(currentSourcePath / ".." / "attached.xml")
    var root = readXml(registry, strs, "attached.xml", ref Document)
    check root.tasks["hello"].execute() == "hello world"
    check root.tasks["say1"].execute() == "content"
    check root.tasks["say2"].execute() == "content2"

  test "table embed":
    var strs = openFileStream(currentSourcePath / ".." / "attached_table.xml")
    var root = readXml(registry, strs, "attached_table.xml", ref Document)
    check root.tasks["hello"].execute() == "hello world"
    check root.tasks["kv"].execute() == "test:hello world;"
