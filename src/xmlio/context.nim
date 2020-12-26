import parsexml, streams, options, tables, strscans

import traits, typeid, typed_proxy

export registerTypeId

when defined(debug_parsexml):
  const decho = echo
else:
  template decho(all: varargs[untyped]) = discard

type XmlError* = object of ValueError
  filename: string
  line, column: int
type XmlContext* = object
  case ischild: bool
  of false:
    parser: XmlParser
    handler: ref XmlnsRegistry
  of true:
    root, parent: ptr XmlContext
    defaultns: ref XmlnsHandler
    nsmap: Table[string, string]

type ElementName = object
  ns: string
  name: string
  attr: Option[string]

proc verifyName(name: string) =
  if name.len == 0:
    raise newException(ValueError, "Invalid null name")
  elif ':' in name or '.' in name:
    raise newException(ValueError, "Invalid character appear in name")

proc parseElementName(name: string): ElementName =
  var attr: string
  if scanf(name, "$+:$+.$+$.", result.ns, result.name, attr):
    result.attr = some attr
  elif scanf(name, "$+.$+$.", result.name, attr):
    result.ns = ""
    result.attr = some attr
  elif scanf(name, "$+:$+$.", result.ns, result.name):
    discard
  else:
    result.ns = ""
    result.name = name
  verifyName(result.name)

type AttributeKind = enum
  ak_normal,
  ak_xmlns

type AttributeName = object
  case kind: AttributeKind
  of ak_normal:
    name: string
  of ak_xmlns:
    ns: string

proc parseAttributeName(name: string): AttributeName =
  var ns: string
  if scanf(name, "xmlns:$+$.", ns):
    result = AttributeName(kind: ak_xmlns, ns: ns)
  elif ':' in name:
    raise newException(ValueError, "namespaced attribute is unsupported")
  elif name == "xmlns":
    result = AttributeName(kind: ak_xmlns)
  else:
    result = AttributeName(kind: ak_normal, name: name)

proc rootContext(self: var XmlContext): ptr XmlContext =
  var cur = addr self
  if cur[].ischild:
    cur.root
  else:
    cur

proc newChildContext(parent: var XmlContext): XmlContext =
  result = XmlContext(
    ischild: true,
    root: parent.rootContext,
    parent: addr parent,
    nsmap: initTable[string, string]()
  )

proc resolveNs(ctx: var XmlContext, name: string): ref XmlnsHandler =
  if not ctx.ischild:
    raise newException(ValueError, "invalid xmlns: " & name)
  if name.len == 0 and ctx.defaultns != nil:
    ctx.defaultns
  elif name in ctx.nsmap:
    ctx.rootContext.handler.resolveXmlns(ctx.nsmap[name])
  else:
    ctx.parent[].resolveNs(name)

proc process(ctx: var XmlContext, name: string, target: ref XmlElementHandler)

proc scanAttributes(ctx: var XmlContext, attrs: var Table[string, string]) =
  var root = ctx.rootContext
  template parser(): var XmlParser = root.parser
  while true:
    decho "SCAN ", parser.kind
    case parser.kind:
    of xmlAttribute:
      let atn = parseAttributeName parser.attrKey
      case atn.kind:
      of ak_normal:
        attrs[atn.name] = parser.attrValue
      of ak_xmlns:
        assert ctx.ischild
        ctx.nsmap[atn.ns] = parser.attrValue
      parser.next()
    of xmlElementClose:
      parser.next()
      return
    else:
      raise newException(ValueError, "invalid xml node: " & $parser.kind)

proc extract(ctx: var XmlContext, proxy: TypedProxy) =
  var root = ctx.rootContext
  template parser(): var XmlParser = root.parser
  template handler(): ref XmlnsRegistry = root.handler
  var processed = false
  var textmode = false
  while true:
    decho "EXTR ", parser.kind, "::", cast[ByteAddress](proxy.rawptr)
    case parser.kind:
    of xmlPI:
      handler.resolveProcessInstruction(parser.piName, parser.piRest)
      parser.next()
    of xmlElementStart:
      if processed or textmode:
        raise newException(ValueError, "Invalid xml")
      let ele = parseElementName parser.elementName
      if ele.attr.isSome():
        raise newException(ValueError, "Invalid element: " & parser.elementName)
      let nshandler = ctx.resolveNs ele.ns
      let elehandler = nshandler.createElement(ele.name, proxy)
      var childctx = ctx.newChildContext()
      parser.next()
      childctx.process(ele.name, elehandler)
      if parser.kind != xmlElementEnd:
        raise newException(ValueError, "invalid xml")
      parser.next()
      processed = true
    of xmlElementOpen:
      if processed or textmode:
        raise newException(ValueError, "Invalid xml")
      let ele = parseElementName parser.elementName
      if ele.attr.isSome():
        raise newException(ValueError, "Invalid element: " & parser.elementName)
      var childctx = ctx.newChildContext()
      var attrcache = initTable[string, string]()
      parser.next()
      childctx.scanAttributes(attrcache)
      decho "FIXX ", parser.kind
      let nshandler = childctx.resolveNs ele.ns
      let elehandler = nshandler.createElement(ele.name, proxy)
      for k, v in attrcache:
        elehandler.setAttributeString(k, v)
      if parser.kind == xmlElementEnd:
        processed = true
        return
      childctx.process(ele.name, elehandler)
      if parser.kind != xmlElementEnd:
        raise newException(ValueError, "invalid xml")
      parser.next()
      processed = true
    of xmlElementEnd:
      if not processed:
        raise newException(ValueError, "Invalid xml")
      return
    of xmlEof:
      if not processed:
        raise newException(ValueError, "Unexpected eof")
      return
    else:
      raise newException(ValueError, "invalid xml node: " & $parser.kind)
    discard

proc process(ctx: var XmlContext, target: ref XmlAttributeHandler) =
  var root = ctx.rootContext
  template parser(): var XmlParser = root.parser
  template handler(): ref XmlnsRegistry = root.handler
  while true:
    decho "ATTR ", parser.kind
    case parser.kind:
    of xmlPI:
      handler.resolveProcessInstruction(parser.piName, parser.piRest)
      parser.next()
    of xmlElementEnd:
      target.verify()
      return
    of xmlElementStart, xmlElementOpen:
      let eln = parseElementName parser.elementName
      if eln.attr.isSome():
        raise newException(ValueError, "invalid attribute " & parser.elementName)
      else:
        let proxy = target.getChildProxy()
        ctx.extract proxy
        if parser.kind != xmlElementEnd:
          raise newException(ValueError, "invalid xml")
        parser.next()
    of xmlCharData, xmlCData:
      target.addText parser.charData
      parser.next()
    of xmlEntity:
      target.addEntity parser.charData
      parser.next()
    of xmlSpecial:
      target.addSpecial parser.charData
      parser.next()
    else:
      raise newException(ValueError, "invalid xml node when process attribute: " & $parser.kind)

proc process(ctx: var XmlContext, name: string, target: ref XmlElementHandler) =
  var root = ctx.rootContext
  var rawchildhandler: ref XmlAttributeHandler
  template parser(): var XmlParser = root.parser
  template handler(): ref XmlnsRegistry = root.handler
  template childhandler(): ref XmlAttributeHandler =
    if rawchildhandler == nil:
      rawchildhandler = target.getAttributeHandler("children")
    rawchildhandler
  while true:
    decho "ELEM ", parser.kind
    case parser.kind:
    of xmlPI:
      handler.resolveProcessInstruction(parser.piName, parser.piRest)
      parser.next()
    of xmlElementEnd:
      if rawchildhandler != nil:
        rawchildhandler.verify()
      target.verify()
      return
    of xmlElementStart:
      let eln = parseElementName parser.elementName
      if eln.attr.isSome():
        let attr = eln.attr.get()
        if eln.name != name or eln.ns != "":
          raise newException(ValueError, "invalid attribute " & parser.elementName)
        parser.next()
        ctx.process(target.getAttributeHandler(attr))
      else:
        let proxy = childhandler.getChildProxy()
        ctx.extract proxy
        if parser.kind != xmlElementEnd:
          raise newException(ValueError, "invalid xml")
        parser.next()
    of xmlElementOpen:
      let eln = parseElementName parser.elementName
      if eln.attr.isSome():
        raise newException(ValueError, "invalid attribute " & parser.elementName)
      else:
        let proxy = childhandler.getChildProxy()
        ctx.extract proxy
        if parser.kind != xmlElementEnd:
          raise newException(ValueError, "invalid xml")
        parser.next()
    of xmlCharData, xmlCData:
      childhandler.addText parser.charData
      parser.next()
    of xmlEntity:
      childhandler.addEntity parser.charData
      parser.next()
    of xmlSpecial:
      childhandler.addSpecial parser.charData
      parser.next()
    else:
      raise newException(ValueError, "invalid xml node when process element: " & $parser.kind)

proc extract*[T](ctx: var XmlContext, target: var T) =
  let proxy = createProxy(target)
  try:
    ctx.extract(proxy)
  except CatchableError:
    decho getCurrentException().getStackTrace()
    let xmle = newException(XmlError, ctx.parser.errorMsg(getCurrentExceptionMsg()), getCurrentException())
    xmle.filename = ctx.parser.getFilename()
    xmle.line = ctx.parser.getLine()
    xmle.column = ctx.parser.getColumn()
    raise xmle

proc newXmlContext*(handler: ref XmlnsRegistry, input: Stream, filename: string): XmlContext =
  result.parser.open(input, filename)
  result.handler = handler
  result.parser.next()