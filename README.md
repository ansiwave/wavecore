This is the server implementation of ANSIWAVE BBS, along with the client networking / database code so they can be tested together. To build an executable ready for running on a server, do:

```
nimble build -d:release
```

To set up your first board, you'll need to create the sysop key for it. Using the ansiwave terminal client, run `ansiwave --gen-login-key=~/.ansiwave/login-key.png` on your local machine (you do *not* need to do this on the server you're running wavecore). It will create the filename specified, and will also print out your public key.

On the server, you now should create a directory called `bbs`, and inside of it, a directory called `boards`. Finally, create a diretory named after your public key inside of that. For example, if your public key is `Q8BTY324cY7nl5kce6ctEfk8IRIrtsM8NfKL29B-3UE`, you could do:

```
mkdir -p ~/bbs/boards/Q8BTY324cY7nl5kce6ctEfk8IRIrtsM8NfKL29B-3UE
```

Now run the wavecore server in the same working directory as `bbs`. If it can't find the `bbs` directory, it will quit with an error. This directory will contain all the public files that must be served to users.

Never expose the wavecore server directly to external connections. Instead, put it behind a proxy server like nginx. Make your proxy server serve the `bbs` directory as static files, and additionally forward the `/ansiwave` endpoint to the wavecore server. For example, if you're using nginx, edit the config at `/etc/nginx/sites-enabled/default` and somewhere in the `server` block add:

```
server {
        ...

        location /ansiwave {
                proxy_pass  http://127.0.0.1:3000/ansiwave;
        }

        root /path/to/bbs;

        ...
}
```

Assuming nginx is serving on port 80, you should then be able to connect to it with the ansiwave terminal client like this:

```
ansiwave http://localhost:80/#board:Q8BTY324cY7nl5kce6ctEfk8IRIrtsM8NfKL29B-3UE
```

Replace `localhost` with your public IP or hostname to connect to it remotely.

Assuming your ansiwave terminal client is using the sysop key you generated (i.e., it is located at `~/.ansiwave/login-key.png`), you should see a `create banner` and `create new subboard` button. If these don't appear, the board in the URL you gave to ansiwave doesn't match your login key. Once you've made the subboards, other users can begin making posts there.
