XMLIO
=====

Mapping nim type to xml node, use xaml-like semantics, `<root name="123" />` equal to `<root><root.name>123</root.name></root>`.

Early development stage, break changes are expected!

Features
--------

1. Works with dynlib, can load new type from so/dll file, that's why I make this package (and vtable)
2. Identify type by UUID, so it can be choosen manually to avoid conflict between dynlibs
3. Use xmlns to avoid name conflict

Basic usage
-----------

DOCS: WIP (see [tests](tests) for more examples)

1. Import xmlio and xmlio/typeid_default
2. Define your object type, only `string | SomeInteger | seq[T] | ref T` field are supported (for now)
3. Register your type by using `generateXmlElementHandler`, you need provide a UUID for it, and put verify code in body
4. Define the xmlns and xmlns registry instance
5. Call `readXml` to parse xml
6. Done!

```nim
import xmlio, xmlio/typeid_default

type MyRoot = object of RootObj
  name: string
  secret: int32

generateXmlElementHandler MyRoot, "015a1611-9a98-4cb7-b77f-c7dc56b44507":
  if self.name == "": raise newException(ValueError, "name should not be empty!")
  if self.secret != 123: raise newException(ValueError, "secret is not matched")

var registry = newSimpleRegistry()
var rootns = newSimpleXmlnsHandler()

rootns.registerType("root", ref MyRoot)
registry["std"] = rootns

var root = readXml(registry, """<root xmlns="std" name="name"><root.secret>123</root.secret></root>""", ref MyRoot)
echo root.name # name
echo root.secret # 123
```