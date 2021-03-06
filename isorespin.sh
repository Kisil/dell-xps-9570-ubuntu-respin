#!/bin/bash

#	This script was initially based on the information documented on the following sites:
#	https://help.ubuntu.com/community/LiveCDCustomization (shared under a Creative Commons Attribution-ShareAlike 3.0 License available at https://help.ubuntu.com/community/License)
#	https://wiki.ubuntu.com/KernelTeam/GitKernelBuild (shared under a Creative Commons Attribution-ShareAlike 3.0 License available at https://help.ubuntu.com/community/License)
#	and then further developed by Linuxium (linuxium@linuxium.com.au).
#	Version 1: This work is licensed under a Creative Commons Attribution-ShareAlike 3.0 License.
#	Version 2.01.050417: This work is licensed under a Creative Commons Attribution-ShareAlike 4.0 License.
#	Version 3.01.120417: This work is licensed under GNU GPL version 3 under one-way compatibility with CC BY-SA 4.0.
#	Version 3.02.130417, 4.06.220417 to 4.09.280417, 5.01.020517 and 6.01.120517: This work is licensed under GNU GPL version 3.
#	Version 6.02.0 to 6.03.3: This work is licensed under GNU GPL version 3.
#	Version 7.1.0 to 7.2.0: This work is licensed under GNU GPL version 3.
#	Version 7.2.1: This work is licensed under GNU GPL version 3.

#	Linuxium's script to respin an Ubuntu, Ubuntu flavour, Linux Mint, neon, elementary, BackBox or Peppermint ISO and optionally add/remove functionality like kernels/packages/files etc
#	Copyright (C) 2017 Ian W. Morrison (linuxium@linuxium.com.au)
#	
#	This program is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 3 of the License, or
#	(at your option) any later version.
#	
#	This program is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#	GNU General Public License for more details.
#	
#	You should have received a copy of the GNU General Public License
#	along with this program. If not, see <http://www.gnu.org/licenses/>.

VERSION="7.2.1"
MAINLINE_URL="http://kernel.ubuntu.com/~kernel-ppa/mainline"
SUPPORTED_OS=("Ubuntu" "Kubuntu" "Lubuntu" "Ubuntu-Budgie" "Ubuntu-GNOME" "Ubuntu-MATE" "Xubuntu" "Mint" "neon" "elementary" "BackBox" "Peppermint")
LONG_FLAGS=("help" "version" "update" "kernel" "repository" "erase" "package" "local-package" "download" "file" "boot" "storage" "iso" "work-directory" "command" "output" "grub" "key" "upgrade")
PROCESSORS=("apollo" "atom")
ROLLING_POSSIBILITIES=("rolling-release" "rolling-release-hwe" "rolling-release-hwe-edge" "rolling-proposed" "rolling-proposed-hwe" "rolling-proposed-hwe-edge" "rolling-testing" "rolling-testing-hwe" "rolling-testing-hwe-edge" "rolling-unstable" "rolling-unstable-hwe" "rolling-unstable-hwe-edge")
ROLLING_LIST=("rolling-list")
IS_A_LONG_FLAG=("${LONG_FLAGS[@]}" "${PROCESSORS[@]}" "${ROLLING_POSSIBILITIES[@]}" "${ROLLING_LIST[@]}")
NEEDS_AN_ARGUMENT=("k" "r" "e" "p" "l" "d" "f" "b" "s" "i" "w" "c" "o" "g")

trap 'FORCED_EXIT' SIGHUP SIGINT SIGTERM

function FORCED_EXIT {
	CLOSE_DISPLAY_BOX
	DISPLAY_MESSAGE "${0}: Forced exit ... ISO not created."
	cd ${CWD}
	if [ -d ${WIP} ]; then
		cd ${WIP}
		sudo umount mnt > /dev/null 2>&1 || sudo umount -lf mnt > /dev/null 2>&1
		sudo umount iso-chroot/dev > /dev/null 2>&1 || sudo umount -lf iso-chroot/dev > /dev/null 2>&1
		cd ${CWD}
		sudo rm -rf ${WIP}
	fi
	sudo rm -f ${CWD}/.isorespin.sh.lock
	exit -1
}

function DIRTY_EXIT {
	CLOSE_DISPLAY_BOX
	cd ${CWD}
	sudo rm -f ${CWD}/.isorespin.sh.lock
	exit 1
}

function MESSY_EXIT {
	CLOSE_DISPLAY_BOX
	cd ${CWD}
	if [ -d ${WIP} ]; then
		cd ${WIP}
		sudo umount mnt > /dev/null 2>&1 || sudo umount -lf mnt > /dev/null 2>&1
		cd ${CWD}
		sudo rm -rf ${WIP}
	fi
	sudo rm -f ${CWD}/.isorespin.sh.lock
	exit 1
}

function CLEAN_EXIT {
	CLOSE_DISPLAY_BOX
	cd ${CWD}
	if [ -d ${WIP} ]; then
		sudo rm -rf ${WIP}
	fi
	sudo rm -f ${CWD}/.isorespin.sh.lock
	exit 1
}

function CLOSE_DISPLAY_BOX {
	if [ -n "${GUI_BOX_CONTENT}" ] && [ "$(ps -p ${GUI_BOX_CONTENT} -o comm --no-header)" == "zenity" ]; then
		sudo kill -9 ${GUI_BOX_CONTENT} > /dev/null 2>&1
		GUI_BOX_CONTENT=""
	fi
	if [ -n "${GUI_BOX_BORDER}" ] && [ "$(ps -p ${GUI_BOX_BORDER} -o comm --no-header)" == "sleep" ]; then
		sudo kill -9 ${GUI_BOX_BORDER} > /dev/null 2>&1
		GUI_BOX_BORDER=""
	fi
}

function DISPLAY_MESSAGE {
	DISPLAY_TEXT="$1"
	CLOSE_DISPLAY_BOX
	${GUI} && zenity --info --title="isorespin.sh" --text="${DISPLAY_TEXT}" 2> /dev/null
	${GUI} || echo "${DISPLAY_TEXT}"
	if [ -f ${ISORESPIN_LOGFILE} ]; then
		echo "${DISPLAY_TEXT#${0}: }" >> ${ISORESPIN_LOGFILE} 2> /dev/null
	fi
}

function DISPLAY_PROGRESS {
	DISPLAY_TEXT="$1"
	CLOSE_DISPLAY_BOX
	if ${GUI}; then
		sleep infinity | zenity --progress --title="isorespin.sh" --text="${DISPLAY_TEXT}" --auto-close --no-cancel --pulsate 2> /dev/null &
		GUI_BOX_BORDER=$(jobs -l | (read GUI_BOX_BORDER; echo $GUI_BOX_BORDER | awk '{print $2}'))
		GUI_BOX_CONTENT=$(jobs -l | sed 1d | (read GUI_BOX_CONTENT; echo $GUI_BOX_CONTENT | awk '{print $1}'))
		disown ${GUI_BOX_BORDER}
	fi
	${GUI} || echo "${DISPLAY_TEXT}"
}

function USAGE {
	echo "Usage: ${0} [ -h | -v | --rolling-list ]"
	echo "       ${0} -i <ISO> [ [ -u | -k <kernel> ] | -r \"<repo> ... \" | -p \"<pkg> ... \" | -l \"<pkg.deb> ... \" | -f \"<file> | <directory> ... \" | [ -s <size>MB | GB ] | [ -b GRUB | rEFInd ] | ..."
	echo "       ${0} ... -w <directory> | -d \"<pkg> ... \" | -e \"<pkg> ... \" | -c \"<cmd> ... \" | -o \"<file> | <directory> ... \" | -g \"\" | \"<kernel boot parameter> ... \" | ..."
	echo "       ${0} ... --apollo | --atom | ..."
	echo "       ${0} ... --rolling-release | --rolling-release-hwe | --rolling-release-hwe-edge | --rolling-proposed | --rolling-proposed-hwe | --rolling-proposed-hwe-edge | ..."
	echo "       ${0} ... --rolling-testing | --rolling-testing-hwe | --rolling-testing-hwe-edge | --rolling-unstable | --rolling-unstable-hwe | --rolling-unstable-hwe-edge | ..."
	echo "       ${0} ... --upgrade | --key  \"<repo> ... \" ]"
}

function USE_GUI_TO_GENERATE_CMDLINE {
	GUI_BOX_CONTENT=""
	GUI_BOX_BORDER=""
	TITLE="isorespin.sh (version ${VERSION})"
	while true
	do
		OPTIONS=$(zenity --list --title="isorespin.sh (version ${VERSION})" --text "Select option" --height=340 --width=600 --checklist --hide-header \
			--column ""	--column "" \
			TRUE		"ISO" \
			FALSE		"Add frequently used options for Intel Atom (Bay Trail/Cherry Trail) or Intel Apollo processors" \
			FALSE		"Upgrade kernel" \
			FALSE		"Add repositories" \
			FALSE		"Include packages" \
			FALSE		"Include local packages" \
			FALSE		"Add files" \
			FALSE		"Add directories" \
			FALSE		"Add persistence" \
			FALSE		"Advanced Options" \
			--separator=":" --ok-label="Continue" --cancel-label="Quit" 2> /dev/null)
		if [ -z "${OPTIONS}" ]; then
			rm -f ${ISORESPIN_LOGFILE}
			DIRTY_EXIT
		fi
		OIFS="${IFS}"
		IFS=':' FLAGS=(${OPTIONS})
		IFS="${OIFS}"
		CMDLINE=""
		for FLAG in "${FLAGS[@]}"
		do
			case ${FLAG} in
				"ISO")
					ISO=$(zenity --file-selection --file-filter='ISO (*.iso) | *.iso' --title="Select the ISO to respin" 2> /dev/null)
					if [ -z "${ISO}" ]; then
						break
					fi
					CMDLINE+=" -i ${ISO}"
					;;
				"Add frequently used options for Intel Atom (Bay Trail/Cherry Trail) or Intel Apollo processors")
					PROCESSOR=$(zenity --list --title="isorespin.sh" --text "Make a selection" --height=160 --width=550 --radiolist --column "" --column "" --hide-header TRUE "Add frequently used options for an Intel Atom (Bay Trail or Cherry Trail) processor" FALSE "Add frequently used options for an Intel Apollo processor" 2> /dev/null)
					if [ "${PROCESSOR}" == "Add frequently used options for an Intel Atom (Bay Trail or Cherry Trail) processor" ]; then
						CMDLINE+=" --atom"
					else
						CMDLINE+=" --apollo"
					fi
					;;
				"Upgrade kernel")
					CHOICE=$(zenity --list --title="isorespin.sh" --text "Make a selection" --radiolist --column "" --column "" --hide-header TRUE "Upgrade kernel to latest available version" FALSE "Upgrade kernel to a specific version" FALSE "Upgrade to a rolling kernel" 2> /dev/null)
					if [ "${CHOICE}" == "Upgrade to a rolling kernel" ]; then
						ROLLING=$(zenity --list --title="isorespin.sh" --text "Make a selection" --height=390 --width=300 --radiolist --column "" --column "" --hide-header \
						FALSE "Rolling release kernel" \
						FALSE "Rolling release-hwe kernel" \
						FALSE "Rolling release-hwe-edge kernel" \
						FALSE "Rolling proposed kernel" \
						FALSE "Rolling proposed-hwe kernel" \
						FALSE "Rolling proposed-hwe-edge kernel" \
						FALSE "Rolling testing kernel" \
						FALSE "Rolling testing-hwe kernel" \
						FALSE "Rolling testing-hwe-edge kernel" \
						FALSE "Rolling unstable kernel" \
						FALSE "Rolling unstable-hwe kernel" \
						FALSE "Rolling unstable-hwe-edge kernel" \
						2> /dev/null)
						ROLLING=${ROLLING#Rolling }
						CMDLINE+=" --rolling-${ROLLING% kernel}"
					elif [ "${CHOICE}" == "Upgrade kernel to a specific version" ]; then
						KERNEL=$(zenity --entry --title="isorespin.sh" --text="Enter kernel version (e.g. v4.12-rc1)" 2> /dev/null)
						CMDLINE+=" -k ${KERNEL}"
					else
						CMDLINE+=" -u"
					fi
					;;
				"Add repositories")
					MORE=0
					while [ "${MORE}" == "0" ]
					do
						REPOSITORY=$(zenity --entry --title="isorespin.sh" --text="Enter repository to add to the ISO" 2> /dev/null)
						CMDLINE+=" -r \"${REPOSITORY}\""
						zenity --question --title="Add repositories" --text="Would you like to add another?" 2> /dev/null
						MORE=$?
					done
					;;
				"Include packages")
					MORE=0
					while [ "${MORE}" == "0" ]
					do
						PACKAGES=$(zenity --entry --title="isorespin.sh" --text="Enter packages to install to the ISO" 2> /dev/null)
						CMDLINE+=" -p \"${PACKAGES}\""
						zenity --question --title="Include packages" --text="Would you like to add another?" 2> /dev/null
						MORE=$?
					done
					;;
				"Include local packages")
					MORE=0
					while [ "${MORE}" == "0" ]
					do
						LOCAL_PACKAGE=$(zenity --file-selection --file-filter='Local Package (*.deb) | *.deb' --title="Select local package to install to the ISO" 2> /dev/null)
						if [ -z "${LOCAL_PACKAGE}" ]; then
							break
						fi
						CMDLINE+=" -l \"${LOCAL_PACKAGE}\""
						zenity --question --title="Include local packages" --text="Would you like to add another?" 2> /dev/null
						MORE=$?
					done
					;;
				"Add files")
					MORE=0
					while [ "${MORE}" == "0" ]
					do
						FILE=$(zenity --file-selection --file-filter='Files (*.*) | *.*' --title="Select file to add to the ISO" 2> /dev/null)
						if [ -z "${FILE}" ]; then
							break
						fi
						CMDLINE+=" -f \"${FILE}\""
						zenity --question --title="Add files" --text="Would you like to add another?" 2> /dev/null
						MORE=$?
					done
					;;
				"Add directories")
					MORE=0
					while [ "${MORE}" == "0" ]
					do
						FILE=$(zenity --file-selection --directory --title="Select directory to add to the ISO" 2> /dev/null)
						if [ -z "${FILE}" ]; then
							break
						fi
						CMDLINE+=" -f \"${FILE}\""
						zenity --question --title="Add directories" --text="Would you like to add another?" 2> /dev/null
						MORE=$?
					done
					;;
				"Add persistence")
					STORAGE=$(zenity --scale --title="isorespin.sh" --text "Size of persistence partition in MBs" --min-value=128 --max-value=2048 --value=128 --step 64 2> /dev/null)
					CMDLINE+=" -s ${STORAGE}MB"
					;;
				"Advanced Options")
					OPTIONS=$(zenity --list --title="isorespin.sh (version ${VERSION})" --text "Select 'advanced' option" --height=295 --width=400 --checklist --hide-header \
						--column ""	--column "" \
						FALSE		"Work directory" \
						FALSE		"Download packages" \
						FALSE		"Purge packages" \
						FALSE		"Add commands" \
						FALSE		"Output files/directories" \
						FALSE		"Select bootloader/bootmanager" \
						FALSE		"Delete initial kernel boot parameters" \
						FALSE		"Add additional kernel boot parameters" \
						--separator=":" --ok-label="Continue" --cancel-label="Quit" 2> /dev/null)
					if [ -z "${OPTIONS}" ]; then
						continue
					fi
					OIFS="${IFS}"
					IFS=':' FLAGS=(${OPTIONS})
					IFS="${OIFS}"
					for FLAG in "${FLAGS[@]}"
					do
						case ${FLAG} in
							"Select bootloader/bootmanager")
								CHOICE=$(zenity --list --title="isorespin.sh" --text "Make a selection" --radiolist --column "" --column "" --hide-header TRUE "GRUB bootloader" FALSE "rEFInd bootmanager" 2> /dev/null)
								if [ "${CHOICE}" == "rEFInd bootmanager" ]; then
									CMDLINE+=" -b rEFInd"
								else
									CMDLINE+=" -b GRUB"
								fi
								;;
							"Work directory")
								WORK_DIRECTORY=$(zenity --file-selection --directory --title="Select the work directory" 2> /dev/null)
								if [ -z "${WORK_DIRECTORY}" ]; then
									break
								fi
								CMDLINE+=" -w ${WORK_DIRECTORY}"
								;;
							"Download packages")
								MORE=0
								while [ "${MORE}" == "0" ]
								do
									PACKAGES=$(zenity --entry --title="isorespin.sh" --text="Enter packages to download to the ISO" 2> /dev/null)
									CMDLINE+=" -d \"${PACKAGES}\""
									zenity --question --title="Download packages" --text="Would you like to add another?" 2> /dev/null
									MORE=$?
								done
								;;
							"Add commands")
								MORE=0
								while [ "${MORE}" == "0" ]
								do
									COMMANDS=$(zenity --entry --title="isorespin.sh" --text="Enter command to run on the ISO" 2> /dev/null)
									CMDLINE+=" -c \"${COMMANDS}\""
									zenity --question --title="Add commands" --text="Would you like to add another?" 2> /dev/null
									MORE=$?
								done
								;;
							"Purge packages")
								MORE=0
								while [ "${MORE}" == "0" ]
								do
									PURGE_PACKAGES=$(zenity --entry --title="isorespin.sh" --text="Enter packages to purge from the ISO" 2> /dev/null)
									CMDLINE+=" -e \"${PURGE_PACKAGES}\""
									zenity --question --title="Purge packages" --text="Would you like to purge another?" 2> /dev/null
									MORE=$?
								done
								;;
							"Output files/directories")
								MORE=0
								while [ "${MORE}" == "0" ]
								do
									OUTPUT_FILE=$(zenity --entry --title="isorespin.sh" --text="Enter file or directory to output from the ISO" 2> /dev/null)
									CMDLINE+=" -o \"${OUTPUT_FILE}\""
									zenity --question --title="Output files/directories" --text="Would you like to add another?" 2> /dev/null
									MORE=$?
								done
								;;
							"Delete initial kernel boot parameters")
								CMDLINE+=" -g \"\""
								;;
							"Add additional kernel boot parameters")
								MORE=0
								while [ "${MORE}" == "0" ]
								do
									KERNEL_BOOT_PARAMETER=$(zenity --entry --title="isorespin.sh" --text="Enter kernel boot parameter to add to the ISO" 2> /dev/null)
									CMDLINE+=" -g \"${KERNEL_BOOT_PARAMETER}\""
									zenity --question --title="Add kernel boot parameters" --text="Would you like to add another?" 2> /dev/null
									MORE=$?
								done
								;;
						esac
					done
					;;
			esac
		done
		if [ -n "${ISO}" ]; then
			zenity --question --text="${CMDLINE}" --title="Would you like to run 'isorespin.sh' with the following options?" 2> /dev/null
			RUN_SCRIPT=$?
			if [ ${RUN_SCRIPT} != 0 ]; then
				rm -f ${ISORESPIN_LOGFILE}
				DIRTY_EXIT
			fi
			break
		fi
	done
	CMDLINE="${CMDLINE:1}"
}

function CHECK_WHETHER { for MATCHED_FLAG in "${@:2}"; do [[ "${1}" == "${MATCHED_FLAG}" ]] && return 0; done && return 1; }

function GET_LONG_FLAG { for VALUE in $(seq 0 $((${#IS_A_LONG_FLAG[@]}-1))); do [[ "${FLAG:1:1}" == "${IS_A_LONG_FLAG[${VALUE}]:0:1}" ]] && LONG_FLAG="--${IS_A_LONG_FLAG[${VALUE}]}" && return 0; done; LONG_FLAG="" && return 1; }

function CHECK_CMDLINE {
	${GUI} && DISPLAY_PROGRESS "Checking invocation ..."
	ISORESPIN_SCRIPT=$(readlink -f ${0})
	ISORESPIN_COMMAND="$@"
	echo "Script '${0}' called with '${ISORESPIN_COMMAND}' ..." >> ${ISORESPIN_LOGFILE}
	I_OPTION=false
	UPDATE_KERNEL=false
	U_OPTION=false
	K_OPTION=false
	PURGE_PACKAGE=false
	E_OPTION=false
	PURGE_ARRAY=0
	ADD_KEY=false
	KEY_OPTION=false
	KEY_ARRAY=0
	ADD_REPOSITORY=false
	R_OPTION=false
	REPOSITORY_ARRAY=0
	ADD_PACKAGE=false
	P_OPTION=false
	PACKAGE_ARRAY=0
	REMOVE_ROLLING_REPOSITORY=false
	ROLLING_KERNEL_OPTION=false
	ADD_LOCAL_PACKAGE=false
	L_OPTION=false
	LOCAL_PACKAGE_ARRAY=0
	UPGRADE=false
	ADD_DOWNLOAD=false
	D_OPTION=false
	DOWNLOAD_ARRAY=0
	ADD_FILE=false
	F_OPTION=false
	FILE_ARRAY=0
	ADD_COMMAND=false
	C_OPTION=false
	COMMAND_ARRAY=0
	EXTRACT_FILE=false
	O_OPTION=false
	OUTPUT_FILE_ARRAY=0
	S_OPTION=false
	ADD_PERSISTENCE=false;
	B_OPTION=false
	BOOTLOADER=""
	PERSISTENCE=""
	USE_REFIND_BOOTLOADER=false
	ADD_KERNEL_BOOT_PARAMETER=false
	KERNEL_BOOT_PARAMETER=""
	DELETE_KERNEL_BOOT_PARAMETER=false
	W_OPTION=false
	DIRECTORY_ARRAY=0
	TARGET_PROCESSOR_OPTION=false
	FLAG_FOUND=false
	ARGUMENT_FOUND=true
	MULTIPLE_ARGUMENTS=false;
	MULTIPLE=""
	EMBEDDED_QUOTE=false
	CMDLINE=""
	for VALUE in $(seq 0 $((${#IS_A_LONG_FLAG[@]}-1)))
	do
		IS_A_SHORT_FLAG[${VALUE}]="${IS_A_LONG_FLAG[${VALUE}]:0:1}"
	done
	for EACH_OPTION_IN_CMDLINE in $(seq 1 $#)
	do
		OPTION=${@:${EACH_OPTION_IN_CMDLINE}:1}
		# flag
		if ! ${MULTIPLE_ARGUMENTS} && [ "${OPTION:0:1}" == '-' ]; then
			if ! ${ARGUMENT_FOUND}; then
				if [ -z "${LONG_FLAG}" ]; then
					GET_LONG_FLAG
				fi
				if [ "${LONG_FLAG}" == "--key" ]; then
					DISPLAY_MESSAGE "${0}: An argument must be specified when using '${LONG_FLAG}'."
				else
					DISPLAY_MESSAGE "${0}: An argument must be specified when using '${FLAG}' or '${LONG_FLAG}'."
				fi
				DIRTY_EXIT
			elif [ "${OPTION:1:1}" == '-' ] ; then
				if (! CHECK_WHETHER "${OPTION:2}" "${IS_A_LONG_FLAG[@]}") ; then
					DISPLAY_MESSAGE "${0}: Invalid option '${OPTION}'."
					USAGE
					rm -f ${ISORESPIN_LOGFILE}
					DIRTY_EXIT
				fi
				SHORT_FLAG="${OPTION:2:1}"
			else
				if (! CHECK_WHETHER "${OPTION:1}" "${IS_A_SHORT_FLAG[@]}"); then
					DISPLAY_MESSAGE "${0}: Invalid option '${OPTION}'."
					USAGE
					rm -f ${ISORESPIN_LOGFILE}
					DIRTY_EXIT
				fi
				SHORT_FLAG="${OPTION:1}"
			fi
			CMDLINE="${CMDLINE} -${SHORT_FLAG}"
			FLAG="-${SHORT_FLAG}"
			LONG_FLAG=""
			FLAG_FOUND=true
			ARGUMENT_FOUND=false
			if (CHECK_WHETHER "${SHORT_FLAG}" "${NEEDS_AN_ARGUMENT[@]}"); then
				fixme_ARGUMENT_FOUND=true
			fi
			case "${SHORT_FLAG}" in
				"h")
					OPTION_HELP
					;;
				"v")
					OPTION_VERSION
					;;
				"u")	# uPDATE or uPGRADE
					if [ "${OPTION}" == "--upgrade" ]; then
						LONG_FLAG="--upgrade"
						OPTION_UPGRADE
					else
						OPTION_UPDATE
					fi
					FLAG_FOUND=false
					ARGUMENT_FOUND=true
					;;
				"a")	# aTOM or aPOLLO
					TARGET_PROCESSOR=${OPTION:2}
					TARGET_PROCESSOR=${TARGET_PROCESSOR,,}
					OPTION_TARGET_PROCESSOR
					CMDLINE="${CMDLINE} ${TARGET_PROCESSOR}"
					FLAG_FOUND=false
					ARGUMENT_FOUND=true
					;;
				"r")	# rEPOSITORY or rOLLING
					if [ "${OPTION}" != "-r" -a "${OPTION}" != "--repository" ]; then
						ROLLING=${OPTION:2}
						ROLLING=${ROLLING,,}
						if ( ! ROLLING_POSSIBLE "${ROLLING}" "${ROLLING_POSSIBILITIES[@]}" ); then
							if [ "${ROLLING}" == "rolling-list" ]; then
								OPTION_ROLLING_LIST
							else
								DISPLAY_MESSAGE "${0}: Rolling must be one of '${ROLLING_POSSIBILITIES[*]}'."
								DIRTY_EXIT
							fi
						else
							OPTION_ROLLING_KERNEL
							CMDLINE="${CMDLINE} ${ROLLING}"
							FLAG_FOUND=false
							ARGUMENT_FOUND=true
						fi
					fi
					;;
				"k")	# kERNEL or kEY
					if [ "${OPTION}" == "--key" ]; then
						LONG_FLAG="--key"
						KEY_OPTION=true
					fi
					;;
				*)
					NEXT_OPTION_IN_CMDLINE=$((EACH_OPTION_IN_CMDLINE+1))
					;;
			esac
		# argument
		else
			if ! ${MULTIPLE_ARGUMENTS}; then
				# ""
				if [ "${#OPTION}" -eq 0 ] || [ "${OPTION:0:1}" == '"' -a "${OPTION:$((${#OPTION}-1)):1}" == '"' -a "${#OPTION}" -eq 2 ]; then
					if (CHECK_WHETHER "${SHORT_FLAG}" "${NEEDS_AN_ARGUMENT[@]}"); then
						# exception for '-g ""' which is valid
						if [ "${SHORT_FLAG}" == 'g' ]; then
							ARGUMENT_FOUND=true
						else
							ARGUMENT_FOUND=false
							break
						fi
					fi
				# "OPTION"
				elif [ "${OPTION:0:1}" == '"' -a "${OPTION:$((${#OPTION}-1)):1}" == '"' ]; then
					OPTION=${OPTION/#\"/ }
					OPTION=${OPTION/%\"/ }
					ARGUMENT_FOUND=true
				# "OPTION ...
				elif [ "${OPTION:0:1}" == '"' -a "${OPTION:$((${#OPTION}-1)):1}" != '"' ]; then
					MULTIPLE_ARGUMENTS=true;
					MULTIPLE=${OPTION:1:${#OPTION}}
				else
					ARGUMENT_FOUND=true
				fi
			else
				# ... "OPTION" ...
				if [ "${OPTION:0:1}" == '"' -a "${OPTION:$((${#OPTION}-2)):1}" != '"' -a "${OPTION:$((${#OPTION}-1)):1}" == '"' ]; then
					MULTIPLE+=" ${OPTION}"
				# ... "OPTION ...
				elif [ "${OPTION:0:1}" == '"' -a "${OPTION:$((${#OPTION}-1)):1}" != '"' ]; then
					EMBEDDED_QUOTE=true
					MULTIPLE+=" ${OPTION}"
				# ... OPTION" ...
				elif ${EMBEDDED_QUOTE} && [ "${OPTION:0:1}" != '"' -a "${OPTION:$((${#OPTION}-2)):1}" != '"' -a "${OPTION:$((${#OPTION}-1)):1}" == '"' ]; then
					EMBEDDED_QUOTE=false
					MULTIPLE+=" ${OPTION}"
				# ... OPTION"
				elif ! ${EMBEDDED_QUOTE} && [ "${OPTION:0:1}" != '"' -a "${OPTION:$((${#OPTION}-2)):1}" != '"' -a "${OPTION:$((${#OPTION}-1)):1}" == '"' ]; then
					MULTIPLE+=" ${OPTION:0:$((${#OPTION}-1))}"
					MULTIPLE_ARGUMENTS=false
					ARGUMENT_FOUND=true
					OPTION=${MULTIPLE}
				# ... OPTION""
				elif ${EMBEDDED_QUOTE} && [ "${OPTION:0:1}" != '"' -a "${OPTION:$((${#OPTION}-2)):1}" == '"' -a "${OPTION:$((${#OPTION}-1)):1}" == '"' ]; then
					MULTIPLE+=" ${OPTION:0:$((${#OPTION}-1))}" 
					EMBEDDED_QUOTE=false
					MULTIPLE_ARGUMENTS=false
					ARGUMENT_FOUND=true
					OPTION=${MULTIPLE}
				# ... "OPTION"""
				elif ${EMBEDDED_QUOTE} && [ "${OPTION:0:1}" == '"' -a "${OPTION:$((${#OPTION}-2)):1}" == '"' -a "${OPTION:$((${#OPTION}-1)):1}" == '"' ]; then
					MULTIPLE+=" ${OPTION:0:$((${#OPTION}-1))}" 
					EMBEDDED_QUOTE=false
					MULTIPLE_ARGUMENTS=false
					ARGUMENT_FOUND=true
					OPTION=${MULTIPLE}
				# ... "OPTION""
				elif ! ${EMBEDDED_QUOTE} && [ "${OPTION:0:1}" == '"' -a "${OPTION:$((${#OPTION}-2)):1}" == '"' -a "${OPTION:$((${#OPTION}-1)):1}" == '"' ]; then
					MULTIPLE+=" ${OPTION:0:$((${#OPTION}-1))}"
					MULTIPLE_ARGUMENTS=false
					ARGUMENT_FOUND=true
					OPTION=${MULTIPLE}
				# ... OPTION ...
				else
					MULTIPLE+=" ${OPTION}"
				fi
			fi
			if ! ${MULTIPLE_ARGUMENTS}; then
				if ! ${FLAG_FOUND} || ! (CHECK_WHETHER "${SHORT_FLAG}" "${NEEDS_AN_ARGUMENT[@]}"); then
					DISPLAY_MESSAGE "${0}: Flag not specified for '${OPTION}'."
					DIRTY_EXIT
				fi
				case "${FLAG}" in
					"-k")
						if ${KEY_OPTION}; then
							LONG_FLAG="key"
							CMDLINE="${CMDLINE} KEY"
							KEYS[${KEY_ARRAY}]="${OPTION}"
							((KEY_ARRAY++))
						else
							LONG_FLAG="kernel"
							MAINLINE_BRANCH="${OPTION}"
							OPTION_KERNEL
							CMDLINE="${CMDLINE} ${OPTION}"
						fi
						;;
					"-r")
						if ! ${ROLLING_KERNEL_OPTION}; then
							LONG_FLAG="repository"
							CMDLINE="${CMDLINE} REPOSITORY"
							REPOSITORIES[${REPOSITORY_ARRAY}]="${OPTION}"
							((REPOSITORY_ARRAY++))
							R_OPTION=true
						fi
						;;
					"-e")
						LONG_FLAG="erase"
						CMDLINE="${CMDLINE} PURGE_PACKAGE"
						PURGE_PACKAGES[${PURGE_ARRAY}]="${OPTION}"
						((PURGE_ARRAY++))
						E_OPTION=true
						;;
					"-p")
						LONG_FLAG="package"
						CMDLINE="${CMDLINE} PACKAGE"
						PACKAGES[${PACKAGE_ARRAY}]="${OPTION}"
						((PACKAGE_ARRAY++))
						P_OPTION=true
						;;
					"-l")
						LONG_FLAG="local-package"
						CMDLINE="${CMDLINE} LOCAL_PACKAGE"
						LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]="${OPTION}"
						((LOCAL_PACKAGE_ARRAY++))
						L_OPTION=true
						;;
					"-d")
						LONG_FLAG="download"
						CMDLINE="${CMDLINE} DOWNLOAD"
						DOWNLOADS[${DOWNLOAD_ARRAY}]="${OPTION}"
						((DOWNLOAD_ARRAY++))
						D_OPTION=true
						;;
					"-f")
						LONG_FLAG="file"
						CMDLINE="${CMDLINE} FILE"
						FILES[${FILE_ARRAY}]="${OPTION}"
						((FILE_ARRAY++))
						F_OPTION=true
						;;
					"-b")
						LONG_FLAG="boot"
						BOOT="${OPTION}"
						OPTION_BOOT
						CMDLINE="${CMDLINE} ${OPTION}"
						;;
					"-s")
						LONG_FLAG="storage"
						STORAGE="${OPTION}"
						OPTION_STORAGE
						CMDLINE="${CMDLINE} ${OPTION}"
						;;
					"-i")
						LONG_FLAG="iso"
						ISO="${OPTION}"
						OPTION_ISO
						CMDLINE="${CMDLINE} ${OPTION}"
						;;
					"-w")
						LONG_FLAG="work-directory"
						WORK_DIRECTORY="${OPTION}"
						OPTION_WORK
						CMDLINE="${CMDLINE} ${OPTION}"
						;;
					"-c")
						LONG_FLAG="command"
						CMDLINE="${CMDLINE} COMMAND"
						COMMANDS[${COMMAND_ARRAY}]="${OPTION}"
						((COMMAND_ARRAY++))
						C_OPTION=true
						;;
					"-o")
						LONG_FLAG="output"
						CMDLINE="${CMDLINE} OUTPUT"
						OUTPUT_FILES[${OUTPUT_FILE_ARRAY}]="${OPTION}"
						((OUTPUT_FILE_ARRAY++))
						O_OPTION=true
						;;
					"-g")
						LONG_FLAG="grub"
						CMDLINE="${CMDLINE} KERNEL_BOOT_PARAMETER"
						if [ "${OPTION:0:1}" == " " ]; then
							OPTION="${OPTION# }"
						fi
						if [ "${OPTION: -1}" == " " ]; then
							OPTION="${OPTION% }"
						fi
						if [ -z "${OPTION}" -o "${OPTION}" == '""' ]; then
							DELETE_KERNEL_BOOT_PARAMETER=true
						else
							ADD_KERNEL_BOOT_PARAMETER=true
							KERNEL_BOOT_PARAMETER="${KERNEL_BOOT_PARAMETER} ${OPTION}"
						fi
						;;
					*)
						LONG_FLAG=""
						CMDLINE="${CMDLINE} ${OPTION}"
						;;
				esac
				FLAG_FOUND=false
			fi
		fi
	done
	if ! ${ARGUMENT_FOUND}; then
		if [ -z "${LONG_FLAG}" ]; then
			GET_LONG_FLAG
		fi
		if [ "${LONG_FLAG}" == "--key" ]; then
			DISPLAY_MESSAGE "${0}: An argument must be specified when using '${LONG_FLAG}'."
		else
			DISPLAY_MESSAGE "${0}: An argument must be specified when using '${FLAG}' or '${LONG_FLAG}'."
		fi
		DIRTY_EXIT
	fi
	CMDLINE="${CMDLINE:1}"
	if [ -z "${ISO}" ]; then
		DISPLAY_MESSAGE "${0}: An ISO must be specified using '-i' or '--iso' option."
		DIRTY_EXIT
	fi
	if ! ${W_OPTION} && [ -f isorespin -o -d isorespin ] ; then
		DISPLAY_MESSAGE "${0}: Work directory 'isorespin' already exists."
		DIRTY_EXIT
	fi
}

function PROCESS_CMDLINE {
	sudo rm -rf ${WIP}
	sudo mkdir ${WIP} > /dev/null 2>&1
	if [ -z "${WORK_DIRECTORY}" ]; then
		echo "Work directory '$(basename ${WIP})' used ..." >> ${ISORESPIN_LOGFILE}
	else
		echo "Work directory '${WIP}' used ..." >> ${ISORESPIN_LOGFILE}
	fi
	CHECK_FOR_FREE_SPACE
	${O_OPTION} && PROCESS_O_OPTION
	${C_OPTION} && PROCESS_C_OPTION
	${S_OPTION} && PROCESS_S_OPTION
	${F_OPTION} && PROCESS_F_OPTION
	${D_OPTION} && PROCESS_D_OPTION
	${L_OPTION} && PROCESS_L_OPTION
	${R_OPTION} && PROCESS_R_OPTION
	${KEY_OPTION} && PROCESS_KEY_OPTION
	${E_OPTION} && PROCESS_E_OPTION
	${P_OPTION} && PROCESS_P_OPTION
	${B_OPTION} && PROCESS_B_OPTION
	${U_OPTION} && PROCESS_U_OPTION
	${K_OPTION} && PROCESS_K_OPTION
	if ${UPDATE_KERNEL}; then
		LINUXIUM_ISO="linuxium-${BOOTLOADER}${MAINLINE_BRANCH}-$(basename ${ISO})"
	else
		LINUXIUM_ISO="linuxium-${BOOTLOADER}$(basename ${ISO})"
	fi
	if ${ADD_PERSISTENCE}; then
		LINUXIUM_ISO="${LINUXIUM_ISO/linuxium/linuxium-persistence}"
		LINUXIUM_ISO="${LINUXIUM_ISO/rEFInd-/}"
	fi
	if [ -z "${WORK_DIRECTORY}" -a -f ${LINUXIUM_ISO} ]; then
		DISPLAY_MESSAGE "${0}: Respun ISO '${LINUXIUM_ISO}' already exists."
		CLEAN_EXIT
	elif [ -f ${WORK_DIRECTORY}/${LINUXIUM_ISO} ]; then
		DISPLAY_MESSAGE "${0}: Respun ISO '${WORK_DIRECTORY}/${LINUXIUM_ISO}' already exists."
		CLEAN_EXIT
	fi
}

function CHECK_FOR_EXCLUSIVITY {
	if [ -f .isorespin.sh.lock ]; then
		echo "${0}: Lock file exists ... wait for running instance of isorespin.sh to complete or remove '.isorespin.sh.lock' and restart."
		exit -1
	else
		sudo touch .isorespin.sh.lock
		export LC_ALL=C
		CWD=$(pwd)
		WIP=${CWD}/isorespin
		ISORESPIN_LOGFILE="${CWD}/isorespin.log"
		GUI=false
		if [ -f ${ISORESPIN_LOGFILE} -o -d ${ISORESPIN_LOGFILE} ]; then
			echo "${0}: Logfile '$(basename ${ISORESPIN_LOGFILE})' already exists."
			DIRTY_EXIT
		fi
		if ! $(touch ${ISORESPIN_LOGFILE} > /dev/null 2>&1); then
			echo "${0}: Cannot create logfile '$(basename ${ISORESPIN_LOGFILE})'."
			DIRTY_EXIT
		fi
	fi
}

function CHECK_PACKAGE_DEPENDENCIES {
	[ ! $(sudo bash -c "command -v bc") ] && echo "${0}: Please ensure package 'bc' or equivalent for your distro is installed." && exit
	# backward compatibility
	# [ ! $(sudo bash -c "command -v curl") ] && echo "${0}: Please ensure package 'curl' or equivalent for your distro is installed." && exit
	[ ! $(sudo bash -c "command -v losetup") ] && echo "${0}: Please ensure package 'klibc-utils' or equivalent for your distro is installed." && exit
	[ ! $(sudo bash -c "command -v ip") ] && echo "${0}: Please ensure package 'iproute2' or equivalent for your distro is installed." && exit
	[ ! $(sudo bash -c "command -v isoinfo") ] && echo "${0}: Please ensure package 'genisoimage' or equivalent for your distro is installed." && exit
	[ ! $(sudo bash -c "command -v mkdosfs") ] && echo "${0}: Please ensure package 'dosfstools' or equivalent for your distro is installed." && exit
	[ ! $(sudo bash -c "command -v mksquashfs") ] && echo "${0}: Please ensure package 'squashfs-tools' or equivalent for your distro is installed." && exit
	[ ! $(sudo bash -c "command -v rsync") ] && echo "${0}: Please ensure package 'rsync' or equivalent for your distro is installed." && exit
	[ ! $(sudo bash -c "command -v unsquashfs") ] && echo "${0}: Please ensure package 'squashfs-tools' or equivalent for your distro is installed." && exit
	[ ! $(sudo bash -c "command -v unzip") ] && echo "${0}: Please ensure package 'unzip' or equivalent for your distro is installed." && exit
	[ ! $(sudo bash -c "command -v wget") ] && echo "${0}: Please ensure package 'wget' or equivalent for your distro is installed." && exit
	[ ! $(sudo bash -c "command -v xargs") ] && echo "${0}: Please ensure package 'findutils' or equivalent for your distro is installed." && exit
	[ ! $(sudo bash -c "command -v xorriso") ] && echo "${0}: Please ensure package 'xorriso' or equivalent for your distro is installed." && exit
}

function CHECK_FOR_FREE_SPACE {
	FREE_SPACE=$(stat -f --format="%a*%S/1024/1024/1024" ${WIP} | bc -l)
	ROUNDED_FREE_SPACE=$(printf "%.0f\n" ${FREE_SPACE})
	DISPLAY_FREE_SPACE=$(printf "%.1f\n" ${FREE_SPACE})
	if [ "${ROUNDED_FREE_SPACE}" -lt 10 ]; then
		if [ -z "${WORK_DIRECTORY}" ]; then
			DISPLAY_MESSAGE "${0}: Insufficient disk space ... there is only ${DISPLAY_FREE_SPACE}GB free and not the required minimum of 10GB."
		else
			DISPLAY_MESSAGE "${0}: Insufficient disk space ... there is only ${DISPLAY_FREE_SPACE}GB free in '${WORK_DIRECTORY}' and not the required minimum of 10GB."
		fi
		CLEAN_EXIT
	fi
}

function CHECK_INTERNET_ACCESS {
	DEFAULT_GATEWAY=`ip r | grep default | cut -d ' ' -f 3`
	if ( ! ping -q -w 1 -c 1 "${DEFAULT_GATEWAY}" > /dev/null 2>&1 ); then
		DISPLAY_MESSAGE "${0}: Access to the internet is required for downloading files."
		CLEAN_EXIT
	fi
}

function CHECK_FOR_KERNEL_DUPLICATION {
	if ${U_OPTION}; then
		if ${ROLLING_KERNEL_OPTION}; then
			DISPLAY_MESSAGE "${0}: Rolling kernel cannot be used with '-u' or '--update' option."
		else
			DISPLAY_MESSAGE "${0}: Kernel update to latest version already specified using '-u' or '--update' option."
		fi
		DIRTY_EXIT
	elif ${K_OPTION}; then
		DISPLAY_MESSAGE "${0}: Kernel already specified using '-k' or '--kernel' option."
		DIRTY_EXIT
	elif ${ROLLING_KERNEL_OPTION}; then
		DISPLAY_MESSAGE "${0}: Kernel already specified using '${ROLLING}' option."
		DIRTY_EXIT
	fi
}

function GET_MAINLINE_INDEX {
	if [ ! -f ${WIP}/mainline_index.html ]; then
		sudo wget --timeout=10 "${MAINLINE_URL}/?C=N;O=D" -O ${WIP}/mainline_index.html > /dev/null 2>&1
		if [ ! -f ${WIP}/mainline_index.html ]; then
			DISPLAY_MESSAGE "${0}: Cannot get list of available mainline kernels ... check your internet connection and try again."
			CLEAN_EXIT
		fi
	fi
}

function OPTION_HELP {
	if [ "${NUMBER_OF_ARGUMENTS}" != 1 ]; then
		DISPLAY_MESSAGE "${0}: Invalid invocation."
	fi
	USAGE
	rm -f ${ISORESPIN_LOGFILE}
	DIRTY_EXIT
}

function OPTION_VERSION {
	if [ "${NUMBER_OF_ARGUMENTS}" != 1 ]; then
		DISPLAY_MESSAGE "${0}: Invalid invocation. "
		USAGE
		rm -f ${ISORESPIN_LOGFILE}
		DIRTY_EXIT
	else
		DISPLAY_MESSAGE "${0}: Version: ${VERSION}"
		rm -f ${ISORESPIN_LOGFILE}
		DIRTY_EXIT
	fi
}

function OPTION_UPGRADE {
	CHECK_INTERNET_ACCESS
	UPGRADE=true
}

function OPTION_UPDATE {
	CHECK_FOR_KERNEL_DUPLICATION
	U_OPTION=true
}

function PROCESS_U_OPTION {
	CHECK_INTERNET_ACCESS
	GET_MAINLINE_INDEX
	MAINLINE_BRANCH=$(sed -n '/alt=\"\[DIR\]\"/s/^.*href="\([^/]*\).*/\1/p' ${WIP}/mainline_index.html | head -1)
	sudo rm -f ${WIP}/mainline_index.html
	UPDATE_KERNEL=true
}

function OPTION_KERNEL {
	CHECK_FOR_KERNEL_DUPLICATION
	if [ -z "${MAINLINE_BRANCH}" ]; then
		DISPLAY_MESSAGE "${0}: A kernel must be specified when using '-k' or '--kernel' option."
		DIRTY_EXIT
	fi
	K_OPTION=true
}

function PROCESS_K_OPTION {
	CHECK_INTERNET_ACCESS
	GET_MAINLINE_INDEX
	if ! $(echo $(sed -n '/alt=\"\[DIR\]\"/s/^.*href="\([^/]*\).*/\1/p' ${WIP}/mainline_index.html) | egrep -q "^${MAINLINE_BRANCH} | ${MAINLINE_BRANCH} | ${MAINLINE_BRANCH}$"); then
		DISPLAY_MESSAGE "${0}: Kernel '${MAINLINE_BRANCH}' not found in '${MAINLINE_URL}'."
		CLEAN_EXIT
	else
		sudo rm -f ${WIP}/mainline_index.html
	fi
	if ${K_OPTION}; then
		if [ "${MAINLINE_BRANCH:0:1}" == 'd' -o "${MAINLINE_BRANCH:0:1}" == 'l' ]; then
			CURRENT="/current"
		elif [ "${MAINLINE_BRANCH:0:1}" == 'v' ]; then
			CURRENT=""
		elif [ "${MAINLINE_BRANCH}" == "native" ]; then
			DISPLAY_MESSAGE "${0}: Kernel '${MAINLINE_BRANCH}' is not supported."
			CLEAN_EXIT
		fi
	fi
	UPDATE_KERNEL=true
}

function PROCESS_KEY_OPTION {
	CHECK_INTERNET_ACCESS
	ADD_KEY=true
}

function PROCESS_R_OPTION {
	CHECK_INTERNET_ACCESS
	ADD_REPOSITORY=true
}

function PROCESS_E_OPTION {
	CHECK_INTERNET_ACCESS
	PURGE_PACKAGE=true
}

function PROCESS_P_OPTION {
	CHECK_INTERNET_ACCESS
	ADD_PACKAGE=true
}

function PROCESS_L_OPTION {
	CHECK_INTERNET_ACCESS
	for LOCAL_PACKAGE_ARRAY in $(seq 0 $((${#LOCAL_PACKAGES[@]}-1)))
	do
		FULLNAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]=""
		BASENAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]=""
		for PACKAGE in ${LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]}
		do
			if [ ! -f ${PACKAGE} ]; then
				DISPLAY_MESSAGE "${0}: Local package '${PACKAGE}' not found."
				CLEAN_EXIT
			fi
			if [ "${PACKAGE##*.}" != "deb" ] && [ "$(file ${PACKAGE} | sed 's/.*: //' | sed 's/package.*/package/')" != "Debian binary package" ]; then
				DISPLAY_MESSAGE "${0}: Local package '${PACKAGE}' is not a Debian binary package."
				CLEAN_EXIT
			fi
			FULLNAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]+=" $(readlink -f ${PACKAGE})"
			BASENAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]+=" $(basename $(readlink -f ${PACKAGE}))"
		done
		FULLNAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]="${FULLNAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]:1}"
		BASENAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]="${BASENAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]:1}"
		((LOCAL_PACKAGE_ARRAY++))
	done
	ADD_LOCAL_PACKAGE=true
}

function PROCESS_D_OPTION {
	CHECK_INTERNET_ACCESS
	ADD_DOWNLOAD=true
}

function PROCESS_F_OPTION {
	for FILE_ARRAY in $(seq 0 $((${#FILES[@]}-1)))
	do
		FULLNAME_ADDITIONAL_FILES[${FILE_ARRAY}]=""
		for ADDITIONAL_FILE in ${FILES[${FILE_ARRAY}]}
		do
			if [ ! -e ${ADDITIONAL_FILE} ]; then
				DISPLAY_MESSAGE "${0}: File '${ADDITIONAL_FILE}' not found."
				CLEAN_EXIT
			elif [ ! -f ${ADDITIONAL_FILE} -a ! -d ${ADDITIONAL_FILE} ]; then
				DISPLAY_MESSAGE "${0}: File '${ADDITIONAL_FILE}' incorrect file type."
				CLEAN_EXIT
			fi
			FULLNAME_ADDITIONAL_FILES[${FILE_ARRAY}]+=" $(readlink -f ${ADDITIONAL_FILE}) "
		done
		FULLNAME_ADDITIONAL_FILES[${FILE_ARRAY}]="${FULLNAME_ADDITIONAL_FILES[${FILE_ARRAY}]:1}"
		((FILE_ARRAY++))
	done
	ADD_FILE=true
}

function OPTION_BOOT {
	if ${S_OPTION}; then
		DISPLAY_MESSAGE "${0}: Boot option should not be used together with persistence."
		DIRTY_EXIT
	fi
	if ${B_OPTION}; then
		DISPLAY_MESSAGE "${0}: Boot option already specified using '-b' or '--boot'."
		DIRTY_EXIT
	fi
	if ${TARGET_PROCESSOR_OPTION}; then
		if [ "${TARGET_PROCESSOR}" == "apollo" ]; then
			DISPLAY_MESSAGE "${0}: Boot option of 'rEFInd' already specified using '--apollo'."
			DIRTY_EXIT
		fi
	fi
	BOOT=${BOOT,,}
	if [ "${BOOT}" != "grub" -a "${BOOT}" != "refind" ]; then
		DISPLAY_MESSAGE "${0}: Either a 'GRUB' or 'rEFInd' must be specified when using '-b' or '--boot' option."
		DIRTY_EXIT
	fi
	B_OPTION=true
}

function PROCESS_B_OPTION {
	CHECK_INTERNET_ACCESS
	if [ "${BOOT}" == "refind" ]; then
		BOOTLOADER="rEFInd-"
		USE_REFIND_BOOTLOADER=true
	fi
}

function OPTION_STORAGE {
	if ${B_OPTION}; then
		DISPLAY_MESSAGE "${0}: Persistence should not be used together with boot option."
		DIRTY_EXIT
	fi
	if ${S_OPTION}; then
		DISPLAY_MESSAGE "${0}: Persistence already specified using '-s' or '--storage' option."
		DIRTY_EXIT
	fi
	if [ -z "${STORAGE}" ] || [ "${STORAGE:0:1}" == '-' ]; then
		DISPLAY_MESSAGE "${0}: A size must be specified when using '-s' or '--storage' option."
		DIRTY_EXIT
	fi
	PERSISTENCE_UNIT=${STORAGE//[[:digit:]]/}
	PERSISTENCE_SIZE=${STORAGE//${PERSISTENCE_UNIT}/}
	if [ -z "${PERSISTENCE_SIZE}" ]; then
		DISPLAY_MESSAGE "${0}: A size must be specified when using '-s' or '--storage' option."
		DIRTY_EXIT
	fi
	if ! [[ "${PERSISTENCE_SIZE}" =~ ^-?[0-9]+$ ]]; then
		DISPLAY_MESSAGE "${0}: A size must be specified when using '-s' or '--storage' option."
		DIRTY_EXIT
	fi
	SECTOR_SIZE=512
	case "${PERSISTENCE_UNIT}" in
		"MB")
			PERSISTENCE_UNIT="M"
			PERSISTENCE_SECTOR_SIZE=$((${PERSISTENCE_SIZE}*1024*1024/${SECTOR_SIZE}))
			;;
		"GB")
			PERSISTENCE_UNIT="G"
			PERSISTENCE_SECTOR_SIZE=$((${PERSISTENCE_SIZE}*1024*1024*1024/${SECTOR_SIZE}))
			;;
		*)
			DISPLAY_MESSAGE "${0}: Unit for persistence size not 'MB' or 'GB'."
			DIRTY_EXIT
			;;
	esac
	if [ "${PERSISTENCE_UNIT}" == "M" -a "${PERSISTENCE_SIZE}" -le 99 ]; then
		DISPLAY_MESSAGE "${0}: A minimum size of 100MB is required for persistence."
		DIRTY_EXIT
	fi
	S_OPTION=true
	BOOT="refind"
}

function PROCESS_S_OPTION {
	CHECK_INTERNET_ACCESS
	PERSISTENCE="persistent"
	BOOTLOADER="rEFInd-"
	USE_REFIND_BOOTLOADER=true
	ADD_PERSISTENCE=true;
}

function PROCESS_C_OPTION {
	CHECK_INTERNET_ACCESS
	ADD_COMMAND=true
}

function PROCESS_O_OPTION {
	EXTRACT_FILE=true
}

function OPTION_ROLLING_LIST {
	if [ "${NUMBER_OF_ARGUMENTS}" != 1 ]; then
		DISPLAY_MESSAGE "${0}: Invalid invocation. "
		USAGE
		rm -f ${ISORESPIN_LOGFILE}
		DIRTY_EXIT
	fi
	CHECK_FOR_KERNEL_DUPLICATION
	CHECK_INTERNET_ACCESS
	sudo rm -rf ${WIP}
	sudo mkdir ${WIP} > /dev/null 2>&1
	sudo wget --timeout=10 https://launchpad.net/ubuntu/+series -O ${WIP}/Series.html > /dev/null 2>&1
	if [ ! -f ${WIP}/Series.html ]; then
		DISPLAY_MESSAGE "${0}: Cannot fetch active series list ... check your internet connection and try again."
		CLEAN_EXIT
	fi
	SERIES_ARRAY=0
	for SERIES in $(grep '<strong><a href="/ubuntu/' ${WIP}/Series.html | sed 's?.*/ubuntu/??' | sed 's/".*(/_/' | sed 's/).*//')
	do
		RELEASE_SERIES[SERIES_ARRAY]=${SERIES%_*}
		RELEASE_NUMBER[SERIES_ARRAY]=${SERIES#*_}
		((SERIES_ARRAY++))
	done
	sudo rm -f ${WIP}/Series.html
	sudo wget --timeout=10 "https://packages.ubuntu.com/" -O ${WIP}/Releases.html > /dev/null 2>&1
	if [ ! -f ${WIP}/Releases.html ]; then
		DISPLAY_MESSAGE "${0}: Cannot fetch distro information ... check your internet connection and try again."
		CLEAN_EXIT
	fi
	RELEASES=$(grep '<li><a href=' ${WIP}/Releases.html | grep -v '-' | sed 's/.*">//' | sed 's/<.*//')
	sudo rm -f ${WIP}/Releases.html
	for RELEASE in ${RELEASES}
	do
		# RELEASE
		for SERIES_ARRAY in $(seq 0 $((${#RELEASE_SERIES[@]}-1)))
		do
			if [ "${RELEASE_SERIES[${SERIES_ARRAY}]}" == "${RELEASE}" ]; then
				break
			fi
		done
		echo "Release '${RELEASE}':"
		sudo wget --timeout=10 "https://packages.ubuntu.com/${RELEASE}/kernel/" -O ${WIP}/Kernel_Packages.html > /dev/null 2>&1
		if [ ! -f ${WIP}/Kernel_Packages.html ]; then
			DISPLAY_MESSAGE "${0}: Cannot fetch distro package list ... check your internet connection and try again."
			CLEAN_EXIT
		fi
		RELEASE_KERNEL_VERSION=$(grep -m 1 linux-generic ${WIP}/Kernel_Packages.html | sed 's/[^(]*//' | sed 's/^(//' | sed 's/ .*//' | sed 's/).*//')
		RELEASE_KERNEL_VERSION=${RELEASE_KERNEL_VERSION%\.*}
		if [ -n "${RELEASE_KERNEL_VERSION}" ]; then
			echo "rolling-linux: ${RELEASE_KERNEL_VERSION}"
		else
			echo "rolling-linux: Not available"
		fi
		RELEASE_KERNEL_VERSION=$(grep linux-generic-hwe-${RELEASE_NUMBER[${SERIES_ARRAY}]} ${WIP}/Kernel_Packages.html | sed 's/[^(]*//' | sed 's/^(//' | sed 's/).*//' | head -1)
		RELEASE_KERNEL_VERSION=${RELEASE_KERNEL_VERSION%\.*}
		if [ -n "${RELEASE_KERNEL_VERSION}" ]; then
			echo "rolling-linux-hwe: ${RELEASE_KERNEL_VERSION}"
		else
			echo "rolling-linux-hwe: Not available"
		fi
		RELEASE_KERNEL_VERSION=$(grep linux-generic-hwe-${RELEASE_NUMBER[${SERIES_ARRAY}]}-edge ${WIP}/Kernel_Packages.html | sed 's/[^(]*//' | sed 's/^(//' | sed 's/).*//' | tail -1)
		RELEASE_KERNEL_VERSION=${RELEASE_KERNEL_VERSION%\.*}
		if [ -n "${RELEASE_KERNEL_VERSION}" ]; then
			echo "rolling-linux-hwe-edge: ${RELEASE_KERNEL_VERSION}"
		else
			echo "rolling-linux-hwe-edge: Not available"
		fi
		sudo rm -f ${WIP}/Kernel_Builds.html
		# PROPOSED
		sudo wget --timeout=10 "http://archive.ubuntu.com/ubuntu/dists/${RELEASE}-proposed/main/binary-amd64/Packages.gz" -O ${WIP}/Packages.gz > /dev/null 2>&1
		if [ ! -f ${WIP}/Packages.gz ]; then
			DISPLAY_MESSAGE "${0}: Cannot fetch distro package list ... check your internet connection and try again."
			CLEAN_EXIT
		fi
		PROPOSED_KERNEL=$(zgrep linux-image ${WIP}/Packages.gz | grep -oP "^Package: \Klinux-image.*" | grep generic | grep linux-image-[0-9] | sed 's/linux-image-//' | sed 's/-generic//' | sort -t. -nk1,1 -k2,2 -k3,3 | tail -1)
		if [ -n "${PROPOSED_KERNEL}" ]; then
			echo "rolling-proposed: ${PROPOSED_KERNEL}"
			PROPOSED_KERNEL=$(zgrep -oP "^Package: \Klinux-image-generic.*" ${WIP}/Packages.gz | sed 's/linux-image-//')
		else
			echo "rolling-proposed: Not available"
		fi
		PROPOSED_KERNEL=$(zgrep -A 30 "^Package: linux-image-generic-hwe-${RELEASE_NUMBER[${SERIES_ARRAY}]}$" ${WIP}/Packages.gz | sed -n "/^Package: linux-image-generic-hwe-${RELEASE_NUMBER[${SERIES_ARRAY}]}$/,/^Filename/p" | tail -1 | sed 's/_amd64.deb//' | sed 's/.*_//')
		PROPOSED_KERNEL=${PROPOSED_KERNEL%\.*}
		if [ -n "${PROPOSED_KERNEL}" ]; then
			echo "rolling-proposed-hwe: ${PROPOSED_KERNEL}"
		else
			echo "rolling-proposed-hwe: Not available"
		fi
		PROPOSED_KERNEL=$(zgrep -A 30 "^Package: linux-image-generic-hwe-${RELEASE_NUMBER[${SERIES_ARRAY}]}-edge$" ${WIP}/Packages.gz | sed -n "/^Package: linux-image-generic-hwe-${RELEASE_NUMBER[${SERIES_ARRAY}]}-edge$/,/^Filename/p" | tail -1 | sed 's/_amd64.deb//' | sed 's/.*_//')
		PROPOSED_KERNEL=${PROPOSED_KERNEL%\.*}
		if [ -n "${PROPOSED_KERNEL}" ]; then
			echo "rolling-proposed-hwe-edge: ${PROPOSED_KERNEL}"
		else
			echo "rolling-proposed-hwe-edge: Not available"
		fi
		sudo rm -f ${WIP}/Packages.gz
		# TESTING
		sudo wget --timeout=10 "https://launchpad.net/~canonical-kernel-team/+archive/ubuntu/ppa/+packages?field.name_filter=&field.status_filter=published&field.series_filter="${RELEASE} -O ${WIP}/Kernel_Builds.html > /dev/null 2>&1
		if [ ! -f ${WIP}/Kernel_Builds.html ]; then
			DISPLAY_MESSAGE "${0}: Cannot fetch testing kernel builds ... check your internet connection and try again."
			CLEAN_EXIT
		fi
		for ROLLING_KERNEL in linux linux-hwe linux-hwe-edge
		do
			ROLLING_KERNEL_VERSION=$(grep -m 1 "${ROLLING_KERNEL} -" ${WIP}/Kernel_Builds.html | sed 's/ //g' | sed 's/[^0-9]*//' | sed 's/\([0-9]*\)\.\([0-9]*\)\.\([0-9]*\)-\([0-9]*\)\.\([0-9]*\).*/\1.\2.\3-\4/')
			if [ -n "${ROLLING_KERNEL_VERSION}" ]; then
				echo "rolling-testing${ROLLING_KERNEL#linux}: ${ROLLING_KERNEL_VERSION}"
			else
				echo "rolling-testing${ROLLING_KERNEL#linux}: Not available"
			fi
		done
		sudo rm -f ${WIP}/Kernel_Builds.html
		# UNSTABLE
		sudo wget --timeout=10 "https://launchpad.net/~canonical-kernel-team/+archive/ubuntu/unstable/+packages?field.name_filter=&field.status_filter=published&field.series_filter="${RELEASE} -O ${WIP}/Kernel_Builds.html > /dev/null 2>&1
		if [ ! -f ${WIP}/Kernel_Builds.html ]; then
			DISPLAY_MESSAGE "${0}: Cannot fetch unstable kernel builds ... check your internet connection and try again."
			CLEAN_EXIT
		fi
		for ROLLING_KERNEL in linux linux-hwe linux-hwe-edge
		do
			ROLLING_KERNEL_VERSION=$(grep -m 1 "${ROLLING_KERNEL} -" ${WIP}/Kernel_Builds.html | sed 's/ //g' | sed 's/[^0-9]*//' | sed 's/\([0-9]*\)\.\([0-9]*\)\.\([0-9]*\)-\([0-9]*\)\.\([0-9]*\).*/\1.\2.\3-\4/')
			if [ -n "${ROLLING_KERNEL_VERSION}" ]; then
				echo "rolling-unstable${ROLLING_KERNEL#linux}: ${ROLLING_KERNEL_VERSION}"
			else
				echo "rolling-unstable${ROLLING_KERNEL#linux}: Not available"
			fi
		done
		sudo rm -f ${WIP}/Kernel_Builds.html
	done
	rm -f ${ISORESPIN_LOGFILE}
	CLEAN_EXIT
}

function OPTION_ROLLING_KERNEL {
	CHECK_FOR_KERNEL_DUPLICATION
	ROLLING_KERNEL_OPTION=true
}

function PROCESS_ROLLING_KERNEL_OPTION {
	CHECK_INTERNET_ACCESS
	ROLLING_KERNEL=${ROLLING#rolling-}
	DISTRO_RELEASE=$(basename $(find ${WIP}/iso-directory-structure/dists -maxdepth 1 -type d | sed 1d))
	DISTRO_RELEASE_NUMBER=$(grep '^Version' ${WIP}/iso-directory-structure/dists/$DISTRO_RELEASE/Release | sed 's/.* //')
	case "${ROLLING_KERNEL}" in
		"release")
			sudo wget --timeout=10 "https://packages.ubuntu.com/${DISTRO_RELEASE}/kernel/" -O ${WIP}/Kernel_Packages.html > /dev/null 2>&1
			if [ ! -f ${WIP}/Kernel_Packages.html ]; then
				DISPLAY_MESSAGE "${0}: Cannot fetch distro package list ... check your internet connection and try again."
				MESSY_EXIT
			fi
			ROLLING_KERNEL_VERSION=$(grep -m 1 linux-generic ${WIP}/Kernel_Packages.html | sed 's/[^(]*//' | sed 's/^(//' | sed 's/ .*//' | sed 's/).*//')
			ROLLING_KERNEL_VERSION=${ROLLING_KERNEL_VERSION%\.*}
			sudo rm -f ${WIP}/Kernel_Packages.html
			if [ -n "${ROLLING_KERNEL_VERSION}" ]; then
				ROLLING_PACKAGES=""
				for ROLLING_PACKAGE in linux-headers-${ROLLING_KERNEL_VERSION} linux-headers-${ROLLING_KERNEL_VERSION}-generic linux-image-${ROLLING_KERNEL_VERSION}-generic linux-image-extra-${ROLLING_KERNEL_VERSION}-generic
				do
					if ! [ -f ${WIP}/${DISTRO_RELEASE}-Packages.gz ]; then
						sudo wget --timeout=10 "http://archive.ubuntu.com/ubuntu/dists/${DISTRO_RELEASE}/main/binary-amd64/Packages.gz" -O ${WIP}/${DISTRO_RELEASE}-Packages.gz > /dev/null 2>&1
						if [ ! -f ${WIP}/${DISTRO_RELEASE}-Packages.gz ]; then
							DISPLAY_MESSAGE "${0}: Cannot fetch distro package list ... check your internet connection and try again."
							MESSY_EXIT
						fi
					fi
					if [ -n "$(zgrep "^Package: ${ROLLING_PACKAGE}$" ${WIP}/${DISTRO_RELEASE}-Packages.gz)" ]; then
						PACKAGES[${PACKAGE_ARRAY}]+=" ${ROLLING_PACKAGE}"
					else
						if ! [ -f ${WIP}/${DISTRO_RELEASE}-updates-Packages.gz ]; then
							sudo wget --timeout=10 "http://archive.ubuntu.com/ubuntu/dists/${DISTRO_RELEASE}-updates/main/binary-amd64/Packages.gz" -O ${WIP}/${DISTRO_RELEASE}-updates-Packages.gz > /dev/null 2>&1
							if [ ! -f ${WIP}/${DISTRO_RELEASE}-updates-Packages.gz ]; then
								DISPLAY_MESSAGE "${0}: Cannot fetch distro package list ... check your internet connection and try again."
								MESSY_EXIT
							fi
						fi
						if [ -n "$(zgrep "^Package: ${ROLLING_PACKAGE}$" ${WIP}/${DISTRO_RELEASE}-updates-Packages.gz)" ]; then
							PACKAGES[${PACKAGE_ARRAY}]+=" ${ROLLING_PACKAGE}"
						else
							if ! [ -f ${WIP}/${DISTRO_RELEASE}-security-Packages.gz ]; then
								sudo wget --timeout=10 "http://archive.ubuntu.com/ubuntu/dists/${DISTRO_RELEASE}-security/main/binary-amd64/Packages.gz" -O ${WIP}/${DISTRO_RELEASE}-security-Packages.gz > /dev/null 2>&1
								if [ ! -f ${WIP}/${DISTRO_RELEASE}-security-Packages.gz ]; then
									DISPLAY_MESSAGE "${0}: Cannot fetch distro package list ... check your internet connection and try again."
									MESSY_EXIT
								fi
							fi
							if [ -n "$(zgrep "^Package: ${ROLLING_PACKAGE}$" ${WIP}/${DISTRO_RELEASE}-security-Packages.gz)" ]; then
								PACKAGES[${PACKAGE_ARRAY}]+=" ${ROLLING_PACKAGE}"
							fi
						fi
					fi
				done
				sudo rm -f ${WIP}/${DISTRO_RELEASE}-Packages.gz ${WIP}/${DISTRO_RELEASE}-updates-Packages.gz ${WIP}/${DISTRO_RELEASE}-security-Packages.gz
				PACKAGES[${PACKAGE_ARRAY}]=${PACKAGES[${PACKAGE_ARRAY}]:1}
				((PACKAGE_ARRAY++))
				ADD_PACKAGE=true
			else
				DISPLAY_MESSAGE "${0}: Rolling '${ROLLING_KERNEL}' kernel is not available for ISO distribution release of '${DISTRO_RELEASE}'."
				MESSY_EXIT
			fi
			;;
		"release-hwe")
			sudo wget --timeout=10 "https://packages.ubuntu.com/${DISTRO_RELEASE}/kernel/" -O ${WIP}/Kernel_Packages.html > /dev/null 2>&1
			if [ ! -f ${WIP}/Kernel_Packages.html ]; then
				DISPLAY_MESSAGE "${0}: Cannot fetch distro package list ... check your internet connection and try again."
				MESSY_EXIT
			fi
			RELEASE_KERNEL_VERSION=$(grep linux-generic-hwe-${DISTRO_RELEASE_NUMBER} ${WIP}/Kernel_Packages.html | sed 's/[^(]*//' | sed 's/^(//' | sed 's/).*//' | head -1)
			RELEASE_KERNEL_VERSION=${RELEASE_KERNEL_VERSION%\.*}
			sudo rm -f ${WIP}/Kernel_Packages.html
			if [ -n "${ROLLING_KERNEL_VERSION}" ]; then
				ROLLING_PACKAGES=""
				for ROLLING_PACKAGE in linux-headers-${ROLLING_KERNEL_VERSION} linux-headers-${ROLLING_KERNEL_VERSION}-generic linux-image-${ROLLING_KERNEL_VERSION}-generic linux-image-extra-${ROLLING_KERNEL_VERSION}-generic
				do
					if ! [ -f ${WIP}/${DISTRO_RELEASE}-Packages.gz ]; then
						sudo wget --timeout=10 "http://archive.ubuntu.com/ubuntu/dists/${DISTRO_RELEASE}/main/binary-amd64/Packages.gz" -O ${WIP}/${DISTRO_RELEASE}-Packages.gz > /dev/null 2>&1
						if [ ! -f ${WIP}/${DISTRO_RELEASE}-Packages.gz ]; then
							DISPLAY_MESSAGE "${0}: Cannot fetch distro package list ... check your internet connection and try again."
							MESSY_EXIT
						fi
					fi
					if [ -n "$(zgrep "^Package: ${ROLLING_PACKAGE}$" ${WIP}/${DISTRO_RELEASE}-Packages.gz)" ]; then
						PACKAGES[${PACKAGE_ARRAY}]+=" ${ROLLING_PACKAGE}"
					else
						if ! [ -f ${WIP}/${DISTRO_RELEASE}-updates-Packages.gz ]; then
							sudo wget --timeout=10 "http://archive.ubuntu.com/ubuntu/dists/${DISTRO_RELEASE}-updates/main/binary-amd64/Packages.gz" -O ${WIP}/${DISTRO_RELEASE}-updates-Packages.gz > /dev/null 2>&1
							if [ ! -f ${WIP}/${DISTRO_RELEASE}-updates-Packages.gz ]; then
								DISPLAY_MESSAGE "${0}: Cannot fetch distro package list ... check your internet connection and try again."
								MESSY_EXIT
							fi
						fi
						if [ -n "$(zgrep "^Package: ${ROLLING_PACKAGE}$" ${WIP}/${DISTRO_RELEASE}-updates-Packages.gz)" ]; then
							PACKAGES[${PACKAGE_ARRAY}]+=" ${ROLLING_PACKAGE}"
						else
							if ! [ -f ${WIP}/${DISTRO_RELEASE}-security-Packages.gz ]; then
								sudo wget --timeout=10 "http://archive.ubuntu.com/ubuntu/dists/${DISTRO_RELEASE}-security/main/binary-amd64/Packages.gz" -O ${WIP}/${DISTRO_RELEASE}-security-Packages.gz > /dev/null 2>&1
								if [ ! -f ${WIP}/${DISTRO_RELEASE}-security-Packages.gz ]; then
									DISPLAY_MESSAGE "${0}: Cannot fetch distro package list ... check your internet connection and try again."
									MESSY_EXIT
								fi
							fi
							if [ -n "$(zgrep "^Package: ${ROLLING_PACKAGE}$" ${WIP}/${DISTRO_RELEASE}-security-Packages.gz)" ]; then
								PACKAGES[${PACKAGE_ARRAY}]+=" ${ROLLING_PACKAGE}"
							fi
						fi
					fi
				done
				sudo rm -f ${WIP}/${DISTRO_RELEASE}-Packages.gz ${WIP}/${DISTRO_RELEASE}-updates-Packages.gz ${WIP}/${DISTRO_RELEASE}-security-Packages.gz
				PACKAGES[${PACKAGE_ARRAY}]=${PACKAGES[${PACKAGE_ARRAY}]:1}
				((PACKAGE_ARRAY++))
				ADD_PACKAGE=true
			else
				DISPLAY_MESSAGE "${0}: Rolling '${ROLLING_KERNEL}' kernel is not available for ISO distribution release of '${DISTRO_RELEASE}'."
				MESSY_EXIT
			fi
			;;
		"release-hwe-edge")
			sudo wget --timeout=10 "https://packages.ubuntu.com/${DISTRO_RELEASE}/kernel/" -O ${WIP}/Kernel_Packages.html > /dev/null 2>&1
			if [ ! -f ${WIP}/Kernel_Packages.html ]; then
				DISPLAY_MESSAGE "${0}: Cannot fetch distro package list ... check your internet connection and try again."
				MESSY_EXIT
			fi
			RELEASE_KERNEL_VERSION=$(grep linux-generic-hwe-${DISTRO_RELEASE_NUMBER}-edge ${WIP}/Kernel_Packages.html | sed 's/[^(]*//' | sed 's/^(//' | sed 's/).*//' | tail -1)
			RELEASE_KERNEL_VERSION=${RELEASE_KERNEL_VERSION%\.*}
			sudo rm -f ${WIP}/Kernel_Packages.html
			if [ -n "${ROLLING_KERNEL_VERSION}" ]; then
				ROLLING_PACKAGES=""
				for ROLLING_PACKAGE in linux-headers-${ROLLING_KERNEL_VERSION} linux-headers-${ROLLING_KERNEL_VERSION}-generic linux-image-${ROLLING_KERNEL_VERSION}-generic linux-image-extra-${ROLLING_KERNEL_VERSION}-generic
				do
					if ! [ -f ${WIP}/${DISTRO_RELEASE}-Packages.gz ]; then
						sudo wget --timeout=10 "http://archive.ubuntu.com/ubuntu/dists/${DISTRO_RELEASE}/main/binary-amd64/Packages.gz" -O ${WIP}/${DISTRO_RELEASE}-Packages.gz > /dev/null 2>&1
						if [ ! -f ${WIP}/${DISTRO_RELEASE}-Packages.gz ]; then
							DISPLAY_MESSAGE "${0}: Cannot fetch distro package list ... check your internet connection and try again."
							MESSY_EXIT
						fi
					fi
					if [ -n "$(zgrep "^Package: ${ROLLING_PACKAGE}$" ${WIP}/${DISTRO_RELEASE}-Packages.gz)" ]; then
						PACKAGES[${PACKAGE_ARRAY}]+=" ${ROLLING_PACKAGE}"
					else
						if ! [ -f ${WIP}/${DISTRO_RELEASE}-updates-Packages.gz ]; then
							sudo wget --timeout=10 "http://archive.ubuntu.com/ubuntu/dists/${DISTRO_RELEASE}-updates/main/binary-amd64/Packages.gz" -O ${WIP}/${DISTRO_RELEASE}-updates-Packages.gz > /dev/null 2>&1
							if [ ! -f ${WIP}/${DISTRO_RELEASE}-updates-Packages.gz ]; then
								DISPLAY_MESSAGE "${0}: Cannot fetch distro package list ... check your internet connection and try again."
								MESSY_EXIT
							fi
						fi
						if [ -n "$(zgrep "^Package: ${ROLLING_PACKAGE}$" ${WIP}/${DISTRO_RELEASE}-updates-Packages.gz)" ]; then
							PACKAGES[${PACKAGE_ARRAY}]+=" ${ROLLING_PACKAGE}"
						else
							if ! [ -f ${WIP}/${DISTRO_RELEASE}-security-Packages.gz ]; then
								sudo wget --timeout=10 "http://archive.ubuntu.com/ubuntu/dists/${DISTRO_RELEASE}-security/main/binary-amd64/Packages.gz" -O ${WIP}/${DISTRO_RELEASE}-security-Packages.gz > /dev/null 2>&1
								if [ ! -f ${WIP}/${DISTRO_RELEASE}-security-Packages.gz ]; then
									DISPLAY_MESSAGE "${0}: Cannot fetch distro package list ... check your internet connection and try again."
									MESSY_EXIT
								fi
							fi
							if [ -n "$(zgrep "^Package: ${ROLLING_PACKAGE}$" ${WIP}/${DISTRO_RELEASE}-security-Packages.gz)" ]; then
								PACKAGES[${PACKAGE_ARRAY}]+=" ${ROLLING_PACKAGE}"
							fi
						fi
					fi
				done
				sudo rm -f ${WIP}/${DISTRO_RELEASE}-Packages.gz ${WIP}/${DISTRO_RELEASE}-updates-Packages.gz ${WIP}/${DISTRO_RELEASE}-security-Packages.gz
				PACKAGES[${PACKAGE_ARRAY}]=${PACKAGES[${PACKAGE_ARRAY}]:1}
				((PACKAGE_ARRAY++))
				ADD_PACKAGE=true
			else
				DISPLAY_MESSAGE "${0}: Rolling '${ROLLING_KERNEL}' kernel is not available for ISO distribution release of '${DISTRO_RELEASE}'."
				MESSY_EXIT
			fi
			;;
		"proposed")
			sudo wget --timeout=10 "http://archive.ubuntu.com/ubuntu/dists/${DISTRO_RELEASE}-proposed/main/binary-amd64/Packages.gz" -O ${WIP}/Packages.gz > /dev/null 2>&1
			if [ ! -f ${WIP}/Packages.gz ]; then
				DISPLAY_MESSAGE "${0}: Cannot fetch distro package list ... check your internet connection and try again."
				CLEAN_EXIT
			fi
			PROPOSED_KERNEL=$(zgrep linux-image ${WIP}/Packages.gz | grep -oP "^Package: \Klinux-image.*" | grep generic | grep linux-image-[0-9] | sed 's/linux-image-//' | sed 's/-generic//' | sort -t. -nk1,1 -k2,2 -k3,3 | tail -1)
			if [ -n "${PROPOSED_KERNEL}" ]; then
				for ROLLING_PACKAGE in linux-headers-${PROPOSED_KERNEL} linux-headers-${PROPOSED_KERNEL}-generic linux-image-${PROPOSED_KERNEL}-generic linux-image-extra-${PROPOSED_KERNEL}-generic
				do
					FILEPATH=$(zgrep -A 30 "^Package: ${ROLLING_PACKAGE}$" ${WIP}/Packages.gz | sed -n "/^Package: ${ROLLING_PACKAGE}$/,/^Filename/p" | tail -1 | sed 's/Filename: //')
					if [ -n "${FILEPATH}" ]; then
						FILENAME=$(basename ${FILEPATH})
						sudo wget --timeout=10 "http://archive.ubuntu.com/ubuntu/${FILEPATH}" -O ${WIP}/${FILENAME} > /dev/null 2>&1
						if [ ! -f ${WIP}/${FILENAME} ]; then
							DISPLAY_MESSAGE "${0}: Cannot fetch kernel package '${ROLLING_PACKAGE}' ... check your internet connection and try again."
							MESSY_EXIT
						fi
						FULLNAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]+=" $(readlink -f ${WIP}/${FILENAME})"
						BASENAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]+=" $(basename $(readlink -f ${WIP}/${FILENAME}))"
					fi
				done
				sudo rm -f ${WIP}/Packages.gz
				FULLNAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]="${FULLNAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]:1}"
				BASENAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]="${BASENAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]:1}"
				((LOCAL_PACKAGE_ARRAY++))
				ADD_LOCAL_PACKAGE=true
			else
				DISPLAY_MESSAGE "${0}: Rolling '${ROLLING_KERNEL}' kernel is not available for ISO distribution release of '${DISTRO_RELEASE}'."
				MESSY_EXIT
			fi
			;;
		"proposed-hwe")
			sudo wget --timeout=10 "http://archive.ubuntu.com/ubuntu/dists/${DISTRO_RELEASE}-proposed/main/binary-amd64/Packages.gz" -O ${WIP}/Packages.gz > /dev/null 2>&1
			if [ ! -f ${WIP}/Packages.gz ]; then
				DISPLAY_MESSAGE "${0}: Cannot fetch distro package list ... check your internet connection and try again."
				CLEAN_EXIT
			fi
			PROPOSED_KERNEL=$(zgrep -A 30 "^Package: linux-image-generic-hwe-${DISTRO_RELEASE_NUMBER}$" ${WIP}/Packages.gz | sed -n "/^Package: linux-image-generic-hwe-${DISTRO_RELEASE_NUMBER}$/,/^Filename/p" | tail -1 | sed 's/_amd64.deb//' | sed 's/.*_//')
			PROPOSED_KERNEL=${PROPOSED_KERNEL%\.*}
			if [ -n "${PROPOSED_KERNEL}" ]; then
				for ROLLING_PACKAGE in linux-headers-${PROPOSED_KERNEL} linux-headers-${PROPOSED_KERNEL}-generic linux-image-${PROPOSED_KERNEL}-generic linux-image-extra-${PROPOSED_KERNEL}-generic
				do
					FILEPATH=$(zgrep -A 30 "^Package: ${ROLLING_PACKAGE}$" ${WIP}/Packages.gz | sed -n "/^Package: ${ROLLING_PACKAGE}$/,/^Filename/p" | tail -1 | sed 's/Filename: //')
					if [ -n "${FILEPATH}" ]; then
						FILENAME=$(basename ${FILEPATH})
						sudo wget --timeout=10 "http://archive.ubuntu.com/ubuntu/${FILEPATH}" -O ${WIP}/${FILENAME} > /dev/null 2>&1
						if [ ! -f ${WIP}/${FILENAME} ]; then
							DISPLAY_MESSAGE "${0}: Cannot fetch kernel package '${ROLLING_PACKAGE}' ... check your internet connection and try again."
							MESSY_EXIT
						fi
						FULLNAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]+=" $(readlink -f ${WIP}/${FILENAME})"
						BASENAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]+=" $(basename $(readlink -f ${WIP}/${FILENAME}))"
					fi
				done
				sudo rm -f ${WIP}/Packages.gz
				FULLNAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]="${FULLNAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]:1}"
				BASENAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]="${BASENAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]:1}"
				((LOCAL_PACKAGE_ARRAY++))
				ADD_LOCAL_PACKAGE=true
			else
				DISPLAY_MESSAGE "${0}: Rolling '${ROLLING_KERNEL}' kernel is not available for ISO distribution release of '${DISTRO_RELEASE}'."
				MESSY_EXIT
			fi
			;;
		"proposed-hwe-edge")
			sudo wget --timeout=10 "http://archive.ubuntu.com/ubuntu/dists/${DISTRO_RELEASE}-proposed/main/binary-amd64/Packages.gz" -O ${WIP}/Packages.gz > /dev/null 2>&1
			if [ ! -f ${WIP}/Packages.gz ]; then
				DISPLAY_MESSAGE "${0}: Cannot fetch distro package list ... check your internet connection and try again."
				CLEAN_EXIT
			fi
			PROPOSED_KERNEL=$(zgrep -A 30 "^Package: linux-image-generic-hwe-${DISTRO_RELEASE_NUMBER}-edge$" ${WIP}/Packages.gz | sed -n "/^Package: linux-image-generic-hwe-${DISTRO_RELEASE_NUMBER}-edge$/,/^Filename/p" | tail -1 | sed 's/_amd64.deb//' | sed 's/.*_//')
			PROPOSED_KERNEL=${PROPOSED_KERNEL%\.*}
			if [ -n "${PROPOSED_KERNEL}" ]; then
				for ROLLING_PACKAGE in linux-headers-${PROPOSED_KERNEL} linux-headers-${PROPOSED_KERNEL}-generic linux-image-${PROPOSED_KERNEL}-generic linux-image-extra-${PROPOSED_KERNEL}-generic
				do
					FILEPATH=$(zgrep -A 30 "^Package: ${ROLLING_PACKAGE}$" ${WIP}/Packages.gz | sed -n "/^Package: ${ROLLING_PACKAGE}$/,/^Filename/p" | tail -1 | sed 's/Filename: //')
					if [ -n "${FILEPATH}" ]; then
						FILENAME=$(basename ${FILEPATH})
						sudo wget --timeout=10 "http://archive.ubuntu.com/ubuntu/${FILEPATH}" -O ${WIP}/${FILENAME} > /dev/null 2>&1
						if [ ! -f ${WIP}/${FILENAME} ]; then
							DISPLAY_MESSAGE "${0}: Cannot fetch kernel package '${ROLLING_PACKAGE}' ... check your internet connection and try again."
							MESSY_EXIT
						fi
						FULLNAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]+=" $(readlink -f ${WIP}/${FILENAME})"
						BASENAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]+=" $(basename $(readlink -f ${WIP}/${FILENAME}))"
					fi
				done
				sudo rm -f ${WIP}/Packages.gz
				FULLNAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]="${FULLNAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]:1}"
				BASENAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]="${BASENAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]:1}"
				((LOCAL_PACKAGE_ARRAY++))
				ADD_LOCAL_PACKAGE=true
			else
				DISPLAY_MESSAGE "${0}: Rolling '${ROLLING_KERNEL}' kernel is not available for ISO distribution release of '${DISTRO_RELEASE}'."
				MESSY_EXIT
			fi
			;;
		"testing")
			sudo wget --timeout=10 "https://launchpad.net/~canonical-kernel-team/+archive/ubuntu/ppa/+packages?field.name_filter=&field.status_filter=published&field.series_filter="${DISTRO_RELEASE} -O ${WIP}/Kernel_Builds.html > /dev/null 2>&1
			if [ ! -f ${WIP}/Kernel_Builds.html ]; then
				DISPLAY_MESSAGE "${0}: Cannot fetch testing kernel builds ... check your internet connection and try again."
				CLEAN_EXIT
			fi
			ROLLING_KERNEL_VERSION=$(grep -m 1 "linux -" ${WIP}/Kernel_Builds.html | sed 's/ //g' | sed 's/[^0-9]*//' | sed 's/\([0-9]*\)\.\([0-9]*\)\.\([0-9]*\)-\([0-9]*\)\.\([0-9]*\).*/\1.\2.\3-\4/')
			sudo rm -f ${WIP}/Kernel_Builds.html
			if [ -n "${ROLLING_KERNEL_VERSION}" ]; then
				ROLLING_REPOSITORY="ppa:canonical-kernel-team/ppa"
				REMOVE_ROLLING_REPOSITORY=true
				if ${ADD_REPOSITORY}; then
					for REPOSITORY_ARRAY in $(seq 0 $((${#REPOSITORIES[@]}-1)))
					do
						if [ "${REPOSITORIES[${REPOSITORY_ARRAY}]}" == "${ROLLING_REPOSITORY}" ]; then
							REMOVE_ROLLING_REPOSITORY=false
							REPOSITORY_ARRAY=${#REPOSITORIES[@]}
							break
						fi
					done
				fi
				if ${REMOVE_ROLLING_REPOSITORY}; then
					REPOSITORY_ARRAY=${#REPOSITORIES[@]}
					REPOSITORIES[REPOSITORY_ARRAY]="${ROLLING_REPOSITORY}"
					((REPOSITORY_ARRAY++))
					ADD_REPOSITORY=true
				fi
				for ROLLING_PACKAGE in linux-headers-${ROLLING_KERNEL_VERSION} linux-headers-${ROLLING_KERNEL_VERSION}-generic linux-image-${ROLLING_KERNEL_VERSION}-generic linux-image-extra-${ROLLING_KERNEL_VERSION}-generic
				do
					PACKAGES[${PACKAGE_ARRAY}]+=" ${ROLLING_PACKAGE}"
				done
				PACKAGES[${PACKAGE_ARRAY}]=${PACKAGES[${PACKAGE_ARRAY}]:1}
				((PACKAGE_ARRAY++))
				ADD_PACKAGE=true
			else
				DISPLAY_MESSAGE "${0}: Rolling '${ROLLING_KERNEL}' kernel is not available for ISO distribution release of '${DISTRO_RELEASE}'."
				MESSY_EXIT
			fi
			;;
		"testing-hwe")
			sudo wget --timeout=10 "https://launchpad.net/~canonical-kernel-team/+archive/ubuntu/ppa/+packages?field.name_filter=&field.status_filter=published&field.series_filter="${DISTRO_RELEASE} -O ${WIP}/Kernel_Builds.html > /dev/null 2>&1
			if [ ! -f ${WIP}/Kernel_Builds.html ]; then
				DISPLAY_MESSAGE "${0}: Cannot fetch testing kernel builds ... check your internet connection and try again."
				CLEAN_EXIT
			fi
			ROLLING_KERNEL_VERSION=$(grep -m 1 "linux-hwe -" ${WIP}/Kernel_Builds.html | sed 's/ //g' | sed 's/[^0-9]*//' | sed 's/\([0-9]*\)\.\([0-9]*\)\.\([0-9]*\)-\([0-9]*\)\.\([0-9]*\).*/\1.\2.\3-\4/')
			sudo rm -f ${WIP}/Kernel_Builds.html
			if [ -n "${ROLLING_KERNEL_VERSION}" ]; then
				ROLLING_REPOSITORY="ppa:canonical-kernel-team/ppa"
				REMOVE_ROLLING_REPOSITORY=true
				if ${ADD_REPOSITORY}; then
					for REPOSITORY_ARRAY in $(seq 0 $((${#REPOSITORIES[@]}-1)))
					do
						if [ "${REPOSITORIES[${REPOSITORY_ARRAY}]}" == "${ROLLING_REPOSITORY}" ]; then
							REMOVE_ROLLING_REPOSITORY=false
							REPOSITORY_ARRAY=${#REPOSITORIES[@]}
							break
						fi
					done
				fi
				if ${REMOVE_ROLLING_REPOSITORY}; then
					REPOSITORY_ARRAY=${#REPOSITORIES[@]}
					REPOSITORIES[REPOSITORY_ARRAY]="${ROLLING_REPOSITORY}"
					((REPOSITORY_ARRAY++))
					ADD_REPOSITORY=true
				fi
				for ROLLING_PACKAGE in linux-headers-${ROLLING_KERNEL_VERSION} linux-headers-${ROLLING_KERNEL_VERSION}-generic linux-image-${ROLLING_KERNEL_VERSION}-generic linux-image-extra-${ROLLING_KERNEL_VERSION}-generic
				do
					PACKAGES[${PACKAGE_ARRAY}]+=" ${ROLLING_PACKAGE}"
				done
				PACKAGES[${PACKAGE_ARRAY}]=${PACKAGES[${PACKAGE_ARRAY}]:1}
				((PACKAGE_ARRAY++))
				ADD_PACKAGE=true
			else
				DISPLAY_MESSAGE "${0}: Rolling '${ROLLING_KERNEL}' kernel is not available for ISO distribution release of '${DISTRO_RELEASE}'."
				MESSY_EXIT
			fi
			;;
		"testing-hwe-edge")
			sudo wget --timeout=10 "https://launchpad.net/~canonical-kernel-team/+archive/ubuntu/ppa/+packages?field.name_filter=&field.status_filter=published&field.series_filter="${DISTRO_RELEASE} -O ${WIP}/Kernel_Builds.html > /dev/null 2>&1
			if [ ! -f ${WIP}/Kernel_Builds.html ]; then
				DISPLAY_MESSAGE "${0}: Cannot fetch testing kernel builds ... check your internet connection and try again."
				CLEAN_EXIT
			fi
			ROLLING_KERNEL_VERSION=$(grep -m 1 "linux-hwe-edge -" ${WIP}/Kernel_Builds.html | sed 's/ //g' | sed 's/[^0-9]*//' | sed 's/\([0-9]*\)\.\([0-9]*\)\.\([0-9]*\)-\([0-9]*\)\.\([0-9]*\).*/\1.\2.\3-\4/')
			sudo rm -f ${WIP}/Kernel_Builds.html
			if [ -n "${ROLLING_KERNEL_VERSION}" ]; then
				ROLLING_REPOSITORY="ppa:canonical-kernel-team/ppa"
				REMOVE_ROLLING_REPOSITORY=true
				if ${ADD_REPOSITORY}; then
					for REPOSITORY_ARRAY in $(seq 0 $((${#REPOSITORIES[@]}-1)))
					do
						if [ "${REPOSITORIES[${REPOSITORY_ARRAY}]}" == "${ROLLING_REPOSITORY}" ]; then
							REMOVE_ROLLING_REPOSITORY=false
							REPOSITORY_ARRAY=${#REPOSITORIES[@]}
							break
						fi
					done
				fi
				if ${REMOVE_ROLLING_REPOSITORY}; then
					REPOSITORY_ARRAY=${#REPOSITORIES[@]}
					REPOSITORIES[REPOSITORY_ARRAY]="${ROLLING_REPOSITORY}"
					((REPOSITORY_ARRAY++))
					ADD_REPOSITORY=true
				fi
				for ROLLING_PACKAGE in linux-headers-${ROLLING_KERNEL_VERSION} linux-headers-${ROLLING_KERNEL_VERSION}-generic linux-image-${ROLLING_KERNEL_VERSION}-generic linux-image-extra-${ROLLING_KERNEL_VERSION}-generic
				do
					PACKAGES[${PACKAGE_ARRAY}]+=" ${ROLLING_PACKAGE}"
				done
				PACKAGES[${PACKAGE_ARRAY}]=${PACKAGES[${PACKAGE_ARRAY}]:1}
				((PACKAGE_ARRAY++))
				ADD_PACKAGE=true
			else
				DISPLAY_MESSAGE "${0}: Rolling '${ROLLING_KERNEL}' kernel is not available for ISO distribution release of '${DISTRO_RELEASE}'."
				MESSY_EXIT
			fi
			;;
		"unstable")
			sudo wget --timeout=10 "https://launchpad.net/~canonical-kernel-team/+archive/ubuntu/unstable/+packages?field.name_filter=&field.status_filter=published&field.series_filter="${DISTRO_RELEASE} -O ${WIP}/Kernel_Builds.html > /dev/null 2>&1
			if [ ! -f ${WIP}/Kernel_Builds.html ]; then
				DISPLAY_MESSAGE "${0}: Cannot fetch testing kernel builds ... check your internet connection and try again."
				CLEAN_EXIT
			fi
			ROLLING_KERNEL_VERSION=$(grep -m 1 "linux -" ${WIP}/Kernel_Builds.html | sed 's/ //g' | sed 's/[^0-9]*//' | sed 's/\([0-9]*\)\.\([0-9]*\)\.\([0-9]*\)-\([0-9]*\)\.\([0-9]*\).*/\1.\2.\3-\4/')
			sudo rm -f ${WIP}/Kernel_Builds.html
			if [ -n "${ROLLING_KERNEL_VERSION}" ]; then
				ROLLING_REPOSITORY="ppa:canonical-kernel-team/unstable"
				REMOVE_ROLLING_REPOSITORY=true
				if ${ADD_REPOSITORY}; then
					for REPOSITORY_ARRAY in $(seq 0 $((${#REPOSITORIES[@]}-1)))
					do
						if [ "${REPOSITORIES[${REPOSITORY_ARRAY}]}" == "${ROLLING_REPOSITORY}" ]; then
							REMOVE_ROLLING_REPOSITORY=false
							REPOSITORY_ARRAY=${#REPOSITORIES[@]}
							break
						fi
					done
				fi
				if ${REMOVE_ROLLING_REPOSITORY}; then
					REPOSITORY_ARRAY=${#REPOSITORIES[@]}
					REPOSITORIES[REPOSITORY_ARRAY]="${ROLLING_REPOSITORY}"
					((REPOSITORY_ARRAY++))
					ADD_REPOSITORY=true
				fi
				for ROLLING_PACKAGE in linux-headers-${ROLLING_KERNEL_VERSION} linux-headers-${ROLLING_KERNEL_VERSION}-generic linux-image-${ROLLING_KERNEL_VERSION}-generic linux-image-extra-${ROLLING_KERNEL_VERSION}-generic
				do
					PACKAGES[${PACKAGE_ARRAY}]+=" ${ROLLING_PACKAGE}"
				done
				PACKAGES[${PACKAGE_ARRAY}]=${PACKAGES[${PACKAGE_ARRAY}]:1}
				((PACKAGE_ARRAY++))
				ADD_PACKAGE=true
			else
				DISPLAY_MESSAGE "${0}: Rolling '${ROLLING_KERNEL}' kernel is not available for ISO distribution release of '${DISTRO_RELEASE}'."
				MESSY_EXIT
			fi
			;;
		"unstable-hwe")
			sudo wget --timeout=10 "https://launchpad.net/~canonical-kernel-team/+archive/ubuntu/unstable/+packages?field.name_filter=&field.status_filter=published&field.series_filter="${DISTRO_RELEASE} -O ${WIP}/Kernel_Builds.html > /dev/null 2>&1
			if [ ! -f ${WIP}/Kernel_Builds.html ]; then
				DISPLAY_MESSAGE "${0}: Cannot fetch testing kernel builds ... check your internet connection and try again."
				CLEAN_EXIT
			fi
			ROLLING_KERNEL_VERSION=$(grep -m 1 "linux-hwe -" ${WIP}/Kernel_Builds.html | sed 's/ //g' | sed 's/[^0-9]*//' | sed 's/\([0-9]*\)\.\([0-9]*\)\.\([0-9]*\)-\([0-9]*\)\.\([0-9]*\).*/\1.\2.\3-\4/')
			sudo rm -f ${WIP}/Kernel_Builds.html
			if [ -n "${ROLLING_KERNEL_VERSION}" ]; then
				ROLLING_REPOSITORY="ppa:canonical-kernel-team/unstable"
				REMOVE_ROLLING_REPOSITORY=true
				if ${ADD_REPOSITORY}; then
					for REPOSITORY_ARRAY in $(seq 0 $((${#REPOSITORIES[@]}-1)))
					do
						if [ "${REPOSITORIES[${REPOSITORY_ARRAY}]}" == "${ROLLING_REPOSITORY}" ]; then
							REMOVE_ROLLING_REPOSITORY=false
							REPOSITORY_ARRAY=${#REPOSITORIES[@]}
							break
						fi
					done
				fi
				if ${REMOVE_ROLLING_REPOSITORY}; then
					REPOSITORY_ARRAY=${#REPOSITORIES[@]}
					REPOSITORIES[REPOSITORY_ARRAY]="${ROLLING_REPOSITORY}"
					((REPOSITORY_ARRAY++))
					ADD_REPOSITORY=true
				fi
				for ROLLING_PACKAGE in linux-headers-${ROLLING_KERNEL_VERSION} linux-headers-${ROLLING_KERNEL_VERSION}-generic linux-image-${ROLLING_KERNEL_VERSION}-generic linux-image-extra-${ROLLING_KERNEL_VERSION}-generic
				do
					PACKAGES[${PACKAGE_ARRAY}]+=" ${ROLLING_PACKAGE}"
				done
				PACKAGES[${PACKAGE_ARRAY}]=${PACKAGES[${PACKAGE_ARRAY}]:1}
				((PACKAGE_ARRAY++))
				ADD_PACKAGE=true
			else
				DISPLAY_MESSAGE "${0}: Rolling '${ROLLING_KERNEL}' kernel is not available for ISO distribution release of '${DISTRO_RELEASE}'."
				MESSY_EXIT
			fi
			;;
		"unstable-hwe-edge")
			sudo wget --timeout=10 "https://launchpad.net/~canonical-kernel-team/+archive/ubuntu/unstable/+packages?field.name_filter=&field.status_filter=published&field.series_filter="${DISTRO_RELEASE} -O ${WIP}/Kernel_Builds.html > /dev/null 2>&1
			if [ ! -f ${WIP}/Kernel_Builds.html ]; then
				DISPLAY_MESSAGE "${0}: Cannot fetch testing kernel builds ... check your internet connection and try again."
				CLEAN_EXIT
			fi
			ROLLING_KERNEL_VERSION=$(grep -m 1 "linux-hwe-edge -" ${WIP}/Kernel_Builds.html | sed 's/ //g' | sed 's/[^0-9]*//' | sed 's/\([0-9]*\)\.\([0-9]*\)\.\([0-9]*\)-\([0-9]*\)\.\([0-9]*\).*/\1.\2.\3-\4/')
			sudo rm -f ${WIP}/Kernel_Builds.html
			if [ -n "${ROLLING_KERNEL_VERSION}" ]; then
				ROLLING_REPOSITORY="ppa:canonical-kernel-team/unstable"
				REMOVE_ROLLING_REPOSITORY=true
				if ${ADD_REPOSITORY}; then
					for REPOSITORY_ARRAY in $(seq 0 $((${#REPOSITORIES[@]}-1)))
					do
						if [ "${REPOSITORIES[${REPOSITORY_ARRAY}]}" == "${ROLLING_REPOSITORY}" ]; then
							REMOVE_ROLLING_REPOSITORY=false
							REPOSITORY_ARRAY=${#REPOSITORIES[@]}
							break
						fi
					done
				fi
				if ${REMOVE_ROLLING_REPOSITORY}; then
					REPOSITORY_ARRAY=${#REPOSITORIES[@]}
					REPOSITORIES[REPOSITORY_ARRAY]="${ROLLING_REPOSITORY}"
					((REPOSITORY_ARRAY++))
					ADD_REPOSITORY=true
				fi
				for ROLLING_PACKAGE in linux-headers-${ROLLING_KERNEL_VERSION} linux-headers-${ROLLING_KERNEL_VERSION}-generic linux-image-${ROLLING_KERNEL_VERSION}-generic linux-image-extra-${ROLLING_KERNEL_VERSION}-generic
				do
					PACKAGES[${PACKAGE_ARRAY}]+=" ${ROLLING_PACKAGE}"
				done
				PACKAGES[${PACKAGE_ARRAY}]=${PACKAGES[${PACKAGE_ARRAY}]:1}
				((PACKAGE_ARRAY++))
				ADD_PACKAGE=true
			else
				DISPLAY_MESSAGE "${0}: Rolling '${ROLLING_KERNEL}' kernel is not available for ISO distribution release of '${DISTRO_RELEASE}'."
				MESSY_EXIT
			fi
			;;
	esac
}

function OPTION_TARGET_PROCESSOR {
	if [ "${TARGET_PROCESSOR}" != "atom" -a "${TARGET_PROCESSOR}" != "apollo" ]; then
		DISPLAY_MESSAGE "${0}: Only 'atom' or 'apollo' can be specified as a target processor."
		DIRTY_EXIT
	fi
	if ${B_OPTION}; then
		if [ "${BOOT}" == "grub" -a "${TARGET_PROCESSOR}" == "apollo" ]; then
			DISPLAY_MESSAGE "${0}: Boot option of 'GRUB' cannot be specified together with '--apollo'."
			DIRTY_EXIT
		fi
	fi
	TARGET_PROCESSOR_OPTION=true
}

function PROCESS_TARGET_PROCESSOR_OPTION {
	# backward compatibility
	[ ! $(sudo bash -c "command -v curl") ] && echo "${0}: Please ensure package 'curl' or equivalent for your distro is installed." && MESSY_EXIT
	CHECK_INTERNET_ACCESS
	# apollo: -b rEFInd
	if [ "${TARGET_PROCESSOR}" == "apollo" ]; then
		BOOTLOADER="rEFInd-"
		USE_REFIND_BOOTLOADER=true
	fi
	# atom: -l rtl8723bX_4.12.0_amd64.deb -f linuxium-install-UCM-files.sh -f wrapper-linuxium-install-UCM-files.sh -f linuxium-install-broadcom-drivers.sh -f wrapper-linuxium-install-broadcom-drivers.sh -c wrapper-linuxium-install-UCM-files.sh -c wrapper-linuxium-install-broadcom-drivers.sh
	if [ "${TARGET_PROCESSOR}" == "atom" ]; then
		DISTRO_RELEASE=$(basename $(find ${WIP}/iso-directory-structure/dists -maxdepth 1 -type d | sed 1d))
		DISTRO_RELEASE_NUMBER=$(grep '^Version' ${WIP}/iso-directory-structure/dists/$DISTRO_RELEASE/Release | sed 's/.* //')
		if [ "${DISTRO_RELEASE_NUMBER}" == "17.10" ]; then
			ATOM_WIFI_PACKAGE=rtl8723bt_4.12.0_amd64.deb
		else
			ATOM_WIFI_PACKAGE=rtl8723bs_4.12.0_amd64.deb
		fi
		ATOM_WIFI_PACKAGE_FOUND=false
		if ${ADD_LOCAL_PACKAGE}; then
			for LOCAL_PACKAGE_ARRAY in $(seq 0 $((${#LOCAL_PACKAGES[@]}-1)))
			do
				for PACKAGE in ${LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]}
				do
					if [ "$(basename ${PACKAGE})" == "rtl8723bs_4.12.0_amd64.deb" ]; then
						if [ "${DISTRO_RELEASE_NUMBER}" == "17.10" ]; then
							DISPLAY_MESSAGE "${0}: Local package '${PACKAGE}' is not compatible with an ISO distribution release of '${DISTRO_RELEASE}'."
							MESSY_EXIT
						fi
						ATOM_WIFI_PACKAGE_FOUND=true
						break 2
					elif [ "$(basename ${PACKAGE})" == "rtl8723bt_4.12.0_amd64.deb" ]; then
						if [ "${DISTRO_RELEASE_NUMBER}" != "17.10" ]; then
							DISPLAY_MESSAGE "${0}: Local package '${PACKAGE}' is not compatible with an ISO distribution release of '${DISTRO_RELEASE}'."
							MESSY_EXIT
						fi
						ATOM_WIFI_PACKAGE_FOUND=true
						break 2
					fi
				done
			done
		fi
		if ! ${ATOM_WIFI_PACKAGE_FOUND}; then
			case ${ATOM_WIFI_PACKAGE} in
				"rtl8723bs_4.12.0_amd64.deb")
					sudo wget --timeout=10 "https://drive.google.com/uc?export=download&id=$(sudo curl -I https://goo.gl/Sb4zG7 2> /dev/null | grep '^Location' | sed 's?.*/??' | sed 's?.$??')" -O ${ATOM_WIFI_PACKAGE} 2> /dev/null
					;;
				"rtl8723bt_4.12.0_amd64.deb")
					sudo wget --timeout=10 "https://drive.google.com/uc?export=download&id=$(sudo curl -I https://goo.gl/h8WSwX 2> /dev/null | grep '^Location' | sed 's?.*/??' | sed 's?.$??')" -O ${ATOM_WIFI_PACKAGE} 2> /dev/null
					;;
			esac
			if [ ! -f ${ATOM_WIFI_PACKAGE} ]; then
				DISPLAY_MESSAGE "${0}: Cannot fetch '${ATOM_WIFI_PACKAGE}' ... check your internet connection and try again."
				MESSY_EXIT
			fi
			LOCAL_PACKAGE_ARRAY=${#LOCAL_PACKAGES[@]}
			FULLNAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]+="$(readlink -f ${ATOM_WIFI_PACKAGE})"
			BASENAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]+="$(basename $(readlink -f ${ATOM_WIFI_PACKAGE}))"
			((LOCAL_PACKAGE_ARRAY++))
		fi
		ADD_LOCAL_PACKAGE=true
		for ATOM_ADDITIONAL_FILE in linuxium-install-UCM-files.sh wrapper-linuxium-install-UCM-files.sh linuxium-install-broadcom-drivers.sh wrapper-linuxium-install-broadcom-drivers.sh
		do
			ATOM_ADDITIONAL_FILE_FOUND=false
			if ${ADD_FILE}; then
				for FILE_ARRAY in $(seq 0 $((${#FULLNAME_ADDITIONAL_FILES[@]}-1)))
				do
					for ADDITIONAL_FILE in ${FULLNAME_ADDITIONAL_FILES[${FILE_ARRAY}]}
					do
						if [ "$(basename ${ADDITIONAL_FILE})" == "${ATOM_ADDITIONAL_FILE}" ]; then
							ATOM_ADDITIONAL_FILE_FOUND=true
							break 2
						fi
					done
				done
			fi
			if ! ${ATOM_ADDITIONAL_FILE_FOUND}; then
				case ${ATOM_ADDITIONAL_FILE} in
					"linuxium-install-UCM-files.sh")
						sudo wget --timeout=10 "https://drive.google.com/uc?export=download&id=$(sudo curl -I https://goo.gl/U7FB8I 2> /dev/null | grep '^Location' | sed 's?.*/??' | sed 's?.$??')" -O ${ATOM_ADDITIONAL_FILE} 2> /dev/null
						;;
					"wrapper-linuxium-install-UCM-files.sh")
						sudo wget --timeout=10 "https://drive.google.com/uc?export=download&id=$(sudo curl -I https://goo.gl/FgoNhO 2> /dev/null | grep '^Location' | sed 's?.*/??' | sed 's?.$??')" -O ${ATOM_ADDITIONAL_FILE} 2> /dev/null
						;;
					"linuxium-install-broadcom-drivers.sh")
						sudo wget --timeout=10 "https://drive.google.com/uc?export=download&id=$(sudo curl -I https://goo.gl/7MmtLw 2> /dev/null | grep '^Location' | sed 's?.*/??' | sed 's?.$??')" -O ${ATOM_ADDITIONAL_FILE} 2> /dev/null
						;;
					"wrapper-linuxium-install-broadcom-drivers.sh")
						sudo wget --timeout=10 "https://drive.google.com/uc?export=download&id=$(sudo curl -I https://goo.gl/A3eWYW 2> /dev/null | grep '^Location' | sed 's?.*/??' | sed 's?.$??')" -O ${ATOM_ADDITIONAL_FILE} 2> /dev/null
						;;
				esac
				if [ ! -f ${ATOM_ADDITIONAL_FILE} ]; then
					DISPLAY_MESSAGE "${0}: Cannot fetch '${ATOM_ADDITIONAL_FILE}' ... check your internet connection and try again."
					MESSY_EXIT
				fi
				sudo chmod +x ${ATOM_ADDITIONAL_FILE}
				FILE_ARRAY=${#FULLNAME_ADDITIONAL_FILES[@]}
				FULLNAME_ADDITIONAL_FILES[${FILE_ARRAY}]="$(readlink -f ${ATOM_ADDITIONAL_FILE}) "
				((FILE_ARRAY++))
			fi
		done
		ADD_FILE=true
		for ATOM_COMMAND in wrapper-linuxium-install-UCM-files.sh wrapper-linuxium-install-broadcom-drivers.sh
		do
			ATOM_COMMAND_FOUND=false
			if ${ADD_COMMAND}; then
				for COMMAND_ARRAY in $(seq 0 $((${#COMMANDS[@]}-1)))
				do
					for COMMAND in "${COMMANDS[${COMMAND_ARRAY}]}"
					do
						if [ "${COMMAND}" == "${ATOM_COMMAND}" ]; then
							ATOM_COMMAND_FOUND=true
							break 2
						fi
					done
				done
				if ! ${ATOM_COMMAND_FOUND}; then
					((COMMAND_ARRAY++))
				fi
			fi
			if ! ${ATOM_COMMAND_FOUND}; then
				COMMAND_ARRAY=${#COMMANDS[@]}
				COMMANDS[${COMMAND_ARRAY}]="${ATOM_COMMAND}"
				((COMMAND_ARRAY++))
			fi
		done
		ADD_COMMAND=true
	fi
}

function SUPPORTED { for OS in "${@:2}"; do [[ "${OS}" == "${ISO_DISTRO}" ]] && return 0; done && return 1; }

function ROLLING_POSSIBLE { for ROLLING_REQUESTED in "${@:2}"; do [[ "${ROLLING_REQUESTED}" == "${ROLLING}" ]] && return 0; done && return 1; }

function OPTION_ISO {
	if ${I_OPTION}; then
		DISPLAY_MESSAGE "${0}: ISO already specified using '-i' or '--iso' option."
		DIRTY_EXIT
	fi
	if [ -z "${ISO}" ]; then
		DISPLAY_MESSAGE "${0}: An ISO must be specified using '-i' or '--iso' option."
		USAGE
		DIRTY_EXIT
	fi
	if [ ! -f ${ISO} ]; then
		DISPLAY_MESSAGE "${0}: Cannot find ISO '${ISO}'."
		DIRTY_EXIT
	fi
	ISO=$(readlink -f ${ISO})
	ISO_VOLID=$(isoinfo -d -i ${ISO} 2> /dev/null | grep '^Volume id:') && ISO_VOLID=${ISO_VOLID##Volume id: }
	ISO_DISTRO=${ISO_VOLID%% *}
	[ "${ISO_DISTRO}" == "Linux" ] && ISO_DISTRO=${ISO_VOLID#Linux } && ISO_DISTRO=${ISO_DISTRO%% *}
	if ( ! SUPPORTED "${ISO_DISTRO}" "${SUPPORTED_OS[@]}" ); then
		DISPLAY_MESSAGE "${0}: '${ISO}' must be an Ubuntu (or Ubuntu flavour), Linux Mint, neon, elementary, BackBox or Peppermint desktop ISO."
		DIRTY_EXIT
	fi
	case "${ISO_DISTRO}" in
		"Ubuntu"|"Kubuntu"|"Lubuntu"|"Ubuntu-Budgie"|"Ubuntu-GNOME"|"Ubuntu-MATE"|"Xubuntu")
			ISO_VMLINUZ=vmlinuz.efi
			ISO_INITRD=initrd.lz
			;;
		"Mint")
			ISO_VMLINUZ=vmlinuz
			ISO_INITRD=initrd.lz
			;;
		"neon")
			ISO_VMLINUZ=vmlinuz.efi
			ISO_INITRD=initrd.lz
			;;
		"elementary")
			ISO_VMLINUZ=vmlinuz
			ISO_INITRD=initrd.lz
			;;
		"BackBox")
			ISO_VMLINUZ=vmlinuz.efi
			ISO_INITRD=initrd.gz
			;;
		"Peppermint")
			ISO_VMLINUZ=vmlinuz.efi
			ISO_INITRD=initrd.lz
			;;
		*)
			DISPLAY_MESSAGE "${0}: '${ISO_DISTRO}' unknown."
			DIRTY_EXIT
			;;
	esac
	ISO_SQUASHFS_DIRECTORY=casper
	FILESYSTEM_FILES=manifest
	PERSISTENCE_PARTITION=casper-rw
	I_OPTION=true
}

function OPTION_WORK {
	if ${W_OPTION}; then
		DISPLAY_MESSAGE "${0}: Work directory already specified using '-w' or '--work-directory' option."
		DIRTY_EXIT
	fi
	if [ ! -d ${WORK_DIRECTORY} ]; then
		DISPLAY_MESSAGE "${0}: Cannot find work directory '${WORK_DIRECTORY}' option."
		DIRTY_EXIT
	fi
	if [ -f ${WORK_DIRECTORY}/isorespin -o -d ${WORK_DIRECTORY}/isorespin ]; then
		DISPLAY_MESSAGE "${0}: Work directory '${WORK_DIRECTORY}/isorespin' already exists."
		DIRTY_EXIT
	fi
	WIP=${WORK_DIRECTORY}/isorespin
	W_OPTION=true
}

function EXTRACT_ISO {
	DISPLAY_PROGRESS "Extracting ISO ..."
	cd ${WIP}
	# mount iso
	sudo losetup -f > /dev/null 2>&1 || DISPLAY_MESSAGE "${0}: No free loop devices."
	sudo losetup -f > /dev/null 2>&1 || CLEAN_EXIT
	[ -f mnt ] && sudo rm -f mnt
	[ -d mnt ] || sudo mkdir mnt
	sudo mount -o loop ${ISO} mnt 2> /dev/null
	if ! $(sudo grep -qm1 amd64 mnt/.disk/info); then
		DISPLAY_MESSAGE "${0}: ISO '${ISO}' is not a 64-bit (amd64 or x86_64) ISO."
		sudo umount mnt
		sudo rmdir mnt
		CLEAN_EXIT
	elif [ ! -f mnt/${ISO_SQUASHFS_DIRECTORY}/filesystem.squashfs ]; then
		DISPLAY_MESSAGE "${0}: ISO '${ISO}' does not contain a 'squashfs' file system."
		sudo umount mnt
		sudo rmdir mnt
		CLEAN_EXIT
	else
		# extract iso directory structure from iso
		sudo rm -rf iso-directory-structure
		sudo rsync --exclude=/${ISO_SQUASHFS_DIRECTORY}/filesystem.squashfs -a mnt/ iso-directory-structure
		${TARGET_PROCESSOR_OPTION} && PROCESS_TARGET_PROCESSOR_OPTION
		${ROLLING_KERNEL_OPTION} && PROCESS_ROLLING_KERNEL_OPTION
		# extract iso chroot file system from iso
		sudo rm -rf squashfs-root iso-chroot
		sudo unsquashfs mnt/${ISO_SQUASHFS_DIRECTORY}/filesystem.squashfs
		sudo mv squashfs-root iso-chroot
		# unmount iso
		sudo umount mnt
		sudo rmdir mnt
	fi
	echo "ISO '${ISO}' respun ..." >> ${ISORESPIN_LOGFILE}
}

function EXTRACT_ISORESPIN_FILES {
	DISPLAY_PROGRESS "Extracting isorespin files ..."
	cd ${WIP}
	sudo rm -f isorespin.zip
	sudo sed '1,/^exit 0$/d' < ${ISORESPIN_SCRIPT} | sudo tee isorespin.zip > /dev/null
	sudo unzip isorespin.zip > /dev/null 2>&1
	sudo rm -f isorespin.zip
}

function FETCH_MAINLINE_DEBS {
	DISPLAY_PROGRESS "Fetching mainline kernel packages ..."
	cd ${WIP}
	sudo rm -f index.html
	sudo wget --timeout=10 ${MAINLINE_URL}/${MAINLINE_BRANCH}${CURRENT} -O index.html > /dev/null 2>&1
	if [ ! -f index.html ]; then
		DISPLAY_MESSAGE "${0}: Cannot fetch mainline kernel index ... check your internet connection and try again."
		CLEAN_EXIT
	fi
	FETCH_FILE=$(sed -n '/href=/{/all/{/headers/s/\(^.*href="\)\([^"]\+\)\(".*\)/\2/p;};}' index.html | tail -1)
	sudo wget --timeout=10 ${MAINLINE_URL}/${MAINLINE_BRANCH}${CURRENT}/${FETCH_FILE} > /dev/null 2>&1
	if [ ! -f "${FETCH_FILE}" ]; then
		DISPLAY_MESSAGE "${0}: Cannot fetch mainline header file ... check your internet connection and try again."
		CLEAN_EXIT
	fi
	FETCH_FILE=$(sed -n '/href=/{/generic/{/'amd64'/{/headers/s/\(^.*href="\)\([^"]\+\)\(".*\)/\2/p;};};}' index.html | tail -1)
	sudo wget --timeout=10 ${MAINLINE_URL}/${MAINLINE_BRANCH}${CURRENT}/${FETCH_FILE} > /dev/null 2>&1
	if [ ! -f "${FETCH_FILE}" ]; then
		DISPLAY_MESSAGE "${0}: Cannot fetch mainline kernel header file ... check your internet connection and try again."
		CLEAN_EXIT
	fi
	FETCH_FILE=$(sed -n '/href=/{/generic/{/'amd64'/{/image/s/\(^.*href="\)\([^"]\+\)\(".*\)/\2/p;};};}' index.html | tail -1)
	sudo wget --timeout=10 ${MAINLINE_URL}/${MAINLINE_BRANCH}${CURRENT}/${FETCH_FILE} > /dev/null 2>&1
	if [ ! -f "${FETCH_FILE}" ]; then
		DISPLAY_MESSAGE "${0}: Cannot fetch mainline kernel image file ... check your internet connection and try again."
		CLEAN_EXIT
	fi
	sudo rm -f index.html
}

function UPGRADE_DISTRO {
	DISPLAY_PROGRESS "Upgrading distro ..."
	cd ${WIP}
	if [ -f iso-chroot/etc/resolv.conf ]; then
		sudo mv iso-chroot/etc/resolv.conf iso-chroot/etc/resolv.conf.linuxium
	fi
	# dev media mnt opt proc run snap srv sys tmp
	for DIRECTORY in dev run tmp
	do
		sudo mv iso-chroot/${DIRECTORY} iso-chroot/${DIRECTORY}.linuxium
		sudo cp -a iso-chroot/${DIRECTORY}.linuxium iso-chroot/${DIRECTORY}
	done
	sudo cp /etc/resolv.conf iso-chroot/etc/
        sudo mv iso-chroot/etc/apt/sources.list iso-chroot/etc/apt/sources.list.linuxium
        sudo sed 's/\(deb.*\)$/\1 universe multiverse/' iso-chroot/etc/apt/sources.list.linuxium | sudo tee iso-chroot/etc/apt/sources.list > /dev/null
        sudo rm -f iso-chroot/usr/src/.upgrade.failed iso-chroot/usr/src/.upgrade.log
	sudo mount --bind /dev/ iso-chroot/dev
	sudo chroot iso-chroot > /dev/null 2>&1 <<+
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devpts none /dev/pts
export HOME=/root
export LC_ALL=C
trap '' SIGHUP SIGINT SIGTERM
cd /usr/src
apt-get update
apt-get -f -y upgrade > .upgrade.log 2>&1
UPGRADED=\$?
if [ \${UPGRADED} != 0 ]; then
        touch .upgrade.failed
else
	if (! grep -q '^overlay$' /etc/initramfs-tools/modules); then echo overlay >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
	if (! grep -q '^pwm-lpss$' /etc/initramfs-tools/modules); then echo pwm-lpss >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
	if (! grep -q '^pwm-lpss-platform$' /etc/initramfs-tools/modules); then echo pwm-lpss-platform >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
	if \${UPDATE_INITRAMFS};then update-initramfs -u; fi
	apt-get clean
	apt-get autoclean
	apt-get -y autoremove
fi
umount /proc || umount -lf /proc
umount /sys
umount /dev/pts
+
	sudo umount iso-chroot/dev
        if [ -f iso-chroot/usr/src/.upgrade.failed ]; then
                sudo cat iso-chroot/usr/src/.upgrade.log
                DISPLAY_MESSAGE "${0}: Distro upgrade failed."
                CLEAN_EXIT
        fi
	sudo mv iso-chroot/etc/apt/sources.list.linuxium iso-chroot/etc/apt/sources.list
	if [ -f iso-chroot/etc/resolv.conf.linuxium ]; then
		sudo mv iso-chroot/etc/resolv.conf.linuxium iso-chroot/etc/resolv.conf
	fi
	sudo rm -f iso-chroot/root/.bash_history
	sudo rm -f iso-chroot/boot/grub/grub.cfg
	sudo rm -f iso-chroot/etc/mtab
	sudo rm -f iso-chroot/var/lib/dpkg/status-old
	for DIRECTORY in dev run tmp
	do
		sudo rm -rf iso-chroot/${DIRECTORY}
		sudo mv iso-chroot/${DIRECTORY}.linuxium iso-chroot/${DIRECTORY}
	done
	echo "Distro upgraded ..." >> ${ISORESPIN_LOGFILE}
}

function INSTALL_MAINLINE_KERNEL {
	DISPLAY_PROGRESS "Installing mainline kernel packages ..."
	cd ${WIP}
	sudo cp linux-headers*.deb iso-chroot/usr/src/
	sudo cp linux-image*.deb iso-chroot/usr/src/
	if [ -f iso-chroot/etc/resolv.conf ]; then
		sudo mv iso-chroot/etc/resolv.conf iso-chroot/etc/resolv.conf.linuxium
	fi
	# dev media mnt opt proc run snap srv sys tmp
	for DIRECTORY in dev run tmp
	do
		sudo mv iso-chroot/${DIRECTORY} iso-chroot/${DIRECTORY}.linuxium
		sudo cp -a iso-chroot/${DIRECTORY}.linuxium iso-chroot/${DIRECTORY}
	done
	sudo cp /etc/resolv.conf iso-chroot/etc/
	sudo mount --bind /dev/ iso-chroot/dev
	sudo chroot iso-chroot > /dev/null 2>&1 <<+
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devpts none /dev/pts
export HOME=/root
export LC_ALL=C
trap '' SIGHUP SIGINT SIGTERM
dpkg -i /usr/src/linux*.deb 
rm -f /usr/src/linux*.deb
if (! grep -q '^overlay$' /etc/initramfs-tools/modules); then echo overlay >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
if (! grep -q '^pwm-lpss$' /etc/initramfs-tools/modules); then echo pwm-lpss >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
if (! grep -q '^pwm-lpss-platform$' /etc/initramfs-tools/modules); then echo pwm-lpss-platform >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
update-initramfs -u
apt-get clean
apt-get autoclean
apt-get -y autoremove
umount /proc || umount -lf /proc
umount /sys
umount /dev/pts
+
	sudo umount iso-chroot/dev
	if [ -f iso-chroot/etc/resolv.conf.linuxium ]; then
		sudo mv iso-chroot/etc/resolv.conf.linuxium iso-chroot/etc/resolv.conf
	fi
	sudo rm -f iso-chroot/root/.bash_history
	sudo rm -f iso-chroot/boot/grub/grub.cfg
	sudo rm -f iso-chroot/etc/mtab
	sudo rm -f iso-chroot/var/lib/dpkg/status-old
	for DIRECTORY in dev run tmp
	do
		sudo rm -rf iso-chroot/${DIRECTORY}
		sudo mv iso-chroot/${DIRECTORY}.linuxium iso-chroot/${DIRECTORY}
	done
	# update kernel in iso
	MAINLINE_INITRD=$(ls -t iso-chroot/boot/initrd* 2> /dev/null | head -1)
	MAINLINE_RELEASE=${MAINLINE_INITRD#iso-chroot/boot/initrd.img-}
	MAINLINE_VMLINUZ=$(ls -t iso-chroot/boot/vmlinuz-${MAINLINE_RELEASE} 2> /dev/null | head -1)
	if [ -z "${MAINLINE_VMLINUZ}" ]; then
		DISPLAY_MESSAGE "${0}: Cannot find mainline kernel."
		CLEAN_EXIT
	elif [ ! -f "${MAINLINE_VMLINUZ}" ]; then
		DISPLAY_MESSAGE "${0}: Mainline kernel '${MAINLINE_VMLINUZ}' missing."
		CLEAN_EXIT
	fi
	if [ -z "${MAINLINE_INITRD}" ]; then
		DISPLAY_MESSAGE "${0}: Cannot find mainline kernel initrd."
		CLEAN_EXIT
	elif [ ! -f "${MAINLINE_INITRD}" ]; then
		DISPLAY_MESSAGE "${0}: Mainline kernel initrd '${MAINLINE_INITRD}' missing."
		CLEAN_EXIT
	fi
	sudo cp ${MAINLINE_VMLINUZ} iso-directory-structure/${ISO_SQUASHFS_DIRECTORY}/${ISO_VMLINUZ}
	sudo cp ${MAINLINE_INITRD} iso-directory-structure/${ISO_SQUASHFS_DIRECTORY}/${ISO_INITRD}
	sudo rm -f linux-headers*.deb
	sudo rm -f linux-image*.deb
	echo "Kernel updated with mainline kernel version '${MAINLINE_RELEASE}' ..." >> ${ISORESPIN_LOGFILE}
}

function ADD_KEYS {
	DISPLAY_PROGRESS "Adding keys ..."
	cd ${WIP}
	if [ -f iso-chroot/etc/resolv.conf ]; then
		sudo mv iso-chroot/etc/resolv.conf iso-chroot/etc/resolv.conf.linuxium
	fi
	# dev media mnt opt proc run snap srv sys tmp
	for DIRECTORY in dev run tmp
	do
		sudo mv iso-chroot/${DIRECTORY} iso-chroot/${DIRECTORY}.linuxium
		sudo cp -a iso-chroot/${DIRECTORY}.linuxium iso-chroot/${DIRECTORY}
	done
	sudo cp /etc/resolv.conf iso-chroot/etc/
	sudo mv iso-chroot/etc/apt/sources.list iso-chroot/etc/apt/sources.list.linuxium
	sudo sed 's/\(deb.*\)$/\1 universe multiverse/' iso-chroot/etc/apt/sources.list.linuxium | sudo tee iso-chroot/etc/apt/sources.list > /dev/null
	sudo rm -f iso-chroot/usr/src/.key.failed iso-chroot/usr/src/.key.log
	sudo mount --bind /dev/ iso-chroot/dev
	for KEY_ARRAY in $(seq 0 $((${#KEYS[@]}-1)))
	do
		KEY_TO_ADD=${KEYS[${KEY_ARRAY}]}
		sudo chroot iso-chroot /bin/bash > /dev/null 2>&1 <<+
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devpts none /dev/pts
export HOME=/root
export LC_ALL=C
trap '' SIGHUP SIGINT SIGTERM
cd /usr/src
apt-get update
DEBIAN_FRONTEND=noninteractive apt-key ${KEY_TO_ADD} > .key.log 2>&1
KEY_ADDED=\$?
if [ \${KEY_ADDED} != 0 ]; then
	echo "${KEY_TO_ADD}" > .key.failed
else
	rm -f .key.log
	apt-get update
	if (! grep -q '^overlay$' /etc/initramfs-tools/modules); then echo overlay >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
	if (! grep -q '^pwm-lpss$' /etc/initramfs-tools/modules); then echo pwm-lpss >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
	if (! grep -q '^pwm-lpss-platform$' /etc/initramfs-tools/modules); then echo pwm-lpss-platform >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
	if \${UPDATE_INITRAMFS};then update-initramfs -u; fi
	apt-get clean
	apt-get autoclean
	apt-get -y autoremove
fi
umount /proc || umount -lf /proc
umount /sys
umount /dev/pts
+
		if [ -f iso-chroot/usr/src/.key.failed ]; then
			break
		fi
	done
	sudo umount iso-chroot/dev
	if [ -f iso-chroot/usr/src/.key.failed ]; then
		KEY_TO_ADD=$(cat iso-chroot/usr/src/.key.failed)
		sudo cat iso-chroot/usr/src/.key.log
		DISPLAY_MESSAGE "${0}: Adding key '${KEY_TO_ADD}' failed."
		CLEAN_EXIT
	fi
	sudo mv iso-chroot/etc/apt/sources.list.linuxium iso-chroot/etc/apt/sources.list
	if [ -f iso-chroot/etc/resolv.conf.linuxium ]; then
		sudo mv iso-chroot/etc/resolv.conf.linuxium iso-chroot/etc/resolv.conf
	fi
	sudo rm -f iso-chroot/root/.bash_history
	sudo rm -f iso-chroot/boot/grub/grub.cfg
	sudo rm -f iso-chroot/etc/mtab
	sudo rm -f iso-chroot/var/lib/dpkg/status-old
	for DIRECTORY in dev run tmp
	do
		sudo rm -rf iso-chroot/${DIRECTORY}
		sudo mv iso-chroot/${DIRECTORY}.linuxium iso-chroot/${DIRECTORY}
	done
	for KEY_ARRAY in $(seq 0 $((${#KEYS[@]}-1)))
	do
		echo "Key '${KEYS[${KEY_ARRAY}]}' added ..." >> ${ISORESPIN_LOGFILE}
	done
}

function ADD_REPOSITORIES {
	DISPLAY_PROGRESS "Adding repositories ..."
	cd ${WIP}
	if [ -f iso-chroot/etc/resolv.conf ]; then
		sudo mv iso-chroot/etc/resolv.conf iso-chroot/etc/resolv.conf.linuxium
	fi
	# dev media mnt opt proc run snap srv sys tmp
	for DIRECTORY in dev run tmp
	do
		sudo mv iso-chroot/${DIRECTORY} iso-chroot/${DIRECTORY}.linuxium
		sudo cp -a iso-chroot/${DIRECTORY}.linuxium iso-chroot/${DIRECTORY}
	done
	sudo cp /etc/resolv.conf iso-chroot/etc/
	sudo mv iso-chroot/etc/apt/sources.list iso-chroot/etc/apt/sources.list.linuxium
	sudo sed 's/\(deb.*\)$/\1 universe multiverse/' iso-chroot/etc/apt/sources.list.linuxium | sudo tee iso-chroot/etc/apt/sources.list.linuxium.unpatched > /dev/null
	sudo sed 's/\(deb.*\)$/\1 universe multiverse/' iso-chroot/etc/apt/sources.list.linuxium | sudo tee iso-chroot/etc/apt/sources.list > /dev/null
	sudo rm -f iso-chroot/usr/src/.repository.failed iso-chroot/usr/src/.repository.log
	for REPOSITORY_ARRAY in $(seq 0 $((${#REPOSITORIES[@]}-1)))
	do
		REPOSITORY_TO_ADD=${REPOSITORIES[${REPOSITORY_ARRAY}]}
		sudo chroot iso-chroot /bin/bash > /dev/null 2>&1 <<+
export HOME=/root
export LC_ALL=C
trap '' SIGHUP SIGINT SIGTERM
cd /usr/src
apt-get update
add-apt-repository -y "${REPOSITORY_TO_ADD}" > .repository.log 2>&1
REPOSITORY_ADDED=\$?
if [ \${REPOSITORY_ADDED} != 0 ]; then
	echo "${REPOSITORY_TO_ADD}" > .repository.failed
else
	rm -f .repository.log
	if (! grep -q '^overlay$' /etc/initramfs-tools/modules); then echo overlay >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
	if (! grep -q '^pwm-lpss$' /etc/initramfs-tools/modules); then echo pwm-lpss >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
	if (! grep -q '^pwm-lpss-platform$' /etc/initramfs-tools/modules); then echo pwm-lpss-platform >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
	if \${UPDATE_INITRAMFS};then update-initramfs -u; fi
	apt-get update
	apt-get clean
	apt-get autoclean
	apt-get -y autoremove
fi
+
		if [ -f iso-chroot/usr/src/.repository.failed ]; then
			break
		fi
	done
	if [ -f iso-chroot/usr/src/.repository.failed ]; then
		REPOSITORY_TO_ADD=$(cat iso-chroot/usr/src/.repository.failed)
		sudo cat iso-chroot/usr/src/.repository.log
		DISPLAY_MESSAGE "${0}: Adding repository '${REPOSITORY_TO_ADD}' failed."
		CLEAN_EXIT
	fi
	sudo diff -u iso-chroot/etc/apt/sources.list.linuxium.unpatched iso-chroot/etc/apt/sources.list > iso-chroot/tmp/linuxium.patch
	sudo mv iso-chroot/etc/apt/sources.list.linuxium iso-chroot/etc/apt/sources.list
	sudo cp iso-chroot/etc/apt/sources.list iso-chroot/etc/apt/sources.list.save
	sudo cat iso-chroot/tmp/linuxium.patch | grep -v '^+++' | grep '^+' | sed 's/^+//' | sudo tee -a iso-chroot/etc/apt/sources.list > /dev/null
	sudo rm -f iso-chroot/etc/apt/sources.list.linuxium.unpatched iso-chroot/tmp/linuxium.patch
	if [ -f iso-chroot/etc/resolv.conf.linuxium ]; then
		sudo mv iso-chroot/etc/resolv.conf.linuxium iso-chroot/etc/resolv.conf
	fi
	sudo rm -f iso-chroot/root/.bash_history
	sudo rm -f iso-chroot/boot/grub/grub.cfg
	sudo rm -f iso-chroot/etc/mtab
	sudo rm -f iso-chroot/var/lib/dpkg/status-old
	for DIRECTORY in dev run tmp
	do
		sudo rm -rf iso-chroot/${DIRECTORY}
		sudo mv iso-chroot/${DIRECTORY}.linuxium iso-chroot/${DIRECTORY}
	done
	for REPOSITORY_ARRAY in $(seq 0 $((${#REPOSITORIES[@]}-1)))
	do
		if ${REMOVE_ROLLING_REPOSITORY}; then
			if [ "${REPOSITORIES[${REPOSITORY_ARRAY}]}" != "${ROLLING_REPOSITORY}" ]; then
				echo "Repository '${REPOSITORIES[${REPOSITORY_ARRAY}]}' added ..." >> ${ISORESPIN_LOGFILE}
			fi
		else
			echo "Repository '${REPOSITORIES[${REPOSITORY_ARRAY}]}' added ..." >> ${ISORESPIN_LOGFILE}
		fi
	done
}

function REMOVE_REPOSITORY {
	DISPLAY_PROGRESS "Removing rolling repository ..."
	cd ${WIP}
	if [ -f iso-chroot/etc/resolv.conf ]; then
		sudo mv iso-chroot/etc/resolv.conf iso-chroot/etc/resolv.conf.linuxium
	fi
	# dev media mnt opt proc run snap srv sys tmp
	for DIRECTORY in dev run tmp
	do
		sudo mv iso-chroot/${DIRECTORY} iso-chroot/${DIRECTORY}.linuxium
		sudo cp -a iso-chroot/${DIRECTORY}.linuxium iso-chroot/${DIRECTORY}
	done
	sudo cp /etc/resolv.conf iso-chroot/etc/
	sudo mv iso-chroot/etc/apt/sources.list iso-chroot/etc/apt/sources.list.linuxium
	sudo sed 's/\(deb.*\)$/\1 universe multiverse/' iso-chroot/etc/apt/sources.list.linuxium | sudo tee iso-chroot/etc/apt/sources.list.linuxium.unpatched > /dev/null
	sudo sed 's/\(deb.*\)$/\1 universe multiverse/' iso-chroot/etc/apt/sources.list.linuxium | sudo tee iso-chroot/etc/apt/sources.list > /dev/null
	sudo rm -f iso-chroot/usr/src/.repository.failed iso-chroot/usr/src/.repository.log
	sudo chroot iso-chroot /bin/bash > /dev/null 2>&1 <<+
export HOME=/root
export LC_ALL=C
trap '' SIGHUP SIGINT SIGTERM
cd /usr/src
apt-get update
add-apt-repository -r -y "${ROLLING_REPOSITORY}" > .repository.log 2>&1
REPOSITORY_REMOVED=\$?
if [ \${REPOSITORY_REMOVED} != 0 ]; then
	echo "${ROLLING_REPOSITORY}" > .repository.failed
else
	rm -f .repository.log
	if (! grep -q '^overlay$' /etc/initramfs-tools/modules); then echo overlay >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
	if (! grep -q '^pwm-lpss$' /etc/initramfs-tools/modules); then echo pwm-lpss >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
	if (! grep -q '^pwm-lpss-platform$' /etc/initramfs-tools/modules); then echo pwm-lpss-platform >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
	if \${UPDATE_INITRAMFS};then update-initramfs -u; fi
	apt-get update
	apt-get clean
	apt-get autoclean
	apt-get -y autoremove
fi
+
	if [ -f iso-chroot/usr/src/.repository.failed ]; then
		sudo cat iso-chroot/usr/src/.repository.log
		DISPLAY_MESSAGE "${0}: Removing rolling repository '${ROLLING_REPOSITORY}' failed."
		CLEAN_EXIT
	fi
	sudo diff -u iso-chroot/etc/apt/sources.list.linuxium.unpatched iso-chroot/etc/apt/sources.list > iso-chroot/tmp/linuxium.patch
	sudo mv iso-chroot/etc/apt/sources.list.linuxium iso-chroot/etc/apt/sources.list
	sudo cp iso-chroot/etc/apt/sources.list iso-chroot/etc/apt/sources.list.save
	sudo cat iso-chroot/tmp/linuxium.patch | grep -v '^+++' | grep '^+' | sed 's/^+//' | sudo tee -a iso-chroot/etc/apt/sources.list > /dev/null
	sudo rm -f iso-chroot/etc/apt/sources.list.linuxium.unpatched iso-chroot/tmp/linuxium.patch
	if [ -f iso-chroot/etc/resolv.conf.linuxium ]; then
		sudo mv iso-chroot/etc/resolv.conf.linuxium iso-chroot/etc/resolv.conf
	fi
	sudo rm -f iso-chroot/root/.bash_history
	sudo rm -f iso-chroot/boot/grub/grub.cfg
	sudo rm -f iso-chroot/etc/mtab
	sudo rm -f iso-chroot/var/lib/dpkg/status-old
	for DIRECTORY in dev run tmp
	do
		sudo rm -rf iso-chroot/${DIRECTORY}
		sudo mv iso-chroot/${DIRECTORY}.linuxium iso-chroot/${DIRECTORY}
	done
}

function PURGE_PACKAGES {
	DISPLAY_PROGRESS "Purging packages ..."
	cd ${WIP}
	if [ -f iso-chroot/etc/resolv.conf ]; then
		sudo mv iso-chroot/etc/resolv.conf iso-chroot/etc/resolv.conf.linuxium
	fi
	# dev media mnt opt proc run snap srv sys tmp
	for DIRECTORY in dev run tmp
	do
		sudo mv iso-chroot/${DIRECTORY} iso-chroot/${DIRECTORY}.linuxium
		sudo cp -a iso-chroot/${DIRECTORY}.linuxium iso-chroot/${DIRECTORY}
	done
	sudo cp /etc/resolv.conf iso-chroot/etc/
	sudo mv iso-chroot/etc/apt/sources.list iso-chroot/etc/apt/sources.list.linuxium
	sudo sed 's/\(deb.*\)$/\1 universe multiverse/' iso-chroot/etc/apt/sources.list.linuxium | sudo tee iso-chroot/etc/apt/sources.list > /dev/null
	sudo rm -f iso-chroot/usr/src/.package.missing iso-chroot/usr/src/.package.failed iso-chroot/usr/src/.package.log
	sudo mount --bind /dev/ iso-chroot/dev
	for PACKAGE_ARRAY in $(seq 0 $((${#PURGE_PACKAGES[@]}-1)))
	do
		PACKAGES_TO_PURGE=${PURGE_PACKAGES[${PACKAGE_ARRAY}]}
		sudo chroot iso-chroot /bin/bash > /dev/null 2>&1 <<+
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devpts none /dev/pts
export HOME=/root
export LC_ALL=C
trap '' SIGHUP SIGINT SIGTERM
cd /usr/src
apt-get update
for PACKAGE in ${PACKAGES_TO_PURGE}
do
	if (! apt-cache show \${PACKAGE}^ > /dev/null 2>&1); then
		if (! apt-cache show \${PACKAGE} > /dev/null 2>&1); then
			echo "\${PACKAGE}" > .package.missing
			break
		fi
	fi
done
if [ ! -f .package.missing ]; then
	for PACKAGE in ${PACKAGES_TO_PURGE}
	do
		if (apt-cache show \${PACKAGE}^ > /dev/null 2>&1); then
			DEBIAN_FRONTEND=noninteractive apt-get purge -y --autoremove \${PACKAGE}^ > .package.log 2>&1
		else
			DEBIAN_FRONTEND=noninteractive apt-get purge -y --autoremove \${PACKAGE} > .package.log 2>&1
		fi
		PACKAGE_PURGED=\$?
		if [ \${PACKAGE_PURGED} != 0 ]; then
			echo "\${PACKAGE}" > .package.failed
			break
		else
			rm -f .package.log
		fi
	done
fi
if [ ! -f .package.missing -a ! -f .package.failed ]; then
	if (! grep -q '^overlay$' /etc/initramfs-tools/modules); then echo overlay >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
	if (! grep -q '^pwm-lpss$' /etc/initramfs-tools/modules); then echo pwm-lpss >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
	if (! grep -q '^pwm-lpss-platform$' /etc/initramfs-tools/modules); then echo pwm-lpss-platform >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
	update-initramfs -u
	LATEST_INITRD=\$(ls -t /boot/initrd* 2> /dev/null | head -1)
	LATEST_KERNEL=\${LATEST_INITRD#*-}
	depmod -a \${LATEST_KERNEL}
	apt-get clean
	apt-get autoclean
	apt-get -y autoremove
fi
umount /proc || umount -lf /proc
umount /sys
umount /dev/pts
+
		if [ -f iso-chroot/usr/src/.package.missing -o -f iso-chroot/usr/src/.package.failed ]; then
			break
		fi
	done
	sudo umount iso-chroot/dev
	if [ -f iso-chroot/usr/src/.package.missing ]; then
		PACKAGE=$(cat iso-chroot/usr/src/.package.missing)
		DISPLAY_MESSAGE "${0}: Package '${PACKAGE}' not found."
		CLEAN_EXIT
	fi
	if [ -f iso-chroot/usr/src/.package.failed ]; then
		PACKAGE=$(cat iso-chroot/usr/src/.package.failed)
		sudo cat iso-chroot/usr/src/.package.log
		DISPLAY_MESSAGE "${0}: Package '${PACKAGE}' failed to purge correctly."
		CLEAN_EXIT
	fi
	sudo mv iso-chroot/etc/apt/sources.list.linuxium iso-chroot/etc/apt/sources.list
	if [ -f iso-chroot/etc/resolv.conf.linuxium ]; then
		sudo mv iso-chroot/etc/resolv.conf.linuxium iso-chroot/etc/resolv.conf
	fi
	sudo rm -f iso-chroot/root/.bash_history
	sudo rm -f iso-chroot/boot/grub/grub.cfg
	sudo rm -f iso-chroot/etc/mtab
	sudo rm -f iso-chroot/var/lib/dpkg/status-old
	for DIRECTORY in dev run tmp
	do
		sudo rm -rf iso-chroot/${DIRECTORY}
		sudo mv iso-chroot/${DIRECTORY}.linuxium iso-chroot/${DIRECTORY}
	done
	# update kernel in iso just in case
	MAINLINE_VMLINUZ=$(ls -t iso-chroot/boot/vmlinuz* 2> /dev/null | head -1)
	if [ -n "${MAINLINE_VMLINUZ}" ]; then
		sudo cp ${MAINLINE_VMLINUZ} iso-directory-structure/${ISO_SQUASHFS_DIRECTORY}/${ISO_VMLINUZ}
		MAINLINE_RELEASE=${MAINLINE_VMLINUZ#iso-chroot/boot/vmlinuz-}
		MAINLINE_INITRD=$(ls -t iso-chroot/boot/initrd.img-${MAINLINE_RELEASE} 2> /dev/null | head -1)
	else
		MAINLINE_INITRD=$(ls -t iso-chroot/boot/initrd* 2> /dev/null | head -1)
	fi
	if [ -n "${MAINLINE_INITRD}" ]; then
		sudo cp ${MAINLINE_INITRD} iso-directory-structure/${ISO_SQUASHFS_DIRECTORY}/${ISO_INITRD}
	fi
	for PACKAGE_ARRAY in $(seq 0 $((${#PURGE_PACKAGES[@]}-1)))
	do
		echo "Package '${PURGE_PACKAGES[${PACKAGE_ARRAY}]}' purged ..." >> ${ISORESPIN_LOGFILE}
	done
}

function INSTALL_PACKAGES {
	DISPLAY_PROGRESS "Installing packages ..."
	cd ${WIP}
	if [ -f iso-chroot/etc/resolv.conf ]; then
		sudo mv iso-chroot/etc/resolv.conf iso-chroot/etc/resolv.conf.linuxium
	fi
	# dev media mnt opt proc run snap srv sys tmp
	for DIRECTORY in dev run tmp
	do
		sudo mv iso-chroot/${DIRECTORY} iso-chroot/${DIRECTORY}.linuxium
		sudo cp -a iso-chroot/${DIRECTORY}.linuxium iso-chroot/${DIRECTORY}
	done
	sudo cp /etc/resolv.conf iso-chroot/etc/
	sudo mv iso-chroot/etc/apt/sources.list iso-chroot/etc/apt/sources.list.linuxium
	sudo sed 's/\(deb.*\)$/\1 universe multiverse/' iso-chroot/etc/apt/sources.list.linuxium | sudo tee iso-chroot/etc/apt/sources.list > /dev/null
	sudo rm -f iso-chroot/usr/src/.package.missing iso-chroot/usr/src/.package.failed iso-chroot/usr/src/.package.log
	sudo mount --bind /dev/ iso-chroot/dev
	for PACKAGE_ARRAY in $(seq 0 $((${#PACKAGES[@]}-1)))
	do
		PACKAGES_TO_INSTALL=${PACKAGES[${PACKAGE_ARRAY}]}
		sudo chroot iso-chroot /bin/bash > /dev/null 2>&1 <<+
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devpts none /dev/pts
export HOME=/root
export LC_ALL=C
trap '' SIGHUP SIGINT SIGTERM
cd /usr/src
apt-get update
for PACKAGE in ${PACKAGES_TO_INSTALL}
do
	if (! apt-cache show \${PACKAGE}^ > /dev/null 2>&1); then
		if (! apt-cache show \${PACKAGE} > /dev/null 2>&1); then
			echo "\${PACKAGE}" > .package.missing
			break
		fi
	fi
done
if [ ! -f .package.missing ]; then
	for PACKAGE in ${PACKAGES_TO_INSTALL}
	do
		if (apt-cache show \${PACKAGE}^ > /dev/null 2>&1); then
			DEBIAN_FRONTEND=noninteractive apt-get install -y \${PACKAGE}^ > .package.log 2>&1
		else
			DEBIAN_FRONTEND=noninteractive apt-get install -y \${PACKAGE} > .package.log 2>&1
		fi
		PACKAGE_INSTALLED=\$?
		if [ \${PACKAGE_INSTALLED} != 0 ]; then
			echo "\${PACKAGE}" > .package.failed
			break
		else
			rm -f .package.log
		fi
	done
fi
if [ ! -f .package.missing -a ! -f .package.failed ]; then
	if (! grep -q '^overlay$' /etc/initramfs-tools/modules); then echo overlay >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
	if (! grep -q '^pwm-lpss$' /etc/initramfs-tools/modules); then echo pwm-lpss >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
	if (! grep -q '^pwm-lpss-platform$' /etc/initramfs-tools/modules); then echo pwm-lpss-platform >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
	update-initramfs -u
	LATEST_INITRD=\$(ls -t /boot/initrd* 2> /dev/null | head -1)
	LATEST_KERNEL=\${LATEST_INITRD#*-}
	depmod -a \${LATEST_KERNEL}
	apt-get clean
	apt-get autoclean
	apt-get -y autoremove
fi
umount /proc || umount -lf /proc
umount /sys
umount /dev/pts
+
		if [ -f iso-chroot/usr/src/.package.missing -o -f iso-chroot/usr/src/.package.failed ]; then
			break
		fi
	done
	sudo umount iso-chroot/dev
	if [ -f iso-chroot/usr/src/.package.missing ]; then
		PACKAGE=$(cat iso-chroot/usr/src/.package.missing)
		DISPLAY_MESSAGE "${0}: Package '${PACKAGE}' not found."
		CLEAN_EXIT
	fi
	if [ -f iso-chroot/usr/src/.package.failed ]; then
		PACKAGE=$(cat iso-chroot/usr/src/.package.failed)
		sudo cat iso-chroot/usr/src/.package.log
		DISPLAY_MESSAGE "${0}: Package '${PACKAGE}' failed to install correctly."
		CLEAN_EXIT
	fi
	sudo mv iso-chroot/etc/apt/sources.list.linuxium iso-chroot/etc/apt/sources.list
	if [ -f iso-chroot/etc/resolv.conf.linuxium ]; then
		sudo mv iso-chroot/etc/resolv.conf.linuxium iso-chroot/etc/resolv.conf
	fi
	sudo rm -f iso-chroot/root/.bash_history
	sudo rm -f iso-chroot/boot/grub/grub.cfg
	sudo rm -f iso-chroot/etc/mtab
	sudo rm -f iso-chroot/var/lib/dpkg/status-old
	for DIRECTORY in dev run tmp
	do
		sudo rm -rf iso-chroot/${DIRECTORY}
		sudo mv iso-chroot/${DIRECTORY}.linuxium iso-chroot/${DIRECTORY}
	done
	# update kernel in iso just in case
	MAINLINE_VMLINUZ=$(ls -t iso-chroot/boot/vmlinuz* 2> /dev/null | head -1)
	if [ -n "${MAINLINE_VMLINUZ}" ]; then
		sudo cp ${MAINLINE_VMLINUZ} iso-directory-structure/${ISO_SQUASHFS_DIRECTORY}/${ISO_VMLINUZ}
		MAINLINE_RELEASE=${MAINLINE_VMLINUZ#iso-chroot/boot/vmlinuz-}
		MAINLINE_INITRD=$(ls -t iso-chroot/boot/initrd.img-${MAINLINE_RELEASE} 2> /dev/null | head -1)
	else
		MAINLINE_INITRD=$(ls -t iso-chroot/boot/initrd* 2> /dev/null | head -1)
	fi
	if [ -n "${MAINLINE_INITRD}" ]; then
		sudo cp ${MAINLINE_INITRD} iso-directory-structure/${ISO_SQUASHFS_DIRECTORY}/${ISO_INITRD}
	fi
	for PACKAGE_ARRAY in $(seq 0 $((${#PACKAGES[@]}-1)))
	do
		echo "Package '${PACKAGES[${PACKAGE_ARRAY}]}' added ..." >> ${ISORESPIN_LOGFILE}
	done
}

function INSTALL_LOCAL_PACKAGES {
	DISPLAY_PROGRESS "Installing local packages ..."
	cd ${WIP}
	for LOCAL_PACKAGE_ARRAY in $(seq 0 $((${#FULLNAME_LOCAL_PACKAGES[@]}-1)))
	do
		for PACKAGE in ${FULLNAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]}
		do
			sudo cp ${PACKAGE} iso-chroot/usr/src
		done
	done
	if [ -f iso-chroot/etc/resolv.conf ]; then
		sudo mv iso-chroot/etc/resolv.conf iso-chroot/etc/resolv.conf.linuxium
	fi
	# dev media mnt opt proc run snap srv sys tmp
	for DIRECTORY in dev run tmp
	do
		sudo mv iso-chroot/${DIRECTORY} iso-chroot/${DIRECTORY}.linuxium
		sudo cp -a iso-chroot/${DIRECTORY}.linuxium iso-chroot/${DIRECTORY}
	done
	sudo cp /etc/resolv.conf iso-chroot/etc/
	sudo mv iso-chroot/etc/apt/sources.list iso-chroot/etc/apt/sources.list.linuxium
	sudo sed 's/\(deb.*\)$/\1 universe multiverse/' iso-chroot/etc/apt/sources.list.linuxium | sudo tee iso-chroot/etc/apt/sources.list > /dev/null
	sudo rm -f iso-chroot/usr/src/.package.missing iso-chroot/usr/src/.package.failed iso-chroot/usr/src/.package.log
	sudo mount --bind /dev/ iso-chroot/dev
	for LOCAL_PACKAGE_ARRAY in $(seq 0 $((${#BASENAME_LOCAL_PACKAGES[@]}-1)))
	do
		PACKAGES_TO_INSTALL=${BASENAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]}
		sudo chroot iso-chroot /bin/bash > /dev/null 2>&1 <<+
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devpts none /dev/pts
export HOME=/root
export LC_ALL=C
trap '' SIGHUP SIGINT SIGTERM
cd /usr/src
apt-get update
apt-get install -y gdebi
for PACKAGE in ${PACKAGES_TO_INSTALL}
do
	DEBIAN_FRONTEND=noninteractive gdebi -n \${PACKAGE} > .package.log 2>&1
	PACKAGE_INSTALLED=\$?
	if [ \${PACKAGE_INSTALLED} != 0 ]; then
		echo "\${PACKAGE}" > .package.failed
		break
	else
		rm -f .package.log
		rm -f \${PACKAGE}
	fi
done
if [ ! -f .package.failed ]; then
	if (! grep -q '^overlay$' /etc/initramfs-tools/modules); then echo overlay >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
	if (! grep -q '^pwm-lpss$' /etc/initramfs-tools/modules); then echo pwm-lpss >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
	if (! grep -q '^pwm-lpss-platform$' /etc/initramfs-tools/modules); then echo pwm-lpss-platform >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
	update-initramfs -u
	LATEST_INITRD=\$(ls -t /boot/initrd* 2> /dev/null | head -1)
	LATEST_KERNEL=\${LATEST_INITRD#*-}
	depmod -a \${LATEST_KERNEL}
	apt-get clean
	apt-get autoclean
	apt-get -y autoremove
fi
umount /proc || umount -lf /proc
umount /sys
umount /dev/pts
+
		if [ -f iso-chroot/usr/src/.package.failed ]; then
			break
		fi
	done
	sudo umount iso-chroot/dev
	if [ -f iso-chroot/usr/src/.package.failed ]; then
		PACKAGE=$(cat iso-chroot/usr/src/.package.failed)
		sudo cat iso-chroot/usr/src/.package.log
		DISPLAY_MESSAGE "${0}: Local package '${PACKAGE}' failed to install correctly."
		CLEAN_EXIT
	fi
	sudo mv iso-chroot/etc/apt/sources.list.linuxium iso-chroot/etc/apt/sources.list
	if [ -f iso-chroot/etc/resolv.conf.linuxium ]; then
		sudo mv iso-chroot/etc/resolv.conf.linuxium iso-chroot/etc/resolv.conf
	fi
	sudo rm -f iso-chroot/root/.bash_history
	sudo rm -f iso-chroot/boot/grub/grub.cfg
	sudo rm -f iso-chroot/etc/mtab
	sudo rm -f iso-chroot/var/lib/dpkg/status-old
	for DIRECTORY in dev run tmp
	do
		sudo rm -rf iso-chroot/${DIRECTORY}
		sudo mv iso-chroot/${DIRECTORY}.linuxium iso-chroot/${DIRECTORY}
	done
	# update kernel in iso just in case
	MAINLINE_VMLINUZ=$(ls -t iso-chroot/boot/vmlinuz* 2> /dev/null | head -1)
	if [ -n "${MAINLINE_VMLINUZ}" ]; then
		sudo cp ${MAINLINE_VMLINUZ} iso-directory-structure/${ISO_SQUASHFS_DIRECTORY}/${ISO_VMLINUZ}
		MAINLINE_RELEASE=${MAINLINE_VMLINUZ#iso-chroot/boot/vmlinuz-}
		MAINLINE_INITRD=$(ls -t iso-chroot/boot/initrd.img-${MAINLINE_RELEASE} 2> /dev/null | head -1)
	else
		MAINLINE_INITRD=$(ls -t iso-chroot/boot/initrd* 2> /dev/null | head -1)
	fi
	if [ -n "${MAINLINE_INITRD}" ]; then
		sudo cp ${MAINLINE_INITRD} iso-directory-structure/${ISO_SQUASHFS_DIRECTORY}/${ISO_INITRD}
	fi
	for LOCAL_PACKAGE_ARRAY in $(seq 0 $((${#FULLNAME_LOCAL_PACKAGES[@]}-1)))
	do
		echo "Local package '${FULLNAME_LOCAL_PACKAGES[${LOCAL_PACKAGE_ARRAY}]}' added ..." >> ${ISORESPIN_LOGFILE}
	done
}

function DOWNLOAD_PACKAGES {
	DISPLAY_PROGRESS "Downloading packages ..."
	cd ${WIP}
	if [ -f iso-chroot/etc/resolv.conf ]; then
		sudo mv iso-chroot/etc/resolv.conf iso-chroot/etc/resolv.conf.linuxium
	fi
	# dev media mnt opt proc run snap srv sys tmp
	for DIRECTORY in dev run tmp
	do
		sudo mv iso-chroot/${DIRECTORY} iso-chroot/${DIRECTORY}.linuxium
		sudo cp -a iso-chroot/${DIRECTORY}.linuxium iso-chroot/${DIRECTORY}
	done
	sudo cp /etc/resolv.conf iso-chroot/etc/
	sudo mv iso-chroot/etc/apt/sources.list iso-chroot/etc/apt/sources.list.linuxium
	sudo sed 's/\(deb.*\)$/\1 universe multiverse/' iso-chroot/etc/apt/sources.list.linuxium | sudo tee iso-chroot/etc/apt/sources.list > /dev/null
	sudo rm -f iso-chroot/usr/src/.package.missing iso-chroot/usr/src/.package.failed iso-chroot/usr/src/.package.log
	sudo mount --bind /dev/ iso-chroot/dev
	for DOWNLOAD_ARRAY in $(seq 0 $((${#DOWNLOADS[@]}-1)))
	do
		PACKAGES_TO_DOWNLOAD=${DOWNLOADS[${DOWNLOAD_ARRAY}]}
		sudo chroot iso-chroot /bin/bash > /dev/null 2>&1 <<+
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devpts none /dev/pts
export HOME=/root
export LC_ALL=C
trap '' SIGHUP SIGINT SIGTERM
cd /usr/src
apt-get update
for PACKAGE in ${PACKAGES_TO_DOWNLOAD}
do
	apt-cache show \${PACKAGE} > /dev/null 2>&1
	PACKAGE_FOUND=\$?
	if [ \${PACKAGE_FOUND} != 0 ]; then
		echo "\${PACKAGE}" > .package.missing
		break
	fi
done
if [ ! -f .package.missing ]; then
	for PACKAGE in ${PACKAGES_TO_DOWNLOAD}
	do
		apt-get download -y \${PACKAGE} >> .package.log 2>&1
		PACKAGE_DOWNLOADED=\$?
		if [ \${PACKAGE_DOWNLOADED} != 0 ]; then
			echo "\${PACKAGE}" > .package.failed
			break
		else
			rm -f .package.log
		fi
	done
fi
if [ ! -f .package.missing -a ! -f .package.failed ]; then
	apt-get clean
	apt-get autoclean
	apt-get -y autoremove
fi
umount /proc || umount -lf /proc
umount /sys
umount /dev/pts
+
		if [ -f iso-chroot/usr/src/.package.missing -o -f iso-chroot/usr/src/.package.failed ]; then
			break
		fi
	done
	sudo umount iso-chroot/dev
	if [ -f iso-chroot/usr/src/.package.missing ]; then
		PACKAGE=$(cat iso-chroot/usr/src/.package.missing)
		DISPLAY_MESSAGE "${0}: Download package '${PACKAGE}' not found."
		CLEAN_EXIT
	fi
	if [ -f iso-chroot/usr/src/.package.failed ]; then
		PACKAGE=$(cat iso-chroot/usr/src/.package.failed)
		sudo cat iso-chroot/usr/src/.package.log
		DISPLAY_MESSAGE "${0}: Download package '${PACKAGE}' failed to download correctly."
		CLEAN_EXIT
	fi
	sudo mv iso-chroot/etc/apt/sources.list.linuxium iso-chroot/etc/apt/sources.list
	if [ -f iso-chroot/etc/resolv.conf.linuxium ]; then
		sudo mv iso-chroot/etc/resolv.conf.linuxium iso-chroot/etc/resolv.conf
	fi
	sudo rm -f iso-chroot/root/.bash_history
	sudo rm -f iso-chroot/boot/grub/grub.cfg
	sudo rm -f iso-chroot/etc/mtab
	sudo rm -f iso-chroot/var/lib/dpkg/status-old
	for DIRECTORY in dev run tmp
	do
		sudo rm -rf iso-chroot/${DIRECTORY}
		sudo mv iso-chroot/${DIRECTORY}.linuxium iso-chroot/${DIRECTORY}
	done
	for DOWNLOAD_ARRAY in $(seq 0 $((${#DOWNLOADS[@]}-1)))
	do
		echo "Download package '${DOWNLOADS[${DOWNLOAD_ARRAY}]}' added ..." >> ${ISORESPIN_LOGFILE}
	done
}

function ADD_FILES {
	DISPLAY_PROGRESS "Adding files/directories ..."
	cd ${WIP}
	sudo mkdir -p iso-chroot/usr/local/bin
	for FILE_ARRAY in $(seq 0 $((${#FULLNAME_ADDITIONAL_FILES[@]}-1)))
	do
		for FILES_TO_ADD in ${FULLNAME_ADDITIONAL_FILES[${FILE_ARRAY}]}
		do
			for ADDITIONAL_FILE in ${FILES_TO_ADD}
			do
				if [ -f ${ADDITIONAL_FILE} ]; then
					sudo cp ${ADDITIONAL_FILE} iso-chroot/usr/local/bin
					echo "File '${ADDITIONAL_FILE}' added ..." >> ${ISORESPIN_LOGFILE}
				else
					sudo cp -a ${ADDITIONAL_FILE} iso-chroot/usr/local/bin
					echo "Directory '${ADDITIONAL_FILE}' added ..." >> ${ISORESPIN_LOGFILE}
				fi
			done
		done
	done
}

function RUN_COMMANDS {
	DISPLAY_PROGRESS "Running commands ..."
	cd ${WIP}
	if [ -f iso-chroot/etc/resolv.conf ]; then
		sudo mv iso-chroot/etc/resolv.conf iso-chroot/etc/resolv.conf.linuxium
	fi
	# dev media mnt opt proc run snap srv sys tmp
	for DIRECTORY in dev run tmp
	do
		sudo mv iso-chroot/${DIRECTORY} iso-chroot/${DIRECTORY}.linuxium
		sudo cp -a iso-chroot/${DIRECTORY}.linuxium iso-chroot/${DIRECTORY}
	done
	sudo cp /etc/resolv.conf iso-chroot/etc/
	sudo mv iso-chroot/etc/apt/sources.list iso-chroot/etc/apt/sources.list.linuxium
	sudo sed 's/\(deb.*\)$/\1 universe multiverse/' iso-chroot/etc/apt/sources.list.linuxium | sudo tee iso-chroot/etc/apt/sources.list > /dev/null
	sudo rm -f iso-chroot/root/.command.log
	trap '' SIGHUP SIGINT SIGTERM
	sudo mount --bind /dev/ iso-chroot/dev
	echo "Command run ..." >> ${ISORESPIN_LOGFILE}
	for COMMAND_ARRAY in $(seq 0 $((${#COMMANDS[@]}-1)))
	do
		COMMAND="${COMMANDS[${COMMAND_ARRAY}]}"
		sudo chroot iso-chroot /bin/bash > /dev/null 2>&1 <<+
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devpts none /dev/pts
export HOME=/root
export LC_ALL=C
cd /root
echo "# ${COMMAND}" > .command.log 2>&1
bash -c "${COMMAND}" >> .command.log 2>&1
if (! grep -q '^overlay$' /etc/initramfs-tools/modules); then echo overlay >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
if (! grep -q '^pwm-lpss$' /etc/initramfs-tools/modules); then echo pwm-lpss >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
if (! grep -q '^pwm-lpss-platform$' /etc/initramfs-tools/modules); then echo pwm-lpss-platform >> /etc/initramfs-tools/modules; UPDATE_INITRAMFS=true; else UPDATE_INITRAMFS=false; fi
if \${UPDATE_INITRAMFS};then update-initramfs -u; fi
umount /proc || umount -lf /proc
umount /sys
umount /dev/pts
+
		sudo cat iso-chroot/root/.command.log >> ${ISORESPIN_LOGFILE}
	done
	sudo umount iso-chroot/dev
	sudo rm -f iso-chroot/root/.command.log
	trap 'FORCED_EXIT' SIGHUP SIGINT SIGTERM
	sudo mv iso-chroot/etc/apt/sources.list.linuxium iso-chroot/etc/apt/sources.list
	if [ -f iso-chroot/etc/resolv.conf.linuxium ]; then
		sudo mv iso-chroot/etc/resolv.conf.linuxium iso-chroot/etc/resolv.conf
	fi
	sudo rm -f iso-chroot/root/.bash_history
	sudo rm -f iso-chroot/boot/grub/grub.cfg
	sudo rm -f iso-chroot/etc/mtab
	sudo rm -f iso-chroot/var/lib/dpkg/status-old
	for DIRECTORY in dev run tmp
	do
		sudo rm -rf iso-chroot/${DIRECTORY}
		sudo mv iso-chroot/${DIRECTORY}.linuxium iso-chroot/${DIRECTORY}
	done
}

function EXTRACT_FILES {
	DISPLAY_PROGRESS "Outputting files/directories ..."
	cd ${WIP}
	sudo mkdir output > /dev/null 2>&1
	for OUTPUT_FILE_ARRAY in $(seq 0 $((${#OUTPUT_FILES[@]}-1)))
	do
		for FILES_TO_OUTPUT in ${OUTPUT_FILES[${OUTPUT_FILE_ARRAY}]}
		do
			for OUTPUT_FILE in ${FILES_TO_OUTPUT}
			do
				if [ ! -e iso-chroot/${OUTPUT_FILE} ]; then
					echo "Output file/directory '${OUTPUT_FILE}' not found ..." >> ${ISORESPIN_LOGFILE}
				elif [ -d iso-chroot/${OUTPUT_FILE} ]; then
					OUTPUT_DIRNAME=$(dirname ${OUTPUT_FILE})
					sudo mkdir -p output/${OUTPUT_DIRNAME} > /dev/null 2>&1
					sudo cp -a iso-chroot/${OUTPUT_FILE} output/${OUTPUT_FILE} > /dev/null 2>&1
					echo "Directory '${OUTPUT_FILE}' output ..." >> ${ISORESPIN_LOGFILE}
				elif [ -f iso-chroot/${OUTPUT_FILE} ]; then
					OUTPUT_DIRNAME=$(dirname ${OUTPUT_FILE})
					sudo mkdir -p output/${OUTPUT_DIRNAME} > /dev/null 2>&1
					sudo cp iso-chroot/${OUTPUT_FILE} output/${OUTPUT_FILE} > /dev/null 2>&1
					echo "File '${OUTPUT_FILE}' output ..." >> ${ISORESPIN_LOGFILE}
				else
					echo "File '${OUTPUT_FILE}' incorrect file type ... " >> ${ISORESPIN_LOGFILE}
				fi
			done
		done
	done
}

function TRY_TO_ADD_32BIT_GRUB_PACKAGES {
	cd ${WIP}
	if [ -f iso-chroot/etc/resolv.conf ]; then
		sudo mv iso-chroot/etc/resolv.conf iso-chroot/etc/resolv.conf.linuxium
	fi
	# dev media mnt opt proc run snap srv sys tmp
	for DIRECTORY in dev run tmp
	do
		sudo mv iso-chroot/${DIRECTORY} iso-chroot/${DIRECTORY}.linuxium
		sudo cp -a iso-chroot/${DIRECTORY}.linuxium iso-chroot/${DIRECTORY}
	done
	sudo cp /etc/resolv.conf iso-chroot/etc/
	sudo mv iso-chroot/etc/apt/sources.list iso-chroot/etc/apt/sources.list.linuxium
	sudo sed 's/\(deb.*\)$/\1 universe multiverse/' iso-chroot/etc/apt/sources.list.linuxium | sudo tee iso-chroot/etc/apt/sources.list > /dev/null
	sudo rm -f iso-chroot/usr/src/.grub_package.missing iso-chroot/usr/src/.index.html
	GRUB_EFI_IA32=grub-efi-ia32
	CANDIDATE_GRUB_EFI_IA32=$(sudo chroot iso-chroot apt-cache policy ${GRUB_EFI_IA32} | grep -m1 Candidate)
	CANDIDATE_GRUB_EFI_IA32=${CANDIDATE_GRUB_EFI_IA32##  Candidate: }
	GRUB_EFI_IA32_BIN=grub-efi-ia32-bin
	CANDIDATE_GRUB_EFI_IA32_BIN=$(sudo chroot iso-chroot apt-cache policy ${GRUB_EFI_IA32_BIN} | grep -m1 Candidate)
	CANDIDATE_GRUB_EFI_IA32_BIN=${CANDIDATE_GRUB_EFI_IA32_BIN##  Candidate: }
	sudo mount --bind /dev/ iso-chroot/dev
	sudo chroot iso-chroot /bin/bash > /dev/null 2>&1 <<+
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devpts none /dev/pts
export HOME=/root
export LC_ALL=C
trap '' SIGHUP SIGINT SIGTERM
function DOWNLOAD_GRUB_PACKAGE {
	apt-get download -y \${GRUB_EFI_PACKAGE}=\${CANDIDATE_GRUB_EFI_PACKAGE}
	GRUB_PACKAGE_DOWNLOADED=\$?
	if [ \${GRUB_PACKAGE_DOWNLOADED} != 0 ]; then
		wget --timeout=10 https://launchpad.net/ubuntu/${DISTS_DISTRO}/amd64/\${GRUB_EFI_PACKAGE}/\${CANDIDATE_GRUB_EFI_PACKAGE}/+index -O .index.html > /dev/null 2>&1
		if [ -f .index.html ]; then
			GRUB_EFI_PACKAGE_TO_DOWNLOAD=\$(grep \${GRUB_EFI_PACKAGE}_\${CANDIDATE_GRUB_EFI_PACKAGE} .index.html | sed 's/^.*href="//' | sed 's/">.*//')
			rm -f .index.html
			if [ -n "\${GRUB_EFI_PACKAGE_TO_DOWNLOAD}" ]; then
				wget --timeout=10 \${GRUB_EFI_PACKAGE_TO_DOWNLOAD} > /dev/null 2>&1
				GRUB_PACKAGE_DOWNLOADED=\$?
				if [ \${GRUB_PACKAGE_DOWNLOADED} != 0 ]; then
					touch .grub_package.missing
				fi
			else
				touch .grub_package.missing
			fi
		else
			touch .grub_package.missing
		fi
	fi
}
cd /usr/src
GRUB_EFI_PACKAGE=${GRUB_EFI_IA32}
CANDIDATE_GRUB_EFI_PACKAGE=${CANDIDATE_GRUB_EFI_IA32}
DOWNLOAD_GRUB_PACKAGE
if [ ! -f .grub_package.missing ]; then
	GRUB_EFI_PACKAGE=${GRUB_EFI_IA32_BIN}
	CANDIDATE_GRUB_EFI_PACKAGE=${CANDIDATE_GRUB_EFI_IA32_BIN}
	DOWNLOAD_GRUB_PACKAGE
fi
umount /proc || umount -lf /proc
umount /sys
umount /dev/pts
+
	sudo umount iso-chroot/dev
	sudo mv iso-chroot/etc/apt/sources.list.linuxium iso-chroot/etc/apt/sources.list
	if [ -f iso-chroot/etc/resolv.conf.linuxium ]; then
		sudo mv iso-chroot/etc/resolv.conf.linuxium iso-chroot/etc/resolv.conf
	fi
	sudo rm -f iso-chroot/root/.bash_history
	sudo rm -f iso-chroot/boot/grub/grub.cfg
	sudo rm -f iso-chroot/etc/mtab
	sudo rm -f iso-chroot/var/lib/dpkg/status-old
	for DIRECTORY in dev run tmp
	do
		sudo rm -rf iso-chroot/${DIRECTORY}
		sudo mv iso-chroot/${DIRECTORY}.linuxium iso-chroot/${DIRECTORY}
	done
	if [ ! -f iso-chroot/usr/src/.grub_package.missing ]; then
		sudo mv iso-chroot/usr/src/grub-efi-ia32-bin*.deb iso-directory-structure/pool/main/g/grub2
		sudo mv iso-chroot/usr/src/grub-efi-ia32*.deb iso-directory-structure/pool/main/g/grub2
		sudo rm -f iso-directory-structure/dists/${DISTS_DISTRO}/main/binary-amd64/Packages
		sudo gzip -d -c iso-directory-structure/dists/${DISTS_DISTRO}/main/binary-amd64/Packages.gz | sudo tee iso-directory-structure/dists/${DISTS_DISTRO}/main/binary-amd64/Packages > /dev/null
		sudo chroot iso-chroot apt-cache show ${GRUB_EFI_IA32}=${CANDIDATE_GRUB_EFI_IA32} | sudo tee -a iso-directory-structure/dists/${DISTS_DISTRO}/main/binary-amd64/Packages > /dev/null
		sudo chroot iso-chroot apt-cache show ${GRUB_EFI_IA32_BIN}=${CANDIDATE_GRUB_EFI_IA32_BIN} | sudo tee -a iso-directory-structure/dists/${DISTS_DISTRO}/main/binary-amd64/Packages > /dev/null
		sudo rm -f iso-directory-structure/dists/${DISTS_DISTRO}/main/binary-amd64/Packages.gz
		sudo gzip -c iso-directory-structure/dists/${DISTS_DISTRO}/main/binary-amd64/Packages | sudo tee iso-directory-structure/dists/${DISTS_DISTRO}/main/binary-amd64/Packages.gz > /dev/null
		sudo rm -f iso-directory-structure/dists/${DISTS_DISTRO}/main/binary-amd64/Packages
	else
		sudo rm -f iso-chroot/usr/src/.grub_package.missing
	fi
}

function FETCH_REFIND_FILES {
	REFIND_DIR=$(ls -C1dr ${CWD}/refind-bin-* 2> /dev/null | head -1)
	if [ ! -f ${REFIND_DIR}/refind/refind.conf-sample ]; then
		REFIND_URL="https://sourceforge.net/projects/refind/files"
		REFIND_DOWNLOAD_URL="https://downloads.sourceforge.net/project/refind"
		sudo rm -f ${WIP}/refind_index.html
		sudo wget --timeout=10 "${REFIND_URL}" -O ${WIP}/refind_index.html > /dev/null 2>&1
		if [ ! -f ${WIP}/refind_index.html ]; then
			DISPLAY_MESSAGE "${0}: Cannot fetch rEFInd index ... check your internet connection and try again."
			CLEAN_EXIT
		fi
		REFIND_LATEST_VERSION=$(grep /projects/refind/files/latest/download ${WIP}/refind_index.html | sed 's/.*title="\/\([^\/]*\).*/\1/')
		REFIND_ZIPFILE=$(grep /projects/refind/files/latest/download ${WIP}/refind_index.html | sed 's/.*\///' | sed 's/:.*//')
		sudo rm -rf ${WIP}/${REFIND_ZIPFILE}
		sudo wget --timeout=10 ${REFIND_DOWNLOAD_URL}/${REFIND_LATEST_VERSION}/${REFIND_ZIPFILE} -O ${WIP}/${REFIND_ZIPFILE} > /dev/null 2>&1
		sudo unzip ${WIP}/${REFIND_ZIPFILE} -d ${WIP} > /dev/null 2>&1
		sudo rm -f ${WIP}/refind_index.html ${WIP}/${REFIND_ZIPFILE}
		REFIND_DIR=${WIP}/"refind-bin-${REFIND_LATEST_VERSION}"
		REFIND_DIR=$(readlink -f ${REFIND_DIR})
		if [ ! -d ${REFIND_DIR} ]; then
			REFIND_DIR=$(ls ${WIP})
			REFIND_DIR=$(readlink -f ${WIP}/${REFIND_DIR})
		fi
	else
		REFIND_DIR=$(readlink -f ${REFIND_DIR})
	fi
	if [ ! -d ${REFIND_DIR} ]; then
		DISPLAY_MESSAGE "${0}: Cannot access rEFInd directory."
		CLEAN_EXIT
	fi
}

function UPDATE_BOOTLOADER {
	DISPLAY_PROGRESS "Updating bootloader/bootmanager ..."
	cd ${WIP}
	DISTS_DISTRO=$(basename $(find  iso-directory-structure/dists -maxdepth 1 -type d | sed 1d))
	if [ -z "${DISTS_DISTRO}" ]; then
		DISPLAY_MESSAGE "${0}: Cannot find bootloader/bootmanager."
		CLEAN_EXIT
	elif [ ! -f iso-directory-structure/dists/${DISTS_DISTRO}/main/binary-amd64/Packages.gz ]; then
		DISPLAY_MESSAGE "${0}: Cannot update bootloader/bootmanager."
		CLEAN_EXIT
	fi
	if [ -d iso-directory-structure/pool/main/g/grub2 ]; then
		TRY_TO_ADD_32BIT_GRUB_PACKAGES
	fi
	if ${ADD_PERSISTENCE}; then
		ADD_KERNEL_BOOT_PARAMETER=true
		KERNEL_BOOT_PARAMETER+=" ${PERSISTENCE}"
	fi
	REFIND_BOOT_PARAMETERS="boot=casper"
	CURRENT_KERNEL_BOOT_PARAMETER=$(grep -m 1 "^GRUB_CMDLINE_LINUX_DEFAULT=" iso-chroot/etc/default/grub)
	CURRENT_KERNEL_BOOT_PARAMETER=${CURRENT_KERNEL_BOOT_PARAMETER#GRUB_CMDLINE_LINUX_DEFAULT=}
	CURRENT_KERNEL_BOOT_PARAMETER=${CURRENT_KERNEL_BOOT_PARAMETER//\"/}
	if [ -n "${CURRENT_KERNEL_BOOT_PARAMETER}" ]; then
		REFIND_BOOT_PARAMETERS+=" ${CURRENT_KERNEL_BOOT_PARAMETER}"
		if ${ADD_KERNEL_BOOT_PARAMETER}; then
			KERNEL_BOOT_PARAMETER="${KERNEL_BOOT_PARAMETER:1}"
			sudo sed -i "s/${CURRENT_KERNEL_BOOT_PARAMETER}/${CURRENT_KERNEL_BOOT_PARAMETER} ${KERNEL_BOOT_PARAMETER}/" iso-directory-structure/boot/grub/grub.cfg
			sudo sed -i "s/${CURRENT_KERNEL_BOOT_PARAMETER}/${CURRENT_KERNEL_BOOT_PARAMETER} ${KERNEL_BOOT_PARAMETER}/" iso-chroot/etc/default/grub
			REFIND_BOOT_PARAMETERS+=" ${KERNEL_BOOT_PARAMETER}"
			echo "Kernel boot parameters '${KERNEL_BOOT_PARAMETER}' added ..." >> ${ISORESPIN_LOGFILE}
		fi
		if ${DELETE_KERNEL_BOOT_PARAMETER}; then
			sudo sed -i "s/ ${CURRENT_KERNEL_BOOT_PARAMETER}//" iso-directory-structure/boot/grub/grub.cfg
			if ${ADD_KERNEL_BOOT_PARAMETER}; then
				sudo sed -i "s/${CURRENT_KERNEL_BOOT_PARAMETER} //" iso-chroot/etc/default/grub
			else
				sudo sed -i "s/${CURRENT_KERNEL_BOOT_PARAMETER}//" iso-chroot/etc/default/grub
			fi
			REFIND_BOOT_PARAMETERS=${REFIND_BOOT_PARAMETERS/ ${CURRENT_KERNEL_BOOT_PARAMETER}/}
			echo "Initial kernel boot parameters '${CURRENT_KERNEL_BOOT_PARAMETER}' deleted ..." >> ${ISORESPIN_LOGFILE}
		fi
	else
		if ${ADD_KERNEL_BOOT_PARAMETER}; then
			KERNEL_BOOT_PARAMETER="${KERNEL_BOOT_PARAMETER:1}"
			sudo sed -i "s/boot=casper/boot=casper ${KERNEL_BOOT_PARAMETER}/" iso-directory-structure/boot/grub/grub.cfg
			sudo sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=\"\"/GRUB_CMDLINE_LINUX_DEFAULT=\"${KERNEL_BOOT_PARAMETER}\"/" iso-chroot/etc/default/grub
			REFIND_BOOT_PARAMETERS+=" ${KERNEL_BOOT_PARAMETER}"
			echo "Kernel boot parameters '${KERNEL_BOOT_PARAMETER}' added ..." >> ${ISORESPIN_LOGFILE}
		fi
		if ${DELETE_KERNEL_BOOT_PARAMETER}; then
			echo "No initial kernel boot parameters found for deletion ..." >> ${ISORESPIN_LOGFILE}
		fi
	fi
	if ${ADD_KERNEL_BOOT_PARAMETER}; then
		case "${ISO_DISTRO}" in
			"Mint")
				PRESEED_SEED="linuxmint.seed"
				;;
			"neon"|"elementary")
				PRESEED_SEED=""
				;;
			*)
				PRESEED_SEED="${ISO_DISTRO,,}.seed"
				;;
		esac
		if [ -n "${PRESEED_SEED}" ]; then
			sudo cp iso-chroot/etc/default/grub iso-chroot/etc/default/grub.isorespin
			sudo cat <<+ | sudo tee -a iso-directory-structure/preseed/${PRESEED_SEED} > /dev/null
# Linuxium 'isorespin.sh' customization: Begin
ubiquity	ubiquity/success_command string cp /etc/default/grub.isorespin /target/etc/default/grub
# Linuxium 'isorespin.sh' customization: End
+
		fi
	fi
	if ${USE_REFIND_BOOTLOADER}; then
		FETCH_REFIND_FILES
		# add 32-bit GRUB bootloader
		sudo cp -a grub/boot iso-refind
		sudo cp iso-directory-structure/boot/grub/grub.cfg iso-refind/grub
		sudo sed -i '/linux/i \\tsearch --no-floppy --label LINUXIUMISO --set' iso-refind/grub/grub.cfg
		# add 64-bit rEFInd bootmanager
		case "${ISO_DISTRO}" in
			"Ubuntu")
				REFIND_ICON="os_ubuntu.png"
				REFIND_OPTIONS="file=\/cdrom\/preseed\/ubuntu.seed ${REFIND_BOOT_PARAMETERS}"
				;;
			"Kubuntu")
				REFIND_ICON="os_kubuntu.png"
				REFIND_OPTIONS="file=\/cdrom\/preseed\/kubuntu.seed ${REFIND_BOOT_PARAMETERS}"
				;;
			"Lubuntu")
				REFIND_ICON="os_lubuntu.png"
				REFIND_OPTIONS="file=\/cdrom\/preseed\/lubuntu.seed ${REFIND_BOOT_PARAMETERS}"
				;;
			"Ubuntu-Budgie")
				REFIND_ICON="os_linux.png"
				REFIND_OPTIONS="file=\/cdrom\/preseed\/ubuntu-budgie.seed ${REFIND_BOOT_PARAMETERS}"
				;;
			"Ubuntu-GNOME")
				REFIND_ICON="os_linux.png"
				REFIND_OPTIONS="file=\/cdrom\/preseed\/ubuntu-gnome.seed ${REFIND_BOOT_PARAMETERS}"
				;;
			"Ubuntu-MATE")
				REFIND_ICON="os_linux.png"
				REFIND_OPTIONS="file=\/cdrom\/preseed\/ubuntu-mate.seed ${REFIND_BOOT_PARAMETERS}"
				;;
			"Xubuntu")
				REFIND_ICON="os_xubuntu.png"
				REFIND_OPTIONS="file=\/cdrom\/preseed\/xubuntu.seed ${REFIND_BOOT_PARAMETERS}"
				;;
			"Mint")
				REFIND_ICON="os_linuxmint.png"
				REFIND_OPTIONS="file=\/cdrom\/preseed\/linuxmint.seed iso-scan\/filename=${iso_path} ${REFIND_BOOT_PARAMETERS}"
				;;
			"neon")
				REFIND_ICON="os_linux.png"
				REFIND_OPTIONS="${REFIND_BOOT_PARAMETERS}"
				;;
			"elementary")
				REFIND_ICON="os_linux.png"
				REFIND_OPTIONS="file=\/cdrom\/preseed\/ubuntu.seed ${REFIND_BOOT_PARAMETERS}"
				;;
			"BackBox")
				REFIND_ICON="os_linux.png"
				REFIND_OPTIONS="file=\/cdrom\/preseed\/backbox.seed ${REFIND_BOOT_PARAMETERS}"
				;;
			"Peppermint")
				REFIND_ICON="os_linux.png"
				REFIND_OPTIONS="file=\/cdrom\/preseed\/peppermint.seed ${REFIND_BOOT_PARAMETERS}"
				;;
			*)
				DISPLAY_MESSAGE "${0}: '${ISO_DISTRO}' unknown."
				CLEAN_EXIT
				;;
		esac
		sudo cp -a ${REFIND_DIR}/refind/icons iso-refind
		sudo cp ${REFIND_DIR}/refind/refind_x64.efi iso-refind/bootx64.efi
		sudo cp -a ${REFIND_DIR}/refind/drivers_x64 iso-refind
		sudo sed 's/^#scanfor internal,external,optical,manual/scanfor manual/' ${REFIND_DIR}/refind/refind.conf-sample | sudo tee iso-refind/refind.conf > /dev/null
		sudo sed -i "/menuentry Linux /i \\
\\
menuentry \"LINUXIUM ISO\" {\\
    icon EFI\/boot\/icons\/${REFIND_ICON}\\
    volume LINUXIUMISO\\
    loader \/${ISO_SQUASHFS_DIRECTORY}\/${ISO_VMLINUZ}\\
    initrd \/${ISO_SQUASHFS_DIRECTORY}\/${ISO_INITRD}\\
    options \"${REFIND_OPTIONS}\"\\
}\\
		" iso-refind/refind.conf
		echo "Bootmanager 'rEFInd' added ..." >> ${ISORESPIN_LOGFILE}
	else # update GRUB with 32-bit GRUB bootloader
		sudo mkdir mnt
		sudo mount iso-directory-structure/boot/grub/efi.img mnt
		sudo cp -a mnt/efi .
		sudo umount mnt
		sudo rm -f iso-directory-structure/boot/grub/efi.img
		sudo dd if=/dev/zero of=iso-directory-structure/boot/grub/efi.img bs=1 count=3109888 > /dev/null 2>&1
		sudo mkdosfs iso-directory-structure/boot/grub/efi.img > /dev/null 2>&1
		sudo mount iso-directory-structure/boot/grub/efi.img mnt
		sudo cp -a efi mnt
		sudo cp grub_bootia32.efi mnt/efi/boot/bootia32.efi
		sudo umount mnt
		sudo rmdir mnt
		sudo rm -rf efi
		sudo cp efi_bootia32.efi iso-directory-structure/EFI/BOOT/bootia32.efi
		echo "Bootloader 'GRUB' added ..." >> ${ISORESPIN_LOGFILE}
	fi
	sudo rm -f grub_bootia32.efi efi_bootia32.efi
	sudo rm -rf grub
}

function SPIN_ISO {
	DISPLAY_PROGRESS "Spinning ISO ..."
	cd ${WIP}
	# create the mmanifest/packages
	sudo chmod +w iso-directory-structure/${ISO_SQUASHFS_DIRECTORY}/filesystem.${FILESYSTEM_FILES}
	sudo chroot iso-chroot dpkg-query -W --showformat='${Package} ${Version}\n' | sudo tee iso-directory-structure/${ISO_SQUASHFS_DIRECTORY}/filesystem.${FILESYSTEM_FILES} > /dev/null
	# create the filesystem
	sudo mksquashfs iso-chroot iso-directory-structure/${ISO_SQUASHFS_DIRECTORY}/filesystem.squashfs
	printf $(sudo du -sx --block-size=1 iso-chroot | cut -f1) | sudo tee iso-directory-structure/${ISO_SQUASHFS_DIRECTORY}/filesystem.size > /dev/null
	sudo rm -rf iso-chroot
	cd iso-directory-structure
	sudo rm -f md5sum.txt
	find -type f -print0 | sudo xargs -0 md5sum | grep -v isolinux/boot.cat | sudo tee md5sum.txt > /dev/null
	cd ..
	# create the iso
	if ${USE_REFIND_BOOTLOADER}; then
		SECTOR_ALIGNMENT=2048
		SIZE_OF_ISO_REFIND=$(du -s iso-refind | awk '{print $1}')
		SECTOR_SIZE_OF_ISO_REFIND=$((${SIZE_OF_ISO_REFIND}*2))
		END_SECTOR_OF_ISO_REFIND=$((${SECTOR_ALIGNMENT}+${SECTOR_SIZE_OF_ISO_REFIND}))
		NEXT_SECTOR_AFTER_ISO_REFIND=$((((${END_SECTOR_OF_ISO_REFIND} + ${SECTOR_ALIGNMENT} -1) / ${SECTOR_ALIGNMENT}) * ${SECTOR_ALIGNMENT}))
		SIZE_OF_ISO_DIRECTORY_STRUCTURE=$(du -s iso-directory-structure | awk '{print $1}')
		# Add 8% for filesystem overhead
		SIZE_OF_ISO_DIRECTORY_STRUCTURE=$((${SIZE_OF_ISO_DIRECTORY_STRUCTURE}+(${SIZE_OF_ISO_DIRECTORY_STRUCTURE}*2/25)))
		SECTOR_SIZE_OF_ISO_DIRECTORY_STRUCTURE=$((${SIZE_OF_ISO_DIRECTORY_STRUCTURE}*2))
		END_SECTOR_OF_ISO_DIRECTORY_STRUCTURE=$((${NEXT_SECTOR_AFTER_ISO_REFIND}+${SECTOR_SIZE_OF_ISO_DIRECTORY_STRUCTURE}))
		NEXT_SECTOR_AFTER_ISO_DIRECTORY_STRUCTURE=$((((${END_SECTOR_OF_ISO_DIRECTORY_STRUCTURE} + ${SECTOR_ALIGNMENT} -1) / ${SECTOR_ALIGNMENT}) * ${SECTOR_ALIGNMENT}))
		if ${ADD_PERSISTENCE}; then
			END_SECTOR_OF_PERSISTENCE=$((${NEXT_SECTOR_AFTER_ISO_DIRECTORY_STRUCTURE}+${PERSISTENCE_SECTOR_SIZE}))
			sudo dd if=/dev/zero of=../${LINUXIUM_ISO} bs=512 count=$((34+${END_SECTOR_OF_PERSISTENCE})) > /dev/null 2>&1
			(echo n; echo 1; echo ${SECTOR_ALIGNMENT}; echo ${END_SECTOR_OF_ISO_REFIND}; echo ef00; echo n; echo 2; echo ${NEXT_SECTOR_AFTER_ISO_REFIND}; echo ${END_SECTOR_OF_ISO_DIRECTORY_STRUCTURE}; echo 8300; echo n; echo 3; echo ${NEXT_SECTOR_AFTER_ISO_DIRECTORY_STRUCTURE}; echo ${END_SECTOR_OF_PERSISTENCE}; echo 8300; echo w; echo Y) | sudo gdisk ../${LINUXIUM_ISO} > /dev/null 2>&1
		else
			sudo dd if=/dev/zero of=../${LINUXIUM_ISO} bs=512 count=$((34+${END_SECTOR_OF_ISO_DIRECTORY_STRUCTURE})) > /dev/null 2>&1
			(echo n; echo 1; echo ${SECTOR_ALIGNMENT}; echo ${END_SECTOR_OF_ISO_REFIND}; echo ef00; echo n; echo 2; echo ${NEXT_SECTOR_AFTER_ISO_REFIND}; echo ${END_SECTOR_OF_ISO_DIRECTORY_STRUCTURE}; echo 8300; echo w; echo Y) | sudo gdisk ../${LINUXIUM_ISO} > /dev/null 2>&1
		fi
		sudo sync
		sudo sync
		sudo losetup -f > /dev/null 2>&1 || DISPLAY_MESSAGE "${0}: No free loop devices."
		sudo losetup -f > /dev/null 2>&1 || CLEAN_EXIT
		LOOP_DEVICE=$(sudo losetup -f)
		sudo mkdir mnt
		DISPLAY_PROGRESS "Adding ISO boot partition ..."
		sudo losetup ${LOOP_DEVICE} ../${LINUXIUM_ISO} -o $((${SECTOR_ALIGNMENT}*512)) --sizelimit $(((${END_SECTOR_OF_ISO_REFIND}-${SECTOR_ALIGNMENT})*512))
		sudo mkfs.vfat ${LOOP_DEVICE} > /dev/null 2>&1
		sudo mount ${LOOP_DEVICE} mnt
		sudo mkdir -p mnt/EFI/boot
		sudo cp -a iso-refind/. mnt/EFI/boot
		sudo sync
		sudo sync
		sudo umount mnt
		sudo losetup -d ${LOOP_DEVICE}
		DISPLAY_PROGRESS "Adding ISO file system partition ..."
		sudo losetup ${LOOP_DEVICE} ../${LINUXIUM_ISO} -o $((${NEXT_SECTOR_AFTER_ISO_REFIND}*512)) --sizelimit $(((${END_SECTOR_OF_ISO_DIRECTORY_STRUCTURE}-${NEXT_SECTOR_AFTER_ISO_REFIND})*512))
		sudo mkfs.ext4 ${LOOP_DEVICE} -L LINUXIUMISO > /dev/null 2>&1
		sudo mount ${LOOP_DEVICE} mnt
		sudo cp -a iso-directory-structure/. mnt
		sudo sync
		sudo sync
		sudo umount mnt
		sudo losetup -d ${LOOP_DEVICE}
		if ${ADD_PERSISTENCE}; then
			DISPLAY_PROGRESS "Adding persistence partition ..."
			sudo losetup ${LOOP_DEVICE} ../${LINUXIUM_ISO} -o $((${NEXT_SECTOR_AFTER_ISO_DIRECTORY_STRUCTURE}*512)) --sizelimit $(((${END_SECTOR_OF_PERSISTENCE}-${NEXT_SECTOR_AFTER_ISO_DIRECTORY_STRUCTURE})*512))
			sudo mkfs.ext4 ${LOOP_DEVICE} -L ${PERSISTENCE_PARTITION} > /dev/null 2>&1
			sudo losetup -d ${LOOP_DEVICE}
			echo "Persistence partition of '${PERSISTENCE_SIZE}${PERSISTENCE_UNIT}B' added ..." >> ${ISORESPIN_LOGFILE}
		fi
		sudo rmdir mnt
		sudo rm -rf $(basename ${REFIND_DIR})
		sudo rm -rf iso-refind
		sudo rm -f isohdpfx.bin
	else
		cd iso-directory-structure
		sudo xorriso -as mkisofs -iso-level 3 -full-iso9660-filenames -volid "${ISO_VOLID}" \
		-isohybrid-mbr ../isohdpfx.bin \
		-eltorito-boot isolinux/isolinux.bin -no-emul-boot -eltorito-catalog isolinux/boot.cat -no-emul-boot \
		-boot-load-size 4 -boot-info-table -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot -isohybrid-gpt-basdat \
		-o ../../${LINUXIUM_ISO} .
		sudo chown $(stat -c '%u' ${ISO}):$(stat -c '%g' ${ISO}) ../../${LINUXIUM_ISO}
		cd ..
		sudo rm -f isohdpfx.bin
	fi
	sudo rm -rf iso-directory-structure
	cd ${CWD}
	sudo mv ${WIP}/output/* ${WIP}/output/.* ${WIP} > /dev/null 2>&1
	sudo rm -rf ${WIP}/output
	sudo rm -f ${CWD}/.isorespin.sh.lock
	! ${EXTRACT_FILE} && sudo rm -rf ${WIP}
	if [ -z "${WORK_DIRECTORY}" ]; then
		CLOSE_DISPLAY_BOX
		${GUI} && zenity --info --title="isorespin.sh" --text="Respun ISO created as '${LINUXIUM_ISO}' ... see logfile '$(basename ${ISORESPIN_LOGFILE})' for details." 2> /dev/null
		echo "${0}: Respun ISO created as '${LINUXIUM_ISO}' ... see logfile '$(basename ${ISORESPIN_LOGFILE})' for details."
		echo "Respun ISO created as '${LINUXIUM_ISO}'." >> ${ISORESPIN_LOGFILE} 2> /dev/null
	else
		CLOSE_DISPLAY_BOX
		${GUI} && zenity --info --title="isorespin.sh" --text="Respun ISO created as '${WORK_DIRECTORY}/${LINUXIUM_ISO}' ... see logfile '$(basename ${ISORESPIN_LOGFILE})' for details." 2> /dev/null
		echo "${0}: Respun ISO created as '${WORK_DIRECTORY}/${LINUXIUM_ISO}' ... see logfile '$(basename ${ISORESPIN_LOGFILE})' for details."
		echo "Respun ISO created as '${WORK_DIRECTORY}/${LINUXIUM_ISO}'." >> ${ISORESPIN_LOGFILE} 2> /dev/null
	fi
}

# isorespin
CHECK_PACKAGE_DEPENDENCIES
CHECK_FOR_EXCLUSIVITY
NUMBER_OF_ARGUMENTS=${#}
if [ "${NUMBER_OF_ARGUMENTS}" == 0 ]; then
	if [ -n "${DISPLAY}" ]; then
		if [ ! $(sudo bash -c "command -v zenity") ]; then
			DISPLAY_MESSAGE "${0}: Install package 'zenity' for a minimalist GUI or an ISO must be specified using '-i' or '--iso'."
			DIRTY_EXIT
		else
			GUI=true
			USE_GUI_TO_GENERATE_CMDLINE
			CHECK_CMDLINE ${CMDLINE}
		fi
	else
		DISPLAY_MESSAGE "${0}: Cannot open display for GUI."
		USAGE
		rm -f ${ISORESPIN_LOGFILE}
		DIRTY_EXIT
	fi
else
	CHECK_CMDLINE "$@"
fi
PROCESS_CMDLINE
EXTRACT_ISO
EXTRACT_ISORESPIN_FILES
UPDATE_BOOTLOADER
if ${UPDATE_KERNEL}; then
	FETCH_MAINLINE_DEBS
	INSTALL_MAINLINE_KERNEL
fi
if ${PURGE_PACKAGE}; then
	PURGE_PACKAGES
fi
if ${UPGRADE}; then
	UPGRADE_DISTRO
fi
if ${ADD_KEY}; then
	ADD_KEYS
fi
if ${ADD_REPOSITORY}; then
	ADD_REPOSITORIES
fi
if ${ADD_PACKAGE}; then
	INSTALL_PACKAGES
fi
if ${REMOVE_ROLLING_REPOSITORY}; then
	REMOVE_REPOSITORY
fi
if ${ADD_LOCAL_PACKAGE}; then
	INSTALL_LOCAL_PACKAGES
fi
if ${ADD_DOWNLOAD}; then
	DOWNLOAD_PACKAGES
fi
if ${ADD_FILE}; then
	ADD_FILES
fi
if ${ADD_COMMAND}; then
	RUN_COMMANDS
fi
if ${EXTRACT_FILE}; then
	EXTRACT_FILES
fi
SPIN_ISO
exit 0
PK