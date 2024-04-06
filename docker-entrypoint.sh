#!/bin/bash

readonly app_instance_dir=/appdata/instance
readonly app_server_dir=/appdata/server
readonly app_instance_cfg=/appdata/instance/SpaceEngineers-Dedicated.cfg

readonly steam_app_id=298740

readonly wine_app_instance_dir=Z:\\appdata\\instance

IP=0.0.0.0
SERVER_PORT=27016
WORLD=World

while [ $# != 0 ]; do
	case "$1" in
		-ip) [ -z "$2" ] && { echo >&2 "Error: option $1 requires argument"; exit 2; }
			IP=$2
			shift 2
			;;
		-port) [ -z "$2" ] && { echo >&2 "Error: option $1 requires argument"; exit 2; }
			SERVER_PORT=$2
			shift 2
			;;
		-world) [ -z "$2" ] && { echo >&2 "Error: option $1 requires argument"; exit 2; }
			WORLD=$2
			shift 2
			;;
		*)
			echo >&2 "Error: unrecognized option: $1"
			exit 2
			;;
	esac
done

if [ ! -d $app_instance_dir ] || [ ! -x $app_instance_dir ] || [ ! -w $app_instance_dir ]; then
	echo >&2 "Error: The directory $app_instance_dir does not exist or is not writable."
	echo >&2 "       It must exist and be owned and writable by uid: $(id -u)."
	exit 3
fi

if [ ! -d $app_server_dir ] || [ ! -x $app_server_dir ] || [ ! -w $app_server_dir ]; then
	echo >&2 "Error: The directory $app_server_dir does not exist or is not writable."
	echo >&2 "       It must exist and be owned and writable by uid: $(id -u)."
	exit 3
fi

if [ ! -f $app_instance_cfg ] || [ ! -w $app_instance_cfg ]; then
	echo >&2 "Error: The file $app_instance_cfg does not exist or is not writable."
	echo >&2 "       It must exist and be owned and writable by uid: $(id -u)."
	exit 3
fi

echo "Preparation step: Install or validate server files"

if ! /usr/games/steamcmd +force_install_dir $app_server_dir +login anonymous +@sSteamCmdForcePlatformType windows +app_update $steam_app_id validate +quit; then
	echo >&2 "Error: Failed to install or validate server files; steamcmd exited with status: $?."
	exit 4
fi

echo "Preparation step: Remove server log files"

if ! find $app_instance_dir -maxdepth 1 -name "*.log" -type f -printf " %p\n" -exec rm {} \; ; then
	echo >&2 "Warning: Failed to remove server log files."
fi

echo "Preparation step: Update server configuration"

_wine_app_instance_world_dir=$(echo "$wine_app_instance_dir\\Saves\\$WORLD" | sed 's;\\;\\\\;g')

if ! _sed_loadworld=$(sed -Ei "s;<LoadWorld>(.*)</LoadWorld>;<LoadWorld>$_wine_app_instance_world_dir</LoadWorld>;g w /dev/stdout" $app_instance_cfg); then
	echo >&2 "Error: Updating configuration in $app_instance_cfg: $?"
	exit 5
fi

if [ -z "$_sed_loadworld" ]; then
	echo >&2 "Error: Failed to update <LoadWorld> value in $app_instance_cfg."
	echo >&2 "       This option is updated automatically, but it is required to exist in file beforehand."
	echo >&2 "       If in doubt, add <LoadWorld></LoadWorld> to config in front of </MyConfigDedicated>."
	exit 5
else
	echo " Updated: $(echo "$_sed_loadworld" | sed -E 's;.*(<LoadWorld>.*</LoadWorld>).*;\1;')"
fi

if ! _sed_ip=$(sed -Ei "s;<IP>(.*)</IP>;<IP>$IP</IP>;g w /dev/stdout" $app_instance_cfg); then
	echo >&2 "Error: Updating configuration in $app_instance_cfg: $?"
	exit 5
fi

if [ -z "$_sed_ip" ]; then
	echo >&2 "Warning: Failed to update <IP> value in $app_instance_cfg."
else
	echo " Updated: $(echo "$_sed_ip" | sed -E 's;.*(<IP>.*</IP>).*;\1;')"
fi

if ! _sed_serverport=$(sed -Ei "s;<ServerPort>(.*)</ServerPort>;<ServerPort>$SERVER_PORT</ServerPort>;g w /dev/stdout" $app_instance_cfg); then
	echo >&2 "Error: Updating configuration in $app_instance_cfg: $?"
	exit 5
fi

if [ -z "$_sed_serverport" ]; then
	echo >&2 "Warning: Failed to update <ServerPort> value in $app_instance_cfg."
else
	echo " Updated: $(echo "$_sed_serverport" | sed -E 's;.*(<ServerPort>.*</ServerPort>).*;\1;')"
fi

echo "Starting server..."

if ! cd $app_server_dir/DedicatedServer64; then
	echo >&2 "Error: Failed to change directory to $app_server_dir/DedicatedServer64."
	exit 6
fi

# NB: When current script is executed directly, logging to stdout does not work.
#     It works fine when the script is run from Dockerfile ENTRYPOINT directive.
wine SpaceEngineersDedicated.exe -noconsole -ignorelastsession -path $wine_app_instance_dir &

trap '{
	echo "Sending SIGINT to server process..."
	killall -s INT SpaceEngineersDedicated.exe
}' INT TERM

# $xpid is set if `wait` returns from exited process, and the $rc is that of
# a exited process. Otherwise it means that `wait` was interrupted by a signal.
# $rc=127 to correctly check if `wait` has no children to wait (why?).
until [ -n "$xpid" ] || [ "$rc" = 127 ]; do
	wait -n -p xpid; rc=$?
done

if [ "$rc" != 0 ]; then
	echo "Server shut down with non-zero status: $rc"
	exit 1
fi

echo "Server shut down successfully"
