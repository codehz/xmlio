import hashes, strformat

type TypeId* = distinct array[16, byte]

proc `==`*(lhs, rhs: TypeId): bool =
  for idx in 0..<16:
    if ((array[16, byte])(lhs))[idx] != ((array[16, byte])(rhs))[idx]:
      return false
  return true

proc hash*(id: TypeId): Hash =
  for i in array[16, byte](id):
    result = result !& hash(i)
  result = !$ result

converter valid*(id: TypeId): bool =
  for i in array[16, byte](id):
    if i != 0:
      return true
  return false

proc `$`*(id: TypeId): string =
  for idx, i in array[16, byte](id):
    case idx:
    of 4, 6, 8, 10:
      result = result & "-"
    else:
      discard
    formatValue(result, i, "02x")

proc typeIdStorage[T](): var TypeId =
  var storage {.global.}: TypeId
  return storage

proc typeid*(T: typedesc): TypeId =
  result = typeIdStorage[T]()
  assert result.valid, $T & " is not registered"

proc parseTypeId(str: string): TypeId {.compileTime.} =
  assert str.len == 36
  assert str[8] == '-'
  assert str[13] == '-'
  assert str[18] == '-'
  assert str[23] == '-'
  var even = false
  var tmp: byte
  var count = 0
  var ret: array[16, byte]
  for ch in str:
    let imm = case ch:
    of '-': continue
    of '0'..'9': byte(ord(ch) - ord('0'))
    of 'a'..'f': byte(ord(ch) - ord('a') + 10)
    of 'A'..'F': byte(ord(ch) - ord('A') + 10)
    else: raise newException(ValueError, "invalid character " & $ch)
    if even:
      ret[count] = (tmp shl 4) + imm
      count += 1
      tmp = 0
      even = false
    else:
      tmp = imm
      even = true
  return TypeId(ret)

proc registerTypeId*(T: typedesc, id: static string) =
  const xid = parseTypeId(id)
  static:
    doAssert xid.valid
  assert (not typeIdStorage[T]().valid) or (typeIdStorage[T]() == xid), $T & " registered"
  typeIdStorage[T]() = xid
  assert typeIdStorage[T]().valid
