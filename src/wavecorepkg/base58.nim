# https://git.sr.ht/~ehmry/nim_base58

import std/strutils

include ./base58/alphabet

proc encode*[T: char|int8|uint8](bin: openArray[T]): string {.noSideEffect.} =
  ## Encode a string to a Bitcoin base58 encoded string.
  if bin.len == 0: return ""
  var zeroes, length: int
  for c in bin:
    if c == 0: inc zeroes
    else: break
  # Skip & count leading zeroes.

  let size = bin.len * 138 div 100 + 1 # log(256) / log(58), rounded up.
  var b58 = newString(size)
  # Allocate enough space in big-endian base58 representation.

  for k in zeroes..<bin.len:
    var
      carry = bin[k].int
      i: int
    for j in countdown(b58.high, 0):
      if (carry == 0) and (i >= length): break
      carry = carry + 256 * b58[j].int
      b58[j] = (char)carry mod 58
      carry = carry div 58
      inc i
    # Apply "b58 = b58 * 256 + ch".
    doAssert(carry == 0)
    length = i
  # Process the bytes.

  var start: int
  while b58[start] == 0.char:
    inc start
  # Skip leading zeroes in base58 result.
  result = newStringOfCap(zeroes + (b58.len - start))
  for i in 1..zeroes:
    result.add '1'
  for i in start..<b58.len:
    result.add Alphabet[b58[i].int]
  # Translate the result into a string.

proc d(b58: string): string =
  ## Decode a string in Bitcoin base58 to a string.
  var zeroes, length: int
  for c in b58:
    if c == '1': inc zeroes
    else: break

  let size = b58.len * 733 div 1000 + 1 # log(58) / log(256), rounded up.
  var b256 = newString(size)
  # Allocate enough space in big-endian base256 representation.

  for i in zeroes..b58.high:
    let c = b58[i]
    if c notin Whitespace:
      var
        carry = (int)reverse c
        i: int
      for j in countdown(b256.high, 0):
        if (carry == 0) and (i >= length): break
        carry = carry + 58 * b256[j].int
        b256[j] = (carry mod 256).char
        carry = carry div 256
        inc i
      doAssert(carry == 0)
      length = i
      # Decode base58 character
  # Process the characters

  var i = size - length
  while i < b256.len and b256[i] == 0.char:
    inc i
  # Skip leading zeroes in b256.

  result = newString(b256.len - i)
  for j in 0..<result.len:
    result[j] = b256[i]
    inc i

proc decode*(b58: string): string {.noSideEffect.} =
  ## Decode a string in Bitcoin base58 to a string.
  try: result = d b58
  except:
    raise newException(ValueError, "invalid Bitcoin base58 encoding")
