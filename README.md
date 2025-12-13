I simple docker for running interactive game servers. It provides an sshd w/ a nice bash environment for administration. It spawns the interactive app in a tmux server which is auto attached on ssh pty login. It has a crontab for updating a `*.duckdns.org` domain every 5mins, and sftp is enabled for uploading w/ filezilla. Everything, including the interactive app, is supervised by s6.

Example:
`docker run -d --name gamunner -e DUCKDNS_DOMAINS=<subdomain1,...> -e DUCKDNS_TOKEN=<token> -v /some/path2store/data:/data -p 2222:2222/tcp -p 25565:25565/tcp --restart=unless-stopped --stop-timeout=40 drew6017/gamerunner`

- port 2222: sshd
- port 25565: assumed game server port (user specified)

The user/interactive app should be `exec`-ed from `/data/start.sh` which is dropped on first start by the docker. Public key authentication is the only supported login so append your trusted admin pubkeys like `echo '<ssh-rsa AAAA... user_comment>' >> /data/ssh/authorized_keys`

- jre-21 is pre-installed (this was originally meant for minecraft servers)
- *optionally* change the UID/GID of the user running the game server w/ `-e APP_UID=<uid> -e APP_GID=<gid>`, otherwise they are both `1000`
- *optionally* specify `-e TZ='America/Chicago'` to change timezone information to e.g. `CST`
- *optionally* specify `--stop-timeout=40` to increase the allowed time for the game app to save it's data. You may combine this w/ e.g. `-e STOP_TIMEOUT=30` which is the number of seconds after being sent SIGTERM the game is sent SIGKILL. It is recommended `--stop-timeout` is always given 10s over `-e STOP_TIMEOUT`, but this shouldn't matter much.

Tunneling and forwarding are also enabled for sshd in-case your game has additional, questionably-secure, management ports.
