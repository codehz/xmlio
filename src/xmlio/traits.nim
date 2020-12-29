import macros, options, sugar

import vtable
import vtable/utils

import typed_proxy, strmod

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
  method getChildrenAttribute*(self: ref XmlElementHandler):
    Option[string] = none string
  method getAttributeHandler*(
    self: ref XmlElementHandler, key: string
  ): ref XmlAttributeHandler =
    raise newException(ValueError, "unsupported")
  method setAttributeString*(self: ref XmlElementHandler, key, value: string) =
    let handler = self.getAttributeHandler(key)
    handler.addText(value)
    handler.verify()
  method verify*(self: ref XmlElementHandler)

trait XmlnsHandler:
  method createElement*(
    self: ref XmlnsHandler, name: string, proxy: TypedProxy
  ): ref XmlElementHandler

trait XmlnsRegistry:
  method resolveXmlns*(self: ref XmlnsRegistry, name: string): ref XmlnsHandler
  method resolveProcessInstruction*(
    self: ref XmlnsRegistry, key, value: string
  ) = raise newException(ValueError, "unsupported")

export XmlAttributeHandler, XmlElementHandler, XmlnsHandler, XmlnsRegistry

type TypeIdent = tuple[tid, name, children: NimNode, exported: bool]

proc parseTypeIdent(def: NimNode): TypeIdent =
  def.expectKind nnkPragmaExpr
  case def[0].kind:
  of nnkPostfix:
    def[0][0].expectIdent "*"
    result.name = def[0][1]
    result.name.expectKind nnkIdent
    result.exported = true
  of nnkIdent:
    result.name = def[0]
    result.exported = false
  else:
    error "invalid ident"
  def[1].expectKind nnkPragma
  result.tid = newEmptyNode()
  result.children = newEmptyNode()
  for pg in def[1]:
    pg.expectKind {nnkCall,nnkExprColonExpr}
    case pg[0].strVal:
    of "id":
      pg.expectLen 2
      result.tid = pg[1]
    of "children":
      pg.expectLen 2
      result.children = pg[1]
    else:
      error("invalid pragma: " & pg[0].strVal)
  if result.tid.kind != nnkStrLit:
    error("no typeid or invalid typeid")

proc parseFieldIdent(def: NimNode):
  tuple[name, nameid, of_stmt: NimNode, check: Option[NimNode -> NimNode]] =
  case def.kind:
  of nnkPragmaExpr:
    result = parseFieldIdent(def[0])
    let name = result.name
    def[1].expectKind nnkPragma
    for pg in def[1]:
      pg.expectKind {nnkCall,nnkExprColonExpr}
      pg[0].expectKind nnkIdent
      case pg[0].strVal:
      of "check":
        pg.expectLen 3
        let checkbody = pg[1].copy()
        let checkmsg = pg[2].copy()
        result.check = some proc (id: NimNode): NimNode = quote do:
          block:
            template value(): untyped = `id`.`name`
            if `checkbody`: raise newException(ValueError, `checkmsg`)
      of "visitor":
        pg.expectLen 2
        result.of_stmt[1][0] = pg[1].copy()
      else:
        error("invalid pragma")
  of nnkPostfix:
    result = parseFieldIdent(def[1])
    def[0].expectIdent "*"
    result.nameid = def
  of nnkIdent:
    result.name = def
    result.nameid = def
    let of_body = newCall(
      ident "createAttributeHandler",
      newDotExpr(ident "self", def)
    )
    result.of_stmt = nnkOfBranch.newTree(
      newLit casemod def.strVal,
      of_body
    )
  else:
    error "invalid type"

proc processTypeDef(def: NimNode):
  tuple[
    typesec: NimNode,
    children: NimNode,
    case_stmt: NimNode,
    idinfo: TypeIdent,
    checks: seq[NimNode -> NimNode]] =
  result.typesec = def.copy()
  result.case_stmt = nnkCaseStmt.newTree(ident "key")
  result.checks = newSeq[NimNode -> NimNode]()
  result.idinfo = parseTypeIdent(def[0])
  result.typesec[0] = def[0][0]
  let children_id = if result.idinfo.children.kind == nnkEmpty:
    newLit "children"
  else:
    newLit result.idinfo.children.strVal
  def[1].expectKind nnkEmpty
  def[2].expectKind nnkObjectTy
  let objt = def[2]
  objt[0].expectKind nnkEmpty
  objt[1].expectKind nnkOfInherit
  let objl = objt[2]
  objl.expectKind nnkRecList
  result.children = quote do:
    none string
  for idx, item in objl:
    item.expectKind nnkIdentDefs
    let field = parseFieldIdent(item[0])
    result.typesec[2][2][idx][0] = field.nameid
    result.case_stmt.add field.of_stmt
    if field.check.isSome():
      result.checks.add field.check.get()
    if field.name.strVal == children_id.strVal:
      result.children = quote do:
        some `children_id`
  result.case_stmt.add nnkElse.newTree quote do:
    raise newException(ValueError, "unknown attribute: " & key)
  return

macro declareXmlElement*(blocks: varargs[untyped]) =
  if not(blocks.len in 1..2):
    error "only accept 1..2 block"
  for blk in blocks:
    blk.expectKind nnkStmtList
  blocks[0][0].expectKind nnkTypeSection
  blocks[0][0].expectLen 1
  blocks[0][0][0].expectKind nnkTypeDef
  result = newStmtList()
  let tmp = processTypeDef(blocks[0][0][0])
  result.add nnkTypeSection.newTree tmp.typesec
  let T = tmp.idinfo.name
  let tid = tmp.idinfo.tid
  result.add quote do:
    registerTypeId(ref `T`, `tid`)
  let case_stmt = tmp.case_stmt
  let getChildrenAttribute_id = genSym(nskProc, "getChildrenAttribute")
  let getAttributeHandler_id = genSym(nskProc, "getAttributeHandler")
  let verify_id = genSym(nskProc, "verify")
  let impl_id = genSym(nskVar, "impl")
  let self_id = ident "self"
  let key_id = ident "key"
  let children_stmt = tmp.children
  let verify = newStmtList()
  for check in tmp.checks:
    verify.add check(ident "self")
  if blocks.len == 2:
    verify.add blocks[1]
  result.add quote do:
    proc `getChildrenAttribute_id`(self: ref RootObj):
      Option[string] = `children_stmt`
    proc `getAttributeHandler_id`(
      self: ref RootObj, `key_id`: string
    ): ref XmlAttributeHandler =
      let `self_id` {.used.} = cast[ref `T`](self)
      `case_stmt`
    proc `verify_id`(self: ref RootObj) =
      let `self_id` {.used.} = cast[ref `T`](self)
      `verify`
    var `impl_id` = vtXmlElementHandler(
      getChildrenAttribute: some `getChildrenAttribute_id`,
      getAttributeHandler: some `getAttributeHandler_id`,
      verify: `verify_id`)
    converter toXmlElementHandler(self: ref `T`): ref XmlElementHandler {.used.} =
      new result
      result.vtbl = addr `impl_id`
      result.raw = self

macro generateXmlElementHandler*(
  T: typed, xid: static string, verify: untyped
) =
  let impl = T.resolveTypeDesc().getTypeImpl()
  impl.expectKind nnkObjectTy
  let list = impl[2]
  let self_id = ident "self"
  let key_id = ident "key"
  let case_stmt = nnkCaseStmt.newTree(key_id)
  var children_stmt = quote do: none string
  for field in list:
    field.expectKind nnkIdentDefs
    let name = field[0]
    let namestr = name.strVal
    if namestr == "children":
      children_stmt = quote do: some "children"
    let of_body = newCall(
      ident "createAttributeHandler",
      newDotExpr(self_id, name)
    )
    case_stmt.add nnkOfBranch.newTree(
      newLit casemod namestr,
      of_body
    )
  case_stmt.add nnkElse.newTree quote do:
    raise newException(ValueError, "unknown attribute: " & `key_id`)
  let getChildrenAttribute_id = genSym(nskProc, "getChildrenAttribute")
  let getAttributeHandler_id = genSym(nskProc, "getAttributeHandler")
  let verify_id = genSym(nskProc, "verify")
  let impl_id = genSym(nskVar, "impl")
  result = quote do:
    registerTypeId(ref `T`, `xid`)
    proc `getChildrenAttribute_id`(self: ref RootObj):
      Option[string] = `children_stmt`
    proc `getAttributeHandler_id`(
      self: ref RootObj, `key_id`: string
    ): ref XmlAttributeHandler =
      let `self_id` {.used.} = cast[ref `T`](self)
      `case_stmt`
    proc `verify_id`(self: ref RootObj) =
      let `self_id` {.used.} = cast[ref `T`](self)
      `verify`
    var `impl_id` = vtXmlElementHandler(
      getChildrenAttribute: some `getChildrenAttribute_id`,
      getAttributeHandler: some `getAttributeHandler_id`,
      verify: `verify_id`)
    converter toXmlElementHandler(self: ref `T`): ref XmlElementHandler {.used.} =
      new result
      result.vtbl = addr `impl_id`
      result.raw = self
