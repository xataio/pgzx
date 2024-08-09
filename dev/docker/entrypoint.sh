#!/bin/sh

USER=dev
GROUP=dev

chown "$USER:$GROUP" "/home/${USER}/workdir"
if [ "$#" -eq 0 ]; then
	exec runuser -u "$USER" nix develop
else
	exec runuser -u "$USER" "$@"
fi
