{.compile: "ed25519/add_scalar.c".}
{.compile: "ed25519/fe.c".}
{.compile: "ed25519/keypair.c".}
{.compile: "ed25519/sc.c".}
{.compile: "ed25519/seed.c".}
{.compile: "ed25519/verify.c".}
{.compile: "ed25519/ge.c".}
{.compile: "ed25519/key_exchange.c".}
{.compile: "ed25519/sha512.c".}
{.compile: "ed25519/sign.c".}

type
  Seed* = array[32, uint8]
  PublicKey* = array[32, uint8]
  PrivateKey* = array[64, uint8]
  Signature* = array[64, uint8]

proc ed25519_create_seed*(seed: ptr Seed): cint {.importc.}
proc ed25519_create_keypair*(public_key: ptr PublicKey; private_key: ptr PrivateKey;
                             seed: ptr Seed) {.importc.}
proc ed25519_sign*(signature: ptr Signature; message: cstring; message_len: csize_t;
                   public_key: ptr PublicKey; private_key: ptr PrivateKey) {.importc.}
proc ed25519_verify*(signature: ptr Signature; message: cstring; message_len: csize_t;
                     public_key: ptr PublicKey): cint {.importc.}
proc ed25519_add_scalar*(public_key: ptr PublicKey; private_key: ptr PrivateKey;
                         scalar: pointer) {.importc.}
proc ed25519_key_exchange*(shared_secret: pointer; public_key: ptr PublicKey;
                           private_key: ptr PrivateKey) {.importc.}

