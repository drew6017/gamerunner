# https://hub.docker.com/repository/docker/drew6017/gamerunner/general
FROM alpine:edge

SHELL ["sh", "-exc"]
RUN apk add --no-cache \
    tmux \
	openssh \
	nano \
	nano-syntax \
	htop \
	curl \
	ca-certificates \
	openjdk21-jre-headless \
	bash \
	bash-completion \
	util-linux-misc \
	s6

RUN <<EOC
# make shell pretty
cat <<EOF > /root/.bashrc
# if not running interactively, don't evaluate
[[ "\$-" != *i* ]] && return

PS1='\[\e[0m\e[1;31m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w \[\e[0;33m\]\$\[\e[0m\] '
alias ls='ls -F --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# if ssh+interactive+not_tmux try auto-attaching to tmux app
if [[ ( -n "\$SSH_CLIENT" || -n "\$SSH_CONNECTION" || -n "\$SSH_TTY" ) && ! -n "\$TMUX" ]]; then
  tmux attach -t app
fi
EOF
cat <<EOF > /root/.bash_profile
if [ -f "\${HOME}/.bashrc" ]; then
  source "\${HOME}/.bashrc"
fi
EOF

# make nano pretty
cat <<EOF >> /etc/nanorc
include /usr/share/nano/*.nanorc
set tabsize 2
set tabstospaces
set autoindent
set stateflags
set colonparsing
EOF

cat <<EOF > /entry.sh
#!/bin/sh
addgroup -Sg \${APP_GID:-1000} app
adduser -SDH -s /sbin/nologin -h /dev/null -u \${APP_UID:-1000} -G app app

exec s6-svscan /etc/s6
EOF

cat <<EOF > /health.sh
#!/bin/sh
EOF

mkdir -p /etc/s6
cd /etc/s6
mkdir crond sshd app

# CROND --------- BEGIN ---------
rm -r /etc/periodic /etc/crontabs/*
echo "*/5 * * * * /duckdns_update.sh" > /etc/crontabs/cron
cat <<EOF > crond/run
#!/bin/sh
exec crond -f
EOF

cat <<EOF > /duckdns_update.sh
#!/bin/sh
if [[ ! -z "\$DUCKDNS_DOMAINS" && ! -z "\$DUCKDNS_TOKEN" ]]; then
  echo "duckdns -> \$(curl -sSf "https://www.duckdns.org/update?domains=\${DUCKDNS_DOMAINS}&token=\${DUCKDNS_TOKEN}&ip="; echo -n "(\$?)")"
fi
EOF
# CROND ---------  END  ---------

# SSHD --------- BEGIN ---------
cat <<EOF > sshd/run
#!/bin/sh
mkdir -p /data/ssh

#[ -f /data/ssh/ssh_host_ecdsa_key ] ||   ssh-keygen -t ecdsa -b 256 -N '' -f /data/ssh/ssh_host_ecdsa_key
[ -f /data/ssh/ssh_host_ed25519_key ] || ssh-keygen -t ed25519 -N '' -f /data/ssh/ssh_host_ed25519_key
[ -f /data/ssh/ssh_host_rsa_key ] ||     ssh-keygen -t rsa -b 4096 -N '' -f /data/ssh/ssh_host_rsa_key

[ -f /data/ssh/authorized_keys ] || touch /data/ssh/authorized_keys

chmod 700 /data/ssh /data
chmod 644 /data/ssh/ssh_host_*_key.pub
chmod 600 /data/ssh/ssh_host_*_key /data/ssh/authorized_keys
chown root:root /data

exec /usr/sbin/sshd -De
EOF

mv /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
cat <<EOF > /etc/ssh/sshd_config
Port 2222
PermitRootLogin prohibit-password
PasswordAuthentication no
AuthenticationMethods publickey
AuthorizedKeysFile /data/ssh/authorized_keys
#HostKey /data/ssh/ssh_host_ecdsa_key
HostKey /data/ssh/ssh_host_ed25519_key
HostKey /data/ssh/ssh_host_rsa_key

AllowTcpForwarding yes
GatewayPorts clientspecified
PermitTunnel yes
Subsystem sftp internal-sftp

PermitEmptyPasswords no
UseDNS no
EOF
# SSHD ---------  END  ---------

# APP --------- BEGIN ---------
# could have inotify-ed here but busybox has no wait and it aint worth the extra mb's for the package
cat <<EOF > app/run
#!/bin/sh
# a long running script to monitor the status of an interactive process
#   running in tmux and respawn that tmux session should it die
if [ ! -f /data/start.sh ]; then
  echo -e "#!/bin/sh\nexec sleep 365d" > /data/start.sh
fi
chmod +x /data /data/start.sh

tmux new -ds app \\;\\
     send -lt0 "exec /bootstrap-app.sh" \$'\n'

# wait for bootstrap to write pid
for i in \$(seq 5); do
  [ -f /var/run/user_app.pid ] && break
  sleep 1
done

if [ ! -f /var/run/user_app.pid ]; then
  echo "failed to establish app pid"
  exit 1
fi

# wait on tmux app pid, the s6-supervise ensures we keep waiting and restart on fail
echo "started user app[\$(cat /var/run/user_app.pid)]"
exec waitpid \$(cat /var/run/user_app.pid)
EOF

cat <<EOF > /bootstrap-app.sh
#!/bin/sh
cat /proc/self/stat | awk '{print \$4}' > /var/run/user_app.pid
exec s6-setuidgid app /data/start.sh
EOF

cat <<EOF > app/finish
#!/bin/sh
if [ -f /var/run/user_app.pid ]; then
  # ensure clean exit
  prev_pid=\$(cat /var/run/user_app.pid)
  kill -TERM \$prev_pid 2>/dev/null
  waitpid -t 30 \$prev_pid 2>/dev/null
  kill -9 \$prev_pid 2>/dev/null
  rm /var/run/user_app.pid
fi

# kill tmux if it remained running
[ -z "\$(tmux list-sessions 2>/dev/null | grep '^app:')" ] || tmux kill-session -t app
EOF

echo "40000" > app/timeout-finish
# APP ---------  END  ---------

chmod +x /entry.sh /health.sh /duckdns_update.sh /bootstrap-app.sh crond/run sshd/run app/run app/finish
sed -i 's|\(^root:.*:\).*$|\1/bin/bash|' /etc/passwd /etc/passwd-
echo -e '\x1b[4mWelcome\x1b[0m to my game server docker ya \x1b[1;7;36mlil bitch!\x1b[0m\n' > /etc/motd

EOC

ENV TERM=xterm-256color
EXPOSE 2222/tcp 25565/tcp
VOLUME ["/data"]

CMD ["/entry.sh"]
