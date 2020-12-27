import parsexml, streams, options, tables, strscans, critbits

import traits, typeid, typed_proxy

export registerTypeId

when defined(debug_parsexml):
  const decho = echo
  proc dumpParser(parser: var XmlParser, stage: string = "DUMP") =
    let kind = parser.kind
    var buffer = stage & " " & ($kind).substr(3)
    case kind:
    of xmlWhitespace: discard
    of xmlCharData, xmlComment, xmlCData, xmlSpecial:
      buffer = buffer & "=" & parser.charData
    of xmlElementStart, xmlElementEnd, xmlElementOpen:
      buffer = buffer & "=" & parser.elementName
    of xmlEntity:
      buffer = buffer & "=" & parser.entityName
    of xmlAttribute:
      buffer = buffer & "(" & parser.attrKey & "=" & parser.attrValue & ")"
    of xmlPI:
      buffer = buffer & "(" & parser.piName & "=" & parser.piRest & ")"
    of xmlError:
      buffer = buffer & "=" & parser.errorMsg
    else: discard
    echo buffer

else:
  template decho(all: varargs[untyped]) = discard
  template dumpParser(all: varargs[untyped]) = discard

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

proc scanAttributes(ctx: var XmlContext): seq[(string, string)] =
  var root = ctx.rootContext
  template parser(): var XmlParser = root.parser
  while true:
    case parser.kind:
    of xmlElementStart: return @[]
    of xmlElementOpen:
      parser.next()
      break
    of xmlWhitespace: parser.next()
    else: raise newException(ValueError, "invalid xml node: " & $parser.kind)
  while true:
    dumpParser parser, "SCAN"
    case parser.kind:
    of xmlWhitespace: parser.next()
    of xmlAttribute:
      let atn = parseAttributeName parser.attrKey
      case atn.kind:
      of ak_normal:
        result.add (atn.name, parser.attrValue)
      of ak_xmlns:
        assert ctx.ischild
        ctx.nsmap[atn.ns] = parser.attrValue
      parser.next()
    of xmlElementClose:
      return
    else:
      raise newException(ValueError, "invalid xml node: " & $parser.kind)

proc extract(ctx: var XmlContext, target: TypedProxy)

proc processElementAttribute(ctx: var XmlContext, target: ref XmlAttributeHandler) =
  var root = ctx.rootContext
  template parser(): var XmlParser = root.parser
  template handler(): ref XmlnsRegistry = root.handler
  template unexpected() = raise newException(ValueError, "unexpected xml token: " & $parser.kind)
  while true:
    dumpParser parser, "ATTR"
    let kind = parser.kind
    case kind:
    of xmlPI:
      handler.resolveProcessInstruction(parser.piName, parser.piRest)
      parser.next()
    of xmlElementEnd:
      target.verify()
      return
    of xmlElementStart, xmlElementOpen:
      let proxy = target.getChildProxy()
      ctx.extract(proxy)
    of xmlCharData, xmlCData:
      target.addText(parser.charData)
      parser.next()
    of xmlWhitespace:
      target.addWhitespace(parser.charData)
      parser.next()
    of xmlSpecial:
      target.addSpecial(parser.charData)
      parser.next()
    of xmlEntity:
      target.addEntity(parser.entityName)
      parser.next()
    else: unexpected()

proc processElement(ctx: var XmlContext, target: ref XmlElementHandler, origname: ElementName, attrs: sink seq[(string, string)] = @[]) =
  var attrset: CritBitTree[void]
  template acquireAttr(key: string) =
    if key in attrset:
      raise newException(ValueError, "duplicated attribute: " & key)
    attrset.incl key
  for (k, v) in attrs:
    acquireAttr k
    target.setAttributeString(k, v)
  var root = ctx.rootContext
  template parser(): var XmlParser = root.parser
  template handler(): ref XmlnsRegistry = root.handler
  template childrenMode() =
    acquireAttr "children"
    let childhandler = target.getAttributeHandler("children")
    ctx.processElementAttribute(childhandler)
    if parser.kind != xmlElementEnd: unexpected()
    return
  template unexpected() = raise newException(ValueError, "unexpected xml token: " & $parser.kind)
  while true:
    dumpParser parser, "ELEM"
    let kind = parser.kind
    case kind:
    of xmlPI:
      handler.resolveProcessInstruction(parser.piName, parser.piRest)
      parser.next()
    of xmlElementEnd:
      target.verify()
      return
    of xmlElementStart, xmlElementOpen:
      let startname = parser.elementName;
      let elename = parseElementName(startname)
      if elename.attr.isNone(): childrenMode()
      var child = ctx.newChildContext()
      if elename.name != origname.name:
        raise newException(ValueError, "invalid element attribute: element name mismatched")
      let attrs = child.scanAttributes()
      if attrs.len != 0:
        raise newException(ValueError, "invalid element attribute: custom attribute in attribute is not allowed")
      if elename.ns != "" and child.resolveNs(elename.ns) != ctx.resolveNs(origname.ns):
        raise newException(ValueError, "invalid element attribute: xmlns mismatched")
      let attrhandler = target.getAttributeHandler(elename.attr.get())
      parser.next()
      child.processElementAttribute(attrhandler)
      if parser.kind != xmlElementEnd: unexpected()
      if parser.elementName != startname:
        raise newException(ValueError, "invalid element attribute: end tag not matched")
      parser.next()
    of xmlCharData, xmlSpecial, xmlWhitespace, xmlEntity, xmlCData:
      childrenMode()
    else: unexpected()

proc extract(ctx: var XmlContext, target: TypedProxy) =
  var root = ctx.rootContext
  template parser(): var XmlParser = root.parser
  template handler(): ref XmlnsRegistry = root.handler
  template unexpected() = raise newException(ValueError, "unexpected xml token: " & $parser.kind)
  var processed = none string
  while true:
    dumpParser parser, "EXTR"
    let kind = parser.kind
    case kind:
    of xmlWhitespace: parser.next()
    of xmlPI:
      handler.resolveProcessInstruction(parser.piName, parser.piRest)
      parser.next()
    of xmlElementStart, xmlElementOpen:
      if processed.isSome(): unexpected()
      processed = some parser.elementName
      var child = ctx.newChildContext()
      let elename = parseElementName(parser.elementName)
      if elename.attr.isSome():
        raise newException(ValueError, "unexpected attribute style element: " & parser.elementName)
      let attrs = child.scanAttributes()
      let ns = child.resolveNs(elename.ns)
      let element = ns.createElement(elename.name, target)
      parser.next()
      child.processElement(element, elename, attrs)
    of xmlElementEnd:
      if processed.isNone(): unexpected()
      if processed.get() != parser.elementName: unexpected()
      parser.next()
      return
    of xmlEof:
      raise newException(ValueError, "unexpected EOF")
    else: unexpected()

proc extract[T: ref](ctx: var XmlContext, desc: typedesc[T]): T =
  let proxy = createProxy(result)
  try:
    ctx.extract(proxy)
    var root = ctx.rootContext
    template parser(): var XmlParser = root.parser
    template unexpected() = raise newException(ValueError, "unexpected xml token: " & $parser.kind)
    while true:
      dumpParser ctx.parser, "END"
      case parser.kind:
      of xmlEof: return
      of xmlComment, xmlWhitespace: discard
      else: unexpected()
  except CatchableError:
    decho getCurrentException().getStackTrace()
    let xmle = newException(XmlError, ctx.parser.errorMsg(getCurrentExceptionMsg()), getCurrentException())
    xmle.filename = ctx.parser.getFilename()
    xmle.line = ctx.parser.getLine()
    xmle.column = ctx.parser.getColumn()
    raise xmle

proc readXml*[T: ref](handler: ref XmlnsRegistry, input: Stream, filename: string, desc: typedesc[T]): T =
  var ctx: XmlContext
  ctx.parser.open(input, filename, {reportWhitespace, allowUnquotedAttribs, allowEmptyAttribs})
  ctx.handler = handler
  ctx.parser.next()
  ctx.extract(desc)