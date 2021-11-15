from base64 import nil
from strutils import nil

proc encode*[T](data: T): string =
  result = base64.encode(data, safe = true)
  var i = result.len - 1
  while i >= 0 and result[i] == '=':
    strutils.delete(result, i..i)
    i -= 1

export base64.decode
