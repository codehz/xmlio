import parsexml, streams, options, tables, strscans, critbits

import traits, typeid, typed_proxy, debug

type XmlError* = object of ValueError
  filename: string
  line, column: int

type XmlContext = object
  case ischild: bool
  of false:
    parser: XmlParser
    handler: ref XmlnsRegistry
  of true:
    name: string
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
    attached, name: string
  of ak_xmlns:
    ns: string

proc parseAttributeName(name: string): AttributeName =
  var ns, attached, attrname: string
  if scanf(name, "xmlns:$+$.", ns):
    result = AttributeName(kind: ak_xmlns, ns: ns)
  elif ':' in name:
    raise newException(ValueError, "namespaced attribute is unsupported")
  elif scanf(name, "$+.$+$.", attached, attrname):
    result = AttributeName(kind: ak_normal, attached: attached, name: attrname)
  elif name == "xmlns":
    result = AttributeName(kind: ak_xmlns)
  else:
    result = AttributeName(kind: ak_normal, name: name)

proc currentElementName(self: var XmlContext): string =
  if self.ischild:
    self.name
  else:
    ""

proc parentElementName(self: var XmlContext): string =
  if self.ischild:
    self.parent[].currentElementName
  else:
    ""

proc rootContext(self: var XmlContext): ptr XmlContext =
  var cur = addr self
  if cur[].ischild:
    cur.root
  else:
    cur

proc newChildContext(parent: var XmlContext, name: string): XmlContext =
  result = XmlContext(
    ischild: true,
    name: name,
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

proc scanAttributes(
    ctx: var XmlContext,
    attach: ref XmlAttachedAttributeHandler = nil):
    seq[(string, string)] =
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
    of xmlAttribute:
      let atn = parseAttributeName parser.attrKey
      case atn.kind:
      of ak_normal:
        if atn.attached != "":
          decho "attached ", atn.attached, " but ", ctx.parentElementName
          if atn.attached == ctx.parentElementName:
            if attach != nil:
              attach.setAttribute(atn.name, parser.attrValue)
            else:
              raise newException(ValueError, "cannot use attach attribute here")
          else:
            raise newException(ValueError, "invalid attach target")
        else:
          result.add (atn.name, parser.attrValue)
      of ak_xmlns:
        assert ctx.ischild
        ctx.nsmap[atn.ns] = parser.attrValue
      parser.next()
    of xmlElementClose:
      return
    else:
      raise newException(ValueError, "invalid xml node: " & $parser.kind)

proc extract(ctx: var XmlContext, target: XmlChild)

proc processElementAttribute(
    ctx: var XmlContext,
    target: ref XmlAttributeHandler) =
  var root = ctx.rootContext
  template parser(): var XmlParser = root.parser
  template handler(): ref XmlnsRegistry = root.handler
  template unexpected() = raise newException(ValueError,
      "unexpected xml token: " & $parser.kind)
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
      let child = target.getChildProxy()
      ctx.extract(child)
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

proc processElement(
    ctx: var XmlContext,
    target: ref XmlElementHandler,
    origname: ElementName,
    attrs: sink seq[(string, string)] = @[]) =
  var attrset: CritBitTree[void]
  template acquireAttr(key: string) =
    if key in attrset:
      raise newException(ValueError, "duplicated attribute: " & key)
    attrset.incl key
  for (k, v) in attrs:
    acquireAttr k
    target.setAttributeString(k, v)
  var root = ctx.rootContext
  var whitecache = ""
  template parser(): var XmlParser = root.parser
  template handler(): ref XmlnsRegistry = root.handler
  template childrenMode() =
    let childrenattr = target.getChildrenAttribute()
    if childrenattr.isNone():
      raise newException(ValueError, "invalid children element")
    else:
      let attr = childrenattr.get()
      acquireAttr attr
      let childhandler = target.getAttributeHandler(attr)
      if whitecache != "":
        childhandler.addWhitespace whitecache
      ctx.processElementAttribute(childhandler)
      if parser.kind != xmlElementEnd: unexpected()
      return
  template unexpected() =
    raise newException(ValueError, "unexpected xml token: " & $parser.kind)
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
      let startname = parser.elementName & ""
      let elename = parseElementName(startname)
      if elename.attr.isNone(): childrenMode()
      let attrname = elename.attr.get()
      var child = ctx.newChildContext(attrname)
      if elename.name != origname.name:
        raise newException(ValueError, "invalid element attribute: element name mismatched")
      let attrs = child.scanAttributes()
      if attrs.len != 0:
        raise newException(ValueError, "invalid element attribute: custom attribute in attribute is not allowed")
      if elename.ns != "" and child.resolveNs(elename.ns) != ctx.resolveNs(origname.ns):
        raise newException(ValueError, "invalid element attribute: xmlns mismatched")
      acquireAttr attrname
      let attrhandler = target.getAttributeHandler(attrname)
      parser.next()
      child.processElementAttribute(attrhandler)
      if parser.kind != xmlElementEnd: unexpected()
      if parser.elementName != startname:
        raise newException(ValueError, "invalid element attribute: end tag not matched")
      parser.next()
    of xmlWhitespace:
      whitecache.add parser.charData
      parser.next()
    of xmlCharData, xmlSpecial, xmlEntity, xmlCData:
      childrenMode()
    else: unexpected()

proc extract(
    ctx: var XmlContext,
    target: XmlChild) =
  var root = ctx.rootContext
  template parser(): var XmlParser = root.parser
  template handler(): ref XmlnsRegistry = root.handler
  template unexpected() =
    raise newException(ValueError, "unexpected xml token: " & $parser.kind)
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
      let elename = parseElementName(parser.elementName)
      var child = ctx.newChildContext(elename.name)
      if elename.attr.isSome():
        raise newException(
          ValueError,
          "unexpected attribute style element: " & parser.elementName)
      let attrs = child.scanAttributes(target.attach)
      let ns = child.resolveNs(elename.ns)
      let element = ns.createElement(elename.name, target.proxy)
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
    template unexpected() =
      raise newException(ValueError, "unexpected xml token: " & $parser.kind)
    while true:
      dumpParser ctx.parser, "END"
      case parser.kind:
      of xmlEof: return
      of xmlComment, xmlWhitespace: discard
      else: unexpected()
  except CatchableError:
    decho getCurrentException().getStackTrace()
    let xmle = newException(
      XmlError,
      ctx.parser.errorMsg(getCurrentExceptionMsg()), getCurrentException())
    xmle.filename = ctx.parser.getFilename()
    xmle.line = ctx.parser.getLine()
    xmle.column = ctx.parser.getColumn()
    raise xmle

proc readXml*[T: ref](
  handler: ref XmlnsRegistry,
  input: Stream,
  filename: string,
  desc: typedesc[T]): T =
  ## read type T from xml
  var ctx: XmlContext
  ctx.parser.open(input, filename, {reportWhitespace, allowUnquotedAttribs,
      allowEmptyAttribs})
  ctx.handler = handler
  ctx.parser.next()
  ctx.extract(desc)

proc readXml*[T: ref](
  handler: ref XmlnsRegistry,
  input: string,
  desc: typedesc[T],
  filename: string = "<input>"): T =
  var streams = newStringStream input
  readXml[T](handler, streams, filename, desc)
