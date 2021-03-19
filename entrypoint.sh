#!/bin/bash

# File: Pterodactyl Arma 3 Image - entrypoint.sh
# Author: David Wolfe (Red-Thirten)
# Date: 1-30-21

# SteamCMD ID for the Arma 3 GAME (not server). Only used for Workshop mod downloads.
armaGameID=107410
# Color Codes
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

cd /home/container
sleep 1

# Define make mods lowercase function
ModsLowercase () {
	echo -e "\n${GREEN}STARTUP:${NC} Making mod ${CYAN}$1${NC} files/folders lowercase..."
	for SRC in `find ./shared/$1 -depth`
	do
		DST=`dirname "${SRC}"`/`basename "${SRC}" | tr '[A-Z]' '[a-z]'`
		if [ "${SRC}" != "${DST}" ]
		then
			[ ! -e "${DST}" ] && mv -T "${SRC}" "${DST}"
		fi
	done
}

# Define check mods for updates function
ModsOutdated () {

	REMOTEMOD=`curl -s --data "itemcount=1&publishedfileids[0]=$1" https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/`
	REMOTE_CHANGE=`grep -oP '"time_updated":\K[0-9]{5,32}' <<< "$REMOTEMOD"`
	NAME=`grep -oP '"title":"\K[a-z0-9A-Z_\-@]{1,128}' <<< "$REMOTEMOD"`

	if [ -d "shared/@$1" ]; then
		LOCAL_CHANGE=`stat -c %Y "shared/@$1"`

		echo -e "\n${GREEN}STARTUP:${NC} Checking mod ${CYAN}@$1${NC} for update..."

		if [ "$REMOTE_CHANGE" -gt "$LOCAL_CHANGE" ]; then
			echo -e "\n${GREEN}STARTUP:${NC} Mod ${RED}$NAME outdated${NC}"
			UpdateMod $1 $NAME
		else
			echo -e "\n${GREEN}STARTUP:${NC} Mod ${GREEN}$NAME latest version${NC}"
		fi
	else
		echo -e "\n${GREEN}STARTUP:${NC} Installing mod ${CYAN}$1${NC}..."
		UpdateMod $1 $NAME
	fi

}

UpdateMod () {
	echo -e "\n${GREEN}STARTUP:${NC} Downloading/Updating Steam Workshop mod ID: ${CYAN}$1${NC}...\n"
	./steamcmd/steamcmd.sh +login ${STEAM_USER} ${STEAM_PASS} +workshop_download_item $armaGameID $1 validate +quit
	# Move the downloaded mod to the root directory, and replace existing mod if needed
	mkdir -p ./shared/@$2
	rm -rf ./shared/@$2/*
	mv -f ./Steam/steamapps/workshop/content/$armaGameID/$1/* ./shared/@$2
	rm -d ./Steam/steamapps/workshop/content/$armaGameID/$1

	# Move any .bikey's to the keys directory
	echo -e "\n${GREEN}STARTUP:${NC} Moving any mod .bikey files to the ~/keys/ folder...\n"
	find ./shared/@$2 -name "*.bikey" -type f -exec cp {} ./keys \;

	# Make the mods contents all lowercase
	ModsLowercase @$2
}


# Check for old eggs
if [[ -z ${SERVER_BINARY} ]] || [[ -n ${MODS} ]];
then
	echo -e "\n${RED}STARTUP_ERR: Please contact your administrator/host for support, and give them the following message:${NC}\n"
	echo -e "\t${CYAN}Your Arma 3 Egg is outdated and no longer supported.${NC}"
	echo -e "\t${CYAN}Please download the latest version at the following link, and install it in your panel:${NC}"
	echo -e "\t${CYAN}https://github.com/parkervcp/eggs/tree/master/steamcmd_servers/arma${NC}\n"
	exit 1
fi

# Update dedicated server, if specified
if [[ ${UPDATE_SERVER} == "1" ]];
then
	echo -e "\n${GREEN}STARTUP:${NC} Checking for updates to game server with App ID: ${CYAN}${STEAMCMD_APPID}${NC}...\n"
	if [[ -f ./steam.txt ]];
	then
		echo -e "\n${GREEN}STARTUP:${NC} steam.txt found in root folder. Using to run SteamCMD script...\n"
		./steamcmd/steamcmd.sh +login ${STEAM_USER} ${STEAM_PASS} +force_install_dir /home/container +app_update ${STEAMCMD_APPID} ${STEAMCMD_EXTRA_FLAGS} validate +runscript /home/container/steam.txt
	else
		./steamcmd/steamcmd.sh +login ${STEAM_USER} ${STEAM_PASS} +force_install_dir /home/container +app_update ${STEAMCMD_APPID} ${STEAMCMD_EXTRA_FLAGS} validate +quit
	fi
	echo -e "\n${GREEN}STARTUP: Game server update check complete!${NC}\n"
fi

# Download/Update specified Steam Workshop mods, if specified
if [[ -n ${UPDATE_WORKSHOP} ]];
then
	for i in $(echo -e ${UPDATE_WORKSHOP} | sed "s/,/ /g")
	do
		ModsOutdated $i
	done
	echo -e "\n${GREEN}STARTUP: Download/Update Steam Workshop mods complete!${NC}\n"
fi

# Make mods lowercase, if specified
if [[ ${MODS_LOWERCASE} == "1" ]];
then
	for i in $(echo ${MODIFICATIONS} | sed "s/;/ /g")
	do
		ModsLowercase $i
	done

	for i in $(echo ${SERVERMODS} | sed "s/;/ /g")
	do
		ModsLowercase $i
	done
fi

# Check if specified server binary exists. If null (legacy egg is being used), skips check.
if [[ ! -f ./${SERVER_BINARY} ]];
then
	echo -e "\n${RED}STARTUP_ERR: Specified server binary could not be found in files!${NC}"
	exit 1
fi

# Check if basic.cfg exists, and download if not (Arma really doesn't like it missing for some reason)
if [[ -n ${BASIC} ]] && [[ ! -f ./${BASIC} ]];
then
	echo -e "\n${YELLOW}STARTUP: Specified Basic Network Configuration file \"${CYAN}${BASIC}${YELLOW}\" is missing!${NC}"
	echo -e "\t${YELLOW}Downloading default file for use instead...${NC}"
	curl -sSL https://raw.githubusercontent.com/parkervcp/eggs/master/steamcmd_servers/arma/arma3/egg-arma3-config/basic.cfg -o ./${BASIC}
fi

# $NSS_WRAPPER_PASSWD and $NSS_WRAPPER_GROUP have been set by the Dockerfile
export USER_ID=$(id -u)
export GROUP_ID=$(id -g)
envsubst < /passwd.template > ${NSS_WRAPPER_PASSWD}

if [[ ${SERVER_BINARY} == *"x64"* ]];
then
	export LD_PRELOAD=/libnss_wrapper_x64.so
else
	export LD_PRELOAD=/libnss_wrapper.so
fi

# Replace Startup Variables
MODIFIED_STARTUP=`eval echo $(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')`

# Start Headless Clients if applicable
if [[ ${HC_NUM} > 0 ]];
then
	echo -e "\n${GREEN}STARTUP:${NC} Starting ${CYAN}${HC_NUM}${NC} Headless Client(s)."
	for i in $(seq ${HC_NUM})
	do
		./${SERVER_BINARY} -client -connect=127.0.0.1 -port=${SERVER_PORT} -password="${HC_PASSWORD}" -profiles=./serverprofile -bepath=./battleye -mod="${MODIFICATIONS}" ${STARTUP_PARAMS} &
		echo -e "${GREEN}STARTUP:${CYAN} Headless Client $i${NC} launched."
	done
fi

# Start the Server
echo -e "\n${GREEN}STARTUP:${NC} Starting server with the following startup command:"
echo -e "${CYAN}${MODIFIED_STARTUP}${NC}\n"
${MODIFIED_STARTUP}

if [ $? -ne 0 ];
then
    echo -e "\n${RED}PTDL_CONTAINER_ERR: There was an error while attempting to run the start command.${NC}\n"
    exit 1
fi
