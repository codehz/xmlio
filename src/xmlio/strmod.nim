proc casemod*(str: string): string =
  for idx, ch in str:
    case ch:
    of 'A'..'Z':
      if idx != 0:
        result.add '-'
      result.add chr(ord(ch) - ord('A') + ord('a'))
    else:
      result.add ch