proc emscripten_worker_respond(data: cstring, size: cint) {.importc.}

proc recvAction(data: pointer, size: cint) {.exportc.} =
  var input = newString(size)
  copyMem(input[0].addr, data, size)
  echo "Input: ", input
  let data = "BYE"
  emscripten_worker_respond(data, data.len.cint)
