from strutils import format
from ./db/entities import nil
from urlly import nil
from paths import nil

when defined(emscripten):
  import client/emscripten
else:
  import client/native

type
  ClientException* = object of CatchableError

export fetch, start, stop, get, Client, ChannelValue, Result, Request, Response, Header

const
  Valid* = ResultKind.Valid
  Error* = ResultKind.Error

proc initClient*(address: string, postAddress: string = address): Client =
  Client(address: address, postAddress: postAddress)

proc initUrl(address: string; endpoint: string): string =
  if strutils.endsWith(address, "/"):
    "$1$2".format(address, endpoint)
  else:
    "$1/$2".format(address, endpoint)

proc setReadUrl*(client: Client, readUrl: string) =
  when defined(emscripten):
    emscripten.sendSetReadUrl(client, readUrl)
  else:
    paths.readUrl = readUrl

proc request*(url: string, data: string, verb: string): string =
  let response: Response = fetch(Request(url: urlly.parseUrl(url), verb: verb, body: data))
  if response.code != 200:
    raise newException(ClientException, "Error code " & $response.code & ": " & response.body)
  return response.body

proc post*(client: Client, endpoint: string, data: string): string =
  let url = initUrl(client.postAddress, endpoint)
  request(url, data, "post")

proc get*(client: Client, endpoint: string, range: (int, int) = (0, 0)): string =
  let url = initUrl(client.address, endpoint)
  var headers: seq[Header] = @[]
  if range != (0, 0):
    headers.add(Header(key: "Range", value: "range=$1-$2".format(range[0], range[1])))
  let response: Response = fetch(Request(url: urlly.parseUrl(url), headers: headers, verb: "get", body: ""))
  if not response.code in {200, 206}:
    raise newException(ClientException, "Error code " & $response.code & ": " & response.body)
  return response.body

proc query*(client: Client, endpoint: string, range: (int, int) = (0, 0)): ChannelValue[Response] =
  let url = initUrl(client.address, endpoint)
  var headers: seq[Header] = @[]
  if range != (0, 0):
    headers.add(Header(key: "Range", value: "range=$1-$2".format(range[0], range[1])))
  let request = Request(url: urlly.parseUrl(url), headers: headers, verb: "get", body: "")
  result = initChannelValue[Response]()
  sendFetch(client, request, result.chan)

proc submit*(client: Client, endpoint: string, body: string): ChannelValue[Response] =
  let url = initUrl(client.postAddress, endpoint)
  let request = Request(url: urlly.parseUrl(url), verb: "post", body: body)
  result = initChannelValue[Response]()
  sendFetch(client, request, result.chan)

proc queryUser*(client: Client, filename: string, publicKey: string): ChannelValue[entities.User] =
  result = initChannelValue[entities.User]()
  sendUserQuery(client, filename, publicKey, result.chan)

proc queryPost*(client: Client, filename: string, sig: string, getContent: bool = true): ChannelValue[entities.Post] =
  result = initChannelValue[entities.Post]()
  sendPostQuery(client, filename, sig, getContent, result.chan)

proc queryPostChildren*(client: Client, filename: string, sig: string, sortByTs: bool = false, offset: int = 0): ChannelValue[seq[entities.Post]] =
  result = initChannelValue[seq[entities.Post]]()
  sendPostChildrenQuery(client, filename, sig, sortByTs, offset, result.chan)

proc queryUserPosts*(client: Client, filename: string, publicKey: string, offset: int = 0): ChannelValue[seq[entities.Post]] =
  result = initChannelValue[seq[entities.Post]]()
  sendUserPostsQuery(client, filename, publicKey, offset, result.chan)

proc queryUserReplies*(client: Client, filename: string, publicKey: string, offset: int = 0): ChannelValue[seq[entities.Post]] =
  result = initChannelValue[seq[entities.Post]]()
  sendUserRepliesQuery(client, filename, publicKey, offset, result.chan)

proc search*(client: Client, filename: string, kind: entities.SearchKind, term: string, offset: int = 0): ChannelValue[seq[entities.Post]] =
  result = initChannelValue[seq[entities.Post]]()
  sendSearchQuery(client, filename, kind, term, offset, result.chan)

