const
  Alphabet* = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    ## Standard Base58 alphabet.
  AlphabetSize = Alphabet.len
  ReverseAlphabetSize = Alphabet[Alphabet.high].int - Alphabet[Alphabet.low].int + 1

proc reverseAlphabet(): array[ReverseAlphabetSize, char] =
  for i in 0..<result.len:
    result[i] = 0xff.char
  for i in 0..<AlphabetSize:
    let j = Alphabet[i].int - Alphabet[0].int
    result[j] = i.char

const ReverseAlphabet = reverseAlphabet()

proc reverse(c: char): char =
  let i = c.int - Alphabet[0].int
  if i >= ReverseAlphabet.low and i <= ReverseAlphabet.high:
    result = ReverseAlphabet[i]
    if result != 0xff.char:
      return
  raise newException(ValueError, "invalid base58 character")
