import unicode

const
  codeTerminators* = {'c', 'f', 'h', 'l', 'm', 's', 't', 'u',
                      'A', 'B', 'C', 'D', 'E', 'F', 'G',
                      'H', 'J', 'K', 'N', 'O', 'P', 'S',
                      'T', 'X', '\\', ']', '^', '_'}

proc parseCode*(codes: var seq[string], ch: Rune): bool =
  proc terminated(s: string): bool =
    if s.len > 0:
      let lastChar = s[s.len - 1]
      return codeTerminators.contains(lastChar)
    else:
      return false
  let s = $ch
  if s == "\e":
    codes.add(s)
    return true
  elif codes.len > 0 and not codes[codes.len - 1].terminated:
    codes[codes.len - 1] &= s
    return true
  return false

proc stripCodes*(line: seq[Rune]): seq[Rune] =
  var codes: seq[string]
  for ch in line:
    if parseCode(codes, ch):
      continue
    result.add(ch)

proc stripCodes*(line: string): string =
  $stripCodes(line.toRunes)

proc stripCodesIfCommand*(line: string): string =
  var
    codes: seq[string]
    foundFirstValidChar = false
  for ch in runes(line):
    if ansi.parseCode(codes, ch):
      continue
    if not foundFirstValidChar and ch.toUTF8[0] != '/':
      return ""
    else:
      foundFirstValidChar = true
      result &= $ch

proc stripCodesIfCommand*(line: ref string): string =
  stripCodesIfCommand(line[])
