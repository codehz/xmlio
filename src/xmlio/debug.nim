when defined(debug_parsexml):
  import parsexml
  const decho* = echo
  proc dumpParser*(parser: var XmlParser, stage: string = "DUMP") =
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
  template decho*(all: varargs[untyped]) = discard
  template dumpParser*(all: varargs[untyped]) = discard