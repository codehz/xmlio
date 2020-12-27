import macros

import vtable
import vtable/utils

import typed_proxy

trait XmlAttributeHandler:
  method getChildProxy*(self: ref XmlAttributeHandler): TypedProxy =
    raise newException(ValueError, "unsupported")
  method addText*(self: ref XmlAttributeHandler, text: string) =
    raise newException(ValueError, "unsupported")
  method addWhitespace*(self: ref XmlAttributeHandler, space: string) = discard
  method addEntity*(self: ref XmlAttributeHandler, entity: string) =
    raise newException(ValueError, "unsupported")
  method addSpecial*(self: ref XmlAttributeHandler, special: string) =
    raise newException(ValueError, "unsupported")
  method verify*(self: ref XmlAttributeHandler)

trait XmlElementHandler:
  method getAttributeHandler*(self: ref XmlElementHandler, key: string): ref XmlAttributeHandler =
    raise newException(ValueError, "unsupported")
  method setAttributeString*(self: ref XmlElementHandler, key, value: string) =
    let handler = self.getAttributeHandler(key)
    handler.addText(value)
    handler.verify()
  method verify*(self: ref XmlElementHandler)

trait XmlnsHandler:
  method createElement*(self: ref XmlnsHandler, name: string, proxy: TypedProxy): ref XmlElementHandler

trait XmlnsRegistry:
  method resolveXmlns*(self: ref XmlnsRegistry, name: string): ref XmlnsHandler
  method resolveProcessInstruction*(self: ref XmlnsRegistry, key, value: string) =
    raise newException(ValueError, "unsupported")

export XmlAttributeHandler, XmlElementHandler, XmlnsHandler, XmlnsRegistry

macro generateXmlElementHandler*(T: typed, xid: static string, verify: untyped) =
  let impl = T.resolveTypeDesc().getTypeImpl()
  impl.expectKind nnkObjectTy
  let list = impl[2]
  let self_id = ident "self"
  let key_id = ident "key"
  let case_stmt = nnkCaseStmt.newTree(key_id)
  for field in list:
    field.expectKind nnkIdentDefs
    let name = field[0]
    let namestr = name.strVal
    let of_body = newCall(
      ident "createAttributeHandler",
      newDotExpr(self_id, name)
    )
    case_stmt.add nnkOfBranch.newTree(
      newLit namestr,
      of_body
    )
  case_stmt.add nnkElse.newTree quote do:
    raise newException(ValueError, "unknown attribute: " & `key_id`)
  let getAttributeHandler_id = genSym(nskProc, "getAttributeHandler")
  let verify_id = genSym(nskProc, "verify")
  let impl_id = genSym(nskVar, "impl")
  result = quote do:
    registerTypeId(ref `T`, `xid`)
    proc `getAttributeHandler_id`(self: ref RootObj, `key_id`: string): ref XmlAttributeHandler =
      let `self_id` {.used.} = cast[ref `T`](self)
      `case_stmt`
    proc `verify_id`(self: ref RootObj) =
      let `self_id` {.used.} = cast[ref `T`](self)
      `verify`
    var `impl_id` = vtXmlElementHandler(getAttributeHandler: some `getAttributeHandler_id`, verify: `verify_id`)
    converter toXmlElementHandler(self: ref `T`): ref XmlElementHandler {.used.} =
      new result
      result.vtbl = addr `impl_id`
      result.raw = self